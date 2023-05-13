import * as dotenv from "dotenv";
import {HardhatUserConfig, task} from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "solidity-coverage";
import * as process from "process";

dotenv.config();

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// npx hardhat run scripts/deploy.js --network fantom

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        }
      },
      {
        version: "0.5.16"
      },
      {
        version: "0.6.6"
      }
    ]
  }, // compiler version
  networks: { // list of networks with routes and accounts to use
    fantom: {
      url: process.env.FANTOM_ADDRESS,
      accounts:
          [process.env.PRIVATE_KEY!]
    }
  },
  etherscan: { // private api key to verify deployed contracts on etherscan
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

export default config;
