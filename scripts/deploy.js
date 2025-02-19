// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const TokenErc20Checker = await hre.ethers.getContractFactory(
      "TokenErc20Checker"
  );
  const checker = await TokenErc20Checker.deploy();

  const checkerContract = await checker.deployed();

  console.log("deployed checker contract");
  console.log("address: " + checkerContract.address);

  const Proxy = await hre.ethers.getContractFactory(
      "CheckerProxy"
  );
  const proxy = await Proxy.deploy(checkerContract.address);

  const proxyContract = await proxy.deployed();

  console.log("deployed proxy contract");
  console.log("address: " + proxyContract.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
