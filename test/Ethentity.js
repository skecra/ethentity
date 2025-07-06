const { expect } = require("chai")
const { ethers } = require("hardhat")
const { describe } = require("mocha")
const { transpileModule } = require("typescript")

const tokens = (n) => {
  return ethers.utils.parseUnits(n.toString(), 'ether')
}

describe("Ethentity", () => {


  let ethentity
  let deployer, owner1

  const NAME = "ETH Daddy"
  const SYMBOL = "ETHD"

  beforeEach(async () => {
    // Setup accounts
    [deployer, owner1] = await ethers.getSigners()

    // Deploy contract
    const Ethentity = await ethers.getContractFactory("Ethentity")
    ethentity = await Ethentity.deploy(NAME, SYMBOL)

    // List a domain
    const transaction = await ethentity.connect(deployer).list("luka.eth", tokens(10))
    await transaction.wait()
  })
  })


  describe("Domain", () => {
    it('Returns domain attributes', async () => {
      const domain = await ethentity.getDomain(1)
      expect(domain.name).to.be.equal("jack.eth")
      expect(domain.cost).to.be.equal(tokens(10))
      expect(domain.isOwned).to.be.equal(false)
    })
  })



