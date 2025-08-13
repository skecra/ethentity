require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { RPC_SEPOLIA, PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;

const networks = {};
if (RPC_SEPOLIA) {
  networks.sepolia = {
    url: RPC_SEPOLIA,
    accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    chainId: 11155111,
  };
}

module.exports = {
  solidity: {
    version: "0.8.9",
    settings: { optimizer: { enabled: true, runs: 200 } },
  },
  networks,
  etherscan: { apiKey: ETHERSCAN_API_KEY || "" },
};
