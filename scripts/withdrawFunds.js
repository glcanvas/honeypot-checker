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
  const checkerContract = await TokenErc20Checker.attach(
      "0xaBFD3e0C0661a4193B5912401d16Ae4d31E87f07");
  const trans = await checkerContract.withdrawTokens(
      "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83");
  console.log(trans);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
