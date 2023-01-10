/*import {ethers, network} from "hardhat";
import chai from "chai";

import {Usdc, WrappedFtm, TokenErc20Checker} from "../typechain";
import {UniswapV2Factory, UniswapV2Pair, UniswapV2Router01} from "../typechain";
import {BigNumber} from "ethers";

function getOutputAmount(amount: BigNumber, reserve1: BigNumber, reserve2: BigNumber): BigNumber {
  var amountInWithFee = amount.mul(997);
  var numerator = amountInWithFee.mul(reserve2);
  var denominator = reserve1.mul(1000).add(amountInWithFee);
  return numerator.div(denominator);
}

// y * x = (x + x1) * (y - y1)
// (y * (x + x1) - y * x) / (x + x1) = y1
// y * x1 / (x + x1) = y1

// 1000 10_000, 10_000
// 100 * 997 * 10000 / (10000 * 1000 + 100 * 997)
// => 100, 98 & 10100, 9_902
// 98 * 997 * 10100 / ( 9902 * 1000 + 98 * 997)
// => 98, 98 => 10002, 10000

async function init(): Promise<[UniswapV2Factory, UniswapV2Router01, Usdc, WrappedFtm, TokenErc20Checker]> {
  const [owner, ...addresses] = await ethers.getSigners();
  var factory: UniswapV2Factory;
  var router;
  var usdc;
  var wftm;
  var checker;
  {
    const contract = await ethers.getContractFactory("UniswapV2Factory");
    factory = await contract.deploy(owner.address);
    await factory.deployed();
  }
  {
    const contract = await ethers.getContractFactory("UniswapV2Router01");
    router = await contract.deploy(factory.address, factory.address);
    await router.deployed();
  }
  {
    const contract = await ethers.getContractFactory("Usdc");
    usdc = await contract.deploy("USDC", "USDC", 18, owner.address);
    await usdc.deployed();
  }
  {
    const contract = await ethers.getContractFactory("WrappedFtm");
    wftm = await contract.deploy();
    await wftm.deployed();
  }

  {
    const contractChecker = await ethers.getContractFactory("TokenErc20Checker");
    checker = await contractChecker.deploy();
    await checker.deployed();

    const contractProxy = await ethers.getContractFactory("CheckerProxy");
    const proxy = await contractProxy.deploy(checker.address);
    await proxy.deployed();
    checker = contractChecker.attach(proxy.address);
  }

  return [factory, router, usdc, wftm, checker];
}

describe("Honeypot tests", () => {

  it("test pair no tokens fee", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    const [factory, router, usdc, wftm, checker] = await init();

    await factory.createPair(usdc.address, wftm.address);
    const pairAddress = await factory.getPair(usdc.address, wftm.address);
    const pair = (await ethers.getContractFactory("UniswapV2Pair")).attach(pairAddress);

    await usdc.Swapin(owner.address, "999301887940341962470343");
    await wftm.deposit({value: "50000000000000000000"});

    await wftm.transfer(pair.address, "43320510698554");
    await usdc.transfer(pair.address, "999301887940341962470343");
    await chai.expect(pair.sync()).to.emit(pair, "Sync").withArgs("999301887940341962470343", "43320510698554");

    await wftm.transfer(checker.address, "10000000000000000000");
    var fees = {numerator: 997, denominator: 1000, feePercent: 0};
    var checkResult = await checker.callStatic.checkDex(pairAddress, wftm.address, usdc.address, "10000000000000000000", fees);
    console.log(checkResult)

    await usdc.approve(router.address, 100_000);
    await wftm.approve(router.address, 100_000);
    var transaction = router.addLiquidity(usdc.address,
        wftm.address, 10_000, 10_000, 0, 0, owner.address);
    await chai.expect(transaction).to.emit(pair, "Mint").withArgs(router.address, 10_000, 10_000);
    chai.expect(await pair.balanceOf(owner.address)).to.be.eq(9_000);


    await wftm.transfer(checker.address, 1_000);
    var fees = {numerator: 997, denominator: 1000, feePercent: 0};
    var checkResult = await checker.callStatic.checkDex(pairAddress, wftm.address, usdc.address, 100, fees);
    chai.expect(checkResult.amountInStep0).to.be.eq(100);
    chai.expect(checkResult.expectedAmountOutStep0).to.be.eq(98);
    chai.expect(checkResult.actualAmountOutStep0).to.be.eq(98);

    chai.expect(checkResult.amountInStep1).to.be.eq(98);
    chai.expect(checkResult.expectedAmountOutStep1).to.be.eq(98);
    chai.expect(checkResult.actualAmountOutStep1).to.be.eq(98);


    var checkResultTransfer = await checker.callStatic.checkTransfer(pairAddress, wftm.address, usdc.address, 100, fees);
    chai.expect(checkResultTransfer.transfer).to.be.eq(98);
    chai.expect(checkResultTransfer.actualTransfer).to.be.eq(98);

    chai.expect(checkResultTransfer.transferFrom).to.be.eq(98);
    chai.expect(checkResultTransfer.actualTransferFrom).to.be.eq(98);


  });


});


 */