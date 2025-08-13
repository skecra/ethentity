// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Ethentity is ERC721, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    Counters.Counter private _domainIds;

    // Admin
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Only owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    // Token koji koristimo za naplatu (PRP, 18 dec)
    IERC20 public immutable prpToken = IERC20(0xf412de660d3914E2E5CdB5A476E35d291150C88D);

    struct Domain {
        string  name;          // uvijek lowercase
        uint256 cost;          // cijena pri registraciji (PRP)
        uint64  expiresAt;     // timestamp
        string  ipfsHash;      // legacy polje (ostavljeno zbog kompat.)
        string  siteCID;       // aktivni CID
        string  siteURL;       // npr. https://ipfs.io/ipfs/<cid>/
        uint32  storageLimit;  // MB (informativno)
        uint32  usedStorage;   // MB (informativno)
        address receiver;      // gdje primati PRP uplate za ovaj domen
    }

    // Mappings
    mapping(uint256 => Domain) public domains;           // id -> domain
    mapping(string  => uint256) public nameToId;         // lowercase name -> id
    mapping(uint256 => string[]) public subdomains;      // id -> lista subdomena
    mapping(uint256 => mapping(string => string)) public subdomainContents; // id -> sub -> cid
    mapping(address => uint256[]) public userDomains;    // (održavamo u _afterTokenTransfer)

    // Premium riječi (substring match pri racunanju cijene)
    string[] private premiumList;
    mapping(string => bool) public premiumWords;         // quick lookup

    // Events
    event DomainRegistered(uint256 indexed id, string name, address owner, uint256 price);
    event ReceiverChanged(uint256 indexed id, address receiver);
    event SiteCIDChanged(uint256 indexed id, string cid);
    event SiteURLChanged(uint256 indexed id, string url);
    event ContentUploaded(uint256 indexed id, string cid);
    event StorageUpgraded(uint256 indexed id, uint256 newLimit);
    event PremiumWordAdded(string word);
    event PremiumWordRemoved(string word);

    constructor() ERC721("Ethentity Domains", "ENT") {
        owner = msg.sender;

        // default premium rijeci
        string[6] memory defaults = ["crypto","nft","blockchain","dao","web3","eth"];
        for (uint i=0;i<defaults.length;i++){
            premiumWords[defaults[i]] = true;
            premiumList.push(defaults[i]);
        }
    }

    // ===== Helperi =====
    function _toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint i=0;i<b.length;i++){
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) { b[i] = bytes1(c + 32); }
        }
        return string(b);
    }
    function _contains(string memory where, string memory what) internal pure returns (bool) {
        bytes memory w = bytes(where);
        bytes memory a = bytes(what);
        if (a.length == 0 || a.length > w.length) return false;
        for (uint i=0; i<=w.length - a.length; i++){
            bool ok = true;
            for (uint j=0; j<a.length; j++){
                if (w[i+j] != a[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }

    // ===== Cijena =====
    function calculatePrice(string memory name) public view returns (uint256) {
        bytes memory b = bytes(name);
        uint256 basePrice;
        if (b.length <= 3)       basePrice = 300 ether;
        else if (b.length <= 5)  basePrice = 150 ether;
        else                     basePrice = 50 ether;

        string memory lowerName = _toLower(name);
        for (uint i=0;i<premiumList.length;i++){
            if (_contains(lowerName, premiumList[i])) {
                basePrice += 200 ether;
            }
        }
        return basePrice;
    }

    // ===== Premium administracija =====
    function addPremiumWord(string calldata word) external onlyOwner {
        string memory w = _toLower(word);
        if (!premiumWords[w]) {
            premiumWords[w] = true;
            premiumList.push(w);
            emit PremiumWordAdded(w);
        }
    }
    function removePremiumWord(string calldata word) external onlyOwner {
        string memory w = _toLower(word);
        if (premiumWords[w]) {
            premiumWords[w] = false;
            emit PremiumWordRemoved(w);
        }
        // (svjesno ne čistimo iz niza radi gas-a; check je preko mappinga)
    }
    function getPremiumList() external view returns (string[] memory) { return premiumList; }

    // ===== ID/Name helpers =====
    function tokenIdOf(string memory name) public view returns (uint256) {
        return nameToId[_toLower(name)];
    }

    // ===== Registracija =====
    function registerDomain(string calldata name) external nonReentrant {
        string memory lower = _toLower(name);
        require(bytes(lower).length > 0, "empty");
        require(nameToId[lower] == 0, "Name taken");

        uint256 price = calculatePrice(lower);
        prpToken.safeTransferFrom(msg.sender, address(this), price);

        _domainIds.increment();
        uint256 newId = _domainIds.current();

        domains[newId] = Domain({
            name: lower,
            cost: price,
            expiresAt: uint64(block.timestamp + 365 days),
            ipfsHash: "",
            siteCID: "",
            siteURL: "",
            storageLimit: 100,
            usedStorage: 0,
            receiver: msg.sender   // default: primaoc je vlasnik
        });

        nameToId[lower] = newId;
        userDomains[msg.sender].push(newId);

        _safeMint(msg.sender, newId);
        emit DomainRegistered(newId, lower, msg.sender, price);
        emit ReceiverChanged(newId, msg.sender);
    }

    // ===== Receiver / Website =====
    modifier onlyDomainOwner(uint256 id) {
        require(ownerOf(id) == msg.sender, "Not domain owner");
        _;
    }

    function setReceiver(uint256 id, address receiver_) external onlyDomainOwner(id) {
        require(receiver_ != address(0), "zero");
        domains[id].receiver = receiver_;
        emit ReceiverChanged(id, receiver_);
    }

    function getReceiver(string calldata name) external view returns (address) {
        uint256 id = nameToId[_toLower(name)];
        require(id != 0, "no such domain");
        return domains[id].receiver;
    }

    function setSiteCID(uint256 id, string memory cid) public onlyDomainOwner(id) {
        domains[id].siteCID = cid;
        domains[id].ipfsHash = cid; // legacy mirror
        emit SiteCIDChanged(id, cid);
        emit ContentUploaded(id, cid);
    }

    function setSiteURL(uint256 id, string memory url) public onlyDomainOwner(id) {
        domains[id].siteURL = url;
        emit SiteURLChanged(id, url);
    }

    function getSiteCID(string calldata name) external view returns (string memory) {
        uint256 id = nameToId[_toLower(name)];
        require(id != 0, "no such domain");
        return domains[id].siteCID;
    }
    function getSiteURL(string calldata name) external view returns (string memory) {
        uint256 id = nameToId[_toLower(name)];
        require(id != 0, "no such domain");
        return domains[id].siteURL;
    }

    // ===== “Storage” (informativno) =====
    function setIPFSHash(uint256 id, string memory ipfsHash, uint256 fileSizeMB) public onlyDomainOwner(id) {
        // INFO: fileSizeMB je trust-based (klijent šalje broj). Drži ovo informativno.
        uint32 newUsed = domains[id].usedStorage + uint32(fileSizeMB);
        require(newUsed <= domains[id].storageLimit, "Storage limit exceeded");
        domains[id].usedStorage = newUsed;
        setSiteCID(id, ipfsHash);
    }

    function upgradeStorage(uint256 id, uint256 additionalMB) public onlyDomainOwner(id) nonReentrant {
        prpToken.safeTransferFrom(msg.sender, address(this), additionalMB * 1 ether);
        domains[id].storageLimit += uint32(additionalMB);
        emit StorageUpgraded(id, domains[id].storageLimit);
    }

    // ===== Subdomains =====
    function addSubdomain(uint256 parentId, string memory subdomain, string memory cid, uint256 fileSizeMB)
        public onlyDomainOwner(parentId)
    {
        uint32 newUsed = domains[parentId].usedStorage + uint32(fileSizeMB);
        require(newUsed <= domains[parentId].storageLimit, "Storage limit exceeded");
        subdomains[parentId].push(subdomain);
        subdomainContents[parentId][subdomain] = cid;
        domains[parentId].usedStorage = newUsed;
    }

    // ===== Renew =====
    function renew(uint256 id, uint256 duration) public onlyDomainOwner(id) nonReentrant {
        prpToken.safeTransferFrom(msg.sender, address(this), (domains[id].cost * duration) / 365 days);
        domains[id].expiresAt += uint64(duration);
    }

    // ===== Withdraw PRP =====
    function withdrawPRP() external onlyOwner {
        prpToken.safeTransfer(owner, prpToken.balanceOf(address(this)));
    }

    // ===== Održavanje userDomains pri transferu =====
    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256 /*batchSize*/) internal override {
        if (from != address(0)) {
            // ukloni tokenId iz userDomains[from]
            uint256[] storage arr = userDomains[from];
            for (uint i=0;i<arr.length;i++){
                if (arr[i] == tokenId) { arr[i] = arr[arr.length-1]; arr.pop(); break; }
            }
        }
        if (to != address(0)) {
            userDomains[to].push(tokenId);
        }
        super._afterTokenTransfer(from, to, tokenId, 1);
    }
}
