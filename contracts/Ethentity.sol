// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Ethentity is ERC721, Ownable, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    // HARD-KODIRANA PERPER (PRP) ADRESA — promijeni po mreži ako treba
    address public constant PRP = 0xf412de660d3914E2E5CdB5A476E35d291150C88D;

    Counters.Counter private _domainIds;

    struct Domain {
        string name;
        uint256 regPrice;     // PRP cijena registracije
        uint256 renewPrice;   // PRP cijena za 1 godinu obnove
        bool isOwned;
        uint64  expiresAt;
        string ipfsHash;
        uint256 storageLimit; // MB
        uint256 usedStorage;  // MB
        bool forSale;         // sekundarna prodaja
        uint256 salePrice;    // PRP cijena sekundarne prodaje
    }

    mapping(uint256 => Domain) public domains;
    mapping(string => uint256) public nameToId; // normalized name -> id
    mapping(uint256 => string[]) public subdomains;
    mapping(uint256 => mapping(string => string)) public subdomainContents;

    mapping(address => uint256[]) public userDomains;
    mapping(uint256 => uint256) private _userIndex; // id -> index u userDomains[vlasnik]

    event DomainListed(uint256 indexed id, string indexed name, uint256 regPrice, uint256 renewPrice);
    event DomainRegistered(uint256 indexed id, string indexed name, address indexed owner, uint64 expiresAt);
    event DomainRenewed(uint256 indexed id, uint64 newExpiry);
    event DomainForSale(uint256 indexed id, uint256 price, bool active);
    event DomainBought(uint256 indexed id, address indexed from, address indexed to, uint256 price);
    event ContentUploaded(uint256 indexed id, string ipfsHash, uint256 newUsedMB);
    event StorageUpgraded(uint256 indexed id, uint256 newLimitMB);
    event SubdomainSet(uint256 indexed parentId, string subdomain, string ipfsHash);

    constructor() ERC721("Ethentity Domains", "ENT") {
        _pause(); // možeš unpause kad završiš listanje
    }

    // ---------- helpers ----------

    function _normalize(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        require(b.length > 0 && b.length <= 253, "name len");
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c >= 0x41 && c <= 0x5A) {
                b[i] = bytes1(uint8(c) + 32); // A-Z -> a-z
            } else {
                bool ok = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D;
                require(ok, "invalid char");
            }
        }
        return string(b);
    }

    modifier onlyDomainOwner(uint256 id) {
        require(ownerOf(id) == msg.sender, "Not domain owner");
        _;
    }

    modifier notExpired(uint256 id) {
        require(domains[id].expiresAt >= block.timestamp, "Domain expired");
        _;
    }

    // ---------- administracija ----------

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function listDomain(string memory rawName, uint256 regPrice, uint256 renewPricePerYear)
        external
        onlyOwner
        whenNotPaused
    {
        string memory name = _normalize(rawName);
        require(nameToId[name] == 0, "Domain taken");

        _domainIds.increment();
        uint256 newId = _domainIds.current();

        domains[newId] = Domain({
            name: name,
            regPrice: regPrice,
            renewPrice: renewPricePerYear,
            isOwned: false,
            expiresAt: 0,
            ipfsHash: "",
            storageLimit: 100,
            usedStorage: 0,
            forSale: false,
            salePrice: 0
        });

        nameToId[name] = newId;
        emit DomainListed(newId, name, regPrice, renewPricePerYear);
    }

    // ---------- primarna kupovina/registracija (SAMO PRP) ----------

    function mintDomain(uint256 id) external nonReentrant whenNotPaused {
        require(id != 0 && id <= _domainIds.current(), "Invalid ID");
        Domain storage d = domains[id];
        require(!d.isOwned, "Already owned");
        require(d.regPrice > 0, "No price");

        IERC20(PRP).safeTransferFrom(msg.sender, address(this), d.regPrice);

        d.isOwned = true;
        d.expiresAt = uint64(block.timestamp + 365 days);
        _safeMint(msg.sender, id);
        _addUserDomain(msg.sender, id);

        emit DomainRegistered(id, d.name, msg.sender, d.expiresAt);
    }

    // ---------- obnova (SAMO PRP) ----------

    function renewYears(uint256 id, uint256 years_) external nonReentrant onlyDomainOwner(id) whenNotPaused {
        require(years_ >= 1 && years_ <= 10, "years 1..10");
        Domain storage d = domains[id];

        uint256 total = d.renewPrice * years_;
        IERC20(PRP).safeTransferFrom(msg.sender, address(this), total);

        uint64 base = d.expiresAt >= block.timestamp ? d.expiresAt : uint64(block.timestamp);
        d.expiresAt = base + uint64(years_) * 365 days;

        emit DomainRenewed(id, d.expiresAt);
    }

    // ---------- sekundarna prodaja (SAMO PRP) ----------

    function listForSale(uint256 id, uint256 price) external onlyDomainOwner(id) whenNotPaused {
        Domain storage d = domains[id];
        d.forSale = (price > 0);
        d.salePrice = price;
        emit DomainForSale(id, price, d.forSale);
    }

    function buyDomain(uint256 id) external nonReentrant whenNotPaused {
        Domain storage d = domains[id];
        require(d.isOwned, "Not owned");
        require(d.forSale && d.salePrice > 0, "Not for sale");

        address seller = ownerOf(id);

        IERC20(PRP).safeTransferFrom(msg.sender, seller, d.salePrice);

        _transfer(seller, msg.sender, id);

        d.forSale = false;
        uint256 soldFor = d.salePrice;
        d.salePrice = 0;

        emit DomainBought(id, seller, msg.sender, soldFor);
    }

    // ---------- IPFS / storage (SAMO PRP za upgrade) ----------

    function setIPFSHash(uint256 id, string calldata ipfsHash, uint256 fileSizeMB)
        external
        onlyDomainOwner(id)
        notExpired(id)
        whenNotPaused
    {
        Domain storage d = domains[id];
        require(d.usedStorage + fileSizeMB <= d.storageLimit, "Storage limit");
        d.ipfsHash = ipfsHash;
        d.usedStorage += fileSizeMB;
        emit ContentUploaded(id, ipfsHash, d.usedStorage);
    }

    // Napomena: pretpostavka 18 decimala na PRP — 1 PRP/MB = 1e18 wei PRP
    function upgradeStorage(uint256 id, uint256 additionalMB)
        external
        nonReentrant
        onlyDomainOwner(id)
        whenNotPaused
    {
        uint256 cost = additionalMB * 1e18;
        IERC20(PRP).safeTransferFrom(msg.sender, address(this), cost);
        domains[id].storageLimit += additionalMB;
        emit StorageUpgraded(id, domains[id].storageLimit);
    }

    function addSubdomain(uint256 parentId, string calldata subdomain, string calldata ipfsHash, uint256 fileSizeMB)
        external
        onlyDomainOwner(parentId)
        notExpired(parentId)
        whenNotPaused
    {
        Domain storage d = domains[parentId];
        require(d.usedStorage + fileSizeMB <= d.storageLimit, "Storage limit");
        subdomains[parentId].push(subdomain);
        subdomainContents[parentId][subdomain] = ipfsHash;
        d.usedStorage += fileSizeMB;
        emit SubdomainSet(parentId, subdomain, ipfsHash);
    }

    // ---------- čitanje ----------

    function getDomain(uint256 id) external view returns (Domain memory) { return domains[id]; }

    function idOf(string calldata rawName) external view returns (uint256) {
        string memory name = _normalize(rawName);
        return nameToId[name];
    }

    function getSubdomains(uint256 id) external view returns (string[] memory) { return subdomains[id]; }

    // ---------- povlačenje PRP ----------

    function withdrawPRP(address to) external onlyOwner {
        uint256 bal = IERC20(PRP).balanceOf(address(this));
        IERC20(PRP).safeTransfer(to, bal);
    }

    // ---------- ERC721 hooks: sync userDomains + poštuj pause ----------

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        require(!paused(), "paused");
        if (from != address(0)) { _removeUserDomain(from, tokenId); }
        if (to != address(0))   { _addUserDomain(to, tokenId); }
    }

    function _addUserDomain(address u, uint256 id) internal {
        _userIndex[id] = userDomains[u].length;
        userDomains[u].push(id);
    }

    function _removeUserDomain(address u, uint256 id) internal {
        uint256 idx = _userIndex[id];
        uint256 last = userDomains[u].length - 1;
        if (idx != last) {
            uint256 lastId = userDomains[u][last];
            userDomains[u][idx] = lastId;
            _userIndex[lastId] = idx;
        }
        userDomains[u].pop();
        delete _userIndex[id];
    }
}
