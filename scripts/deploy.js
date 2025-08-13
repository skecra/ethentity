const hre = require("hardhat");

async function main() {
  const Ethentity = await hre.ethers.getContractFactory("Ethentity");
  const reg = await Ethentity.deploy();             // bez argumenata
  await reg.deployed();
  console.log("Ethentity deployed to:", reg.address);

  // (opciono) auto-verify — sačekaj par blokova da Etherscan indeksira
  if (process.env.ETHERSCAN_API_KEY) {
    try {
      await hre.run("verify:verify", { address: reg.address, constructorArguments: [] });
      console.log("Verified on Etherscan.");
    } catch (e) {
      console.log("Verify skipped:", e.message);
    }
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
