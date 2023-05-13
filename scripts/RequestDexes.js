// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const {BigNumberish, BigNumber} = require("ethers");

async function main() {
  const TokenErc20Checker = await hre.ethers.getContractFactory(
      "TokenErc20Checker"
  );
  const checker = await TokenErc20Checker.attach(
      "0xaBFD3e0C0661a4193B5912401d16Ae4d31E87f07");

  var res = await checker.requestReservesV2(
      ['0x1d407e5c1265b17a2f2889813d61cf98205325f9',
        '0x9ce8e9b090e8af873e793e0b78c484076f8ceece',
        '0x2b4c76d0dc16be1c31d4c1dc53bf9b45987fc75c']);

  console.log(res);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
