// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Ethentity is ERC721 {
    uint256 public maxSupply;
    uint256 public totalSupply;
    address public owner;
    
    // PRP Token adresa za Sepolia testnet
    IERC20 public prpToken = IERC20(0xf412de660d3914E2E5CdB5A476E35d291150C88D);

    struct Domain {
        string name;
        uint256 cost;
        bool isOwned;
        uint256 expiresAt;
    }

    mapping(uint256 => Domain) public domains;
    mapping(uint256 => string[]) public subdomains;
    mapping(uint256 => uint256) public domainForSalePrice;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    constructor(
        string memory _name, 
        string memory _symbol
    ) ERC721(_name, _symbol) {
        owner = msg.sender;
    }

    function list(string memory _name, uint256 _cost) public onlyOwner {
        maxSupply++;
        domains[maxSupply] = Domain(_name, _cost, false, 0);
    }

    function mint(uint256 _id) public {
        require(_id != 0 && _id <= maxSupply, "Invalid ID");
        require(!domains[_id].isOwned, "Already owned");
        
        prpToken.transferFrom(msg.sender, address(this), domains[_id].cost);
        
        domains[_id].isOwned = true;
        domains[_id].expiresAt = block.timestamp + 365 days;
        totalSupply++;
        
        _safeMint(msg.sender, _id);
    }

    function renew(uint256 _id, uint256 duration) public {
        require(ownerOf(_id) == msg.sender, "Not owner");
        prpToken.transferFrom(msg.sender, address(this), domains[_id].cost);
        domains[_id].expiresAt += duration;
    }

    function addSubdomain(uint256 _id, string memory _subdomain) public {
        require(ownerOf(_id) == msg.sender, "Not owner");
        subdomains[_id].push(_subdomain);
    }

    function listForSale(uint256 _id, uint256 _price) public {
        require(ownerOf(_id) == msg.sender, "Not owner");
        domainForSalePrice[_id] = _price;
    }

    function buyDomain(uint256 _id) public {
        require(domainForSalePrice[_id] > 0, "Not for sale");
        address currentOwner = ownerOf(_id);
        
        prpToken.transferFrom(msg.sender, currentOwner, domainForSalePrice[_id]);
        _transfer(currentOwner, msg.sender, _id);
        
        domainForSalePrice[_id] = 0;
    }

    function getDomain(uint256 _id) public view returns (Domain memory) {
        return domains[_id];
    }

    function getSubdomains(uint256 _id) public view returns (string[] memory) {
        return subdomains[_id];
    }

    function withdrawPRP() public onlyOwner {
        prpToken.transfer(owner, prpToken.balanceOf(address(this)));
    }
}