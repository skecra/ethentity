// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Ethentity is ERC721, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _domainIds;
    
    address public owner;
    IERC20 public immutable prpToken = IERC20(0xf412de660d3914E2E5CdB5A476E35d291150C88D);

    struct Domain {
        string name;
        uint256 cost;
        bool isOwned;
        uint256 expiresAt;
        string ipfsHash;
        uint256 storageLimit; // MB
        uint256 usedStorage; // MB
    }

    // Mappings
    mapping(uint256 => Domain) public domains;
    mapping(string => uint256) public nameToId; // ime -> id domena
    mapping(uint256 => string[]) public subdomains;
    mapping(uint256 => mapping(string => string)) public subdomainContents;
    mapping(address => uint256[]) public userDomains;
    mapping(string => bool) public premiumWords; // premium keyword lista

    // Events
    event DomainRegistered(uint256 indexed id, string name, address owner);
    event ContentUploaded(uint256 indexed id, string ipfsHash);
    event StorageUpgraded(uint256 indexed id, uint256 newLimit);
    event PremiumWordAdded(string word);
    event PremiumWordRemoved(string word);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyDomainOwner(uint256 id) {
        require(ownerOf(id) == msg.sender, "Not domain owner");
        _;
    }

    constructor() ERC721("Ethentity Domains", "ENT") {
        owner = msg.sender;

        // Dodaj neke default premium rijeci
        premiumWords["crypto"] = true;
        premiumWords["nft"] = true;
        premiumWords["blockchain"] = true;
        premiumWords["dao"] = true;
        premiumWords["web3"] = true;
        premiumWords["eth"] = true;
    }

    // ---- Pricing logika ----
    function calculatePrice(string memory name) public view returns (uint256) {
        bytes memory b = bytes(name);
        uint256 basePrice;

        // Dužinski pricing
        if (b.length <= 3) {
            basePrice = 300 ether; // 300 PRP
        } else if (b.length <= 5) {
            basePrice = 150 ether; // 150 PRP
        } else {
            basePrice = 50 ether; // 50 PRP
        }

        // Premium riječ dodatak
        string memory lowerName = _toLower(name);
        for (uint256 i = 0; i < b.length; i++) {
            // crude check - proći kroz premium listu
        }

        // Provjeri da li sadrži premium riječ
        for (uint256 i = 0; i < _premiumList().length; i++) {
            string memory word = _premiumList()[i];
            if (_contains(lowerName, word)) {
                basePrice += 200 ether; // dodatnih 200 PRP za premium riječ
            }
        }

        return basePrice;
    }

    // Lista premium riječi za internu upotrebu
    function _premiumList() internal view returns (string[] memory) {
        uint256 count;
        // prebroj
        for (uint256 i = 0; i < 50; i++) {} // placeholder
        // Ovo ne možemo dinamički vratiti iz mapping-a, ali možemo dodati array storage ako hoćeš
        string ;
        fixedList[0] = "crypto";
        fixedList[1] = "nft";
        fixedList[2] = "blockchain";
        fixedList[3] = "dao";
        fixedList[4] = "web3";
        fixedList[5] = "eth";
        return fixedList;
    }

    // ---- Registracija domena ----
    function registerDomain(string calldata name) external nonReentrant {
        require(nameToId[name] == 0, "Name taken");

        uint256 price = calculatePrice(name);
        prpToken.transferFrom(msg.sender, address(this), price);

        _domainIds.increment();
        uint256 newId = _domainIds.current();

        domains[newId] = Domain({
            name: name,
            cost: price,
            isOwned: true,
            expiresAt: block.timestamp + 365 days,
            ipfsHash: "",
            storageLimit: 100,
            usedStorage: 0
        });

        nameToId[name] = newId;
        userDomains[msg.sender].push(newId);

        _safeMint(msg.sender, newId);
        emit DomainRegistered(newId, name, msg.sender);
    }

    // ---- IPFS ----
    function setIPFSHash(uint256 id, string memory ipfsHash, uint256 fileSize) public onlyDomainOwner(id) {
        require(domains[id].usedStorage + fileSize <= domains[id].storageLimit, "Storage limit exceeded");
        domains[id].ipfsHash = ipfsHash;
        domains[id].usedStorage += fileSize;
        emit ContentUploaded(id, ipfsHash);
    }

    function upgradeStorage(uint256 id, uint256 additionalMB) public onlyDomainOwner(id) {
        uint256 upgradeCost = additionalMB * 1 ether;
        prpToken.transferFrom(msg.sender, address(this), upgradeCost);
        domains[id].storageLimit += additionalMB;
        emit StorageUpgraded(id, domains[id].storageLimit);
    }

    // ---- Subdomain ----
    function addSubdomain(uint256 parentId, string memory subdomain, string memory ipfsHash, uint256 fileSize) public onlyDomainOwner(parentId) {
        require(domains[parentId].usedStorage + fileSize <= domains[parentId].storageLimit, "Storage limit exceeded");
        subdomains[parentId].push(subdomain);
        subdomainContents[parentId][subdomain] = ipfsHash;
        domains[parentId].usedStorage += fileSize;
    }

    // ---- Renew ----
    function renew(uint256 id, uint256 duration) public onlyDomainOwner(id) {
        uint256 cost = (domains[id].cost * duration) / 365 days;
        prpToken.transferFrom(msg.sender, address(this), cost);
        domains[id].expiresAt += duration;
    }

    // ---- Premium riječ administracija ----
    function addPremiumWord(string calldata word) external onlyOwner {
        premiumWords[_toLower(word)] = true;
        emit PremiumWordAdded(word);
    }

    function removePremiumWord(string calldata word) external onlyOwner {
        premiumWords[_toLower(word)] = false;
        emit PremiumWordRemoved(word);
    }

    // ---- Helperi ----
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        for (uint256 i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bStr[i] = bytes1(uint8(bStr[i]) + 32);
            }
        }
        return string(bStr);
    }

    function _contains(string memory where, string memory what) internal pure returns (bool) {
        bytes memory whereBytes = bytes(where);
        bytes memory whatBytes = bytes(what);

        if (whatBytes.length > whereBytes.length) return false;

        for (uint256 i = 0; i <= whereBytes.length - whatBytes.length; i++) {
            bool matchFound = true;
            for (uint256 j = 0; j < whatBytes.length; j++) {
                if (whereBytes[i + j] != whatBytes[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) return true;
        }
        return false;
    }

    // Withdraw PRP
    function withdrawPRP() public onlyOwner {
        prpToken.transfer(owner, prpToken.balanceOf(address(this)));
    }
}
