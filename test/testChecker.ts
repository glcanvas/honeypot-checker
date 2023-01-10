/*
import {ethers, network} from "hardhat";
import chai from "chai";

import {SimpleToken, TokenWithFee, TokenErc20Checker} from "../typechain";
import {UniswapV2Factory, UniswapV2Pair, UniswapV2Router01} from "../typechain";
import {BigNumber} from "ethers";

function getOutputAmount(amount: BigNumber, reserve1: BigNumber, reserve2: BigNumber): BigNumber {
  var amountInWithFee = amount.mul(997);
  var numerator = amountInWithFee.mul(reserve2);
  var denominator = reserve1.mul(1000).add(amountInWithFee);
  return numerator.div(denominator);
}

// 1000 10_000, 10_000
// 100 * 997 * 10000 / (10000 * 1000 + 100 * 997)
// => 100, 98 & 10100, 9_902
// 98 * 997 * 10100 / ( 9902 * 1000 + 98 * 997)
// => 98, 98 => 10002, 10000

async function init(): Promise<[UniswapV2Factory, UniswapV2Router01, SimpleToken, SimpleToken, TokenWithFee, TokenWithFee, TokenErc20Checker]> {
  const [owner, ...addresses] = await ethers.getSigners();
  var factory: UniswapV2Factory;
  var router;
  var simpleToken1;
  var simpleToken2;
  var feeToken1;
  var feeToken2;
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
    const contract = await ethers.getContractFactory("SimpleToken");
    simpleToken1 = await contract.deploy();
    await simpleToken1.deployed();
  }
  {
    const contract = await ethers.getContractFactory("SimpleToken");
    simpleToken2 = await contract.deploy();
    await simpleToken2.deployed();
  }

  {
    const contract = await ethers.getContractFactory("TokenWithFee");
    feeToken1 = await contract.deploy(5);
    await feeToken1.deployed();
  }
  {
    const contract = await ethers.getContractFactory("TokenWithFee");
    feeToken2 = await contract.deploy(5);
    await feeToken2.deployed();
  }
  {
    const contract = await ethers.getContractFactory("TokenErc20Checker");
    checker = await contract.deploy();
    await checker.deployed();
  }

  return [factory, router, simpleToken1, simpleToken2, feeToken1, feeToken2, checker];
}

describe("Honeypot tests", () => {

  it("test pair no tokens fee", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    const [factory, router, simpleToken1, simpleToken2, feeToken1, feeToken2, checker] = await init();

    await factory.createPair(simpleToken1.address, simpleToken2.address);
    const pairAddress = await factory.getPair(simpleToken1.address, simpleToken2.address);
    const pair = (await ethers.getContractFactory("UniswapV2Pair")).attach(pairAddress);

    await simpleToken1.approve(router.address, 100_000);
    await simpleToken2.approve(router.address, 100_000);
    var transaction = router.addLiquidity(simpleToken1.address,
        simpleToken2.address, 10_000, 10_000, 0, 0, owner.address);
    await chai.expect(transaction).to.emit(pair, "Mint").withArgs(router.address, 10_000, 10_000);
    chai.expect(await pair.balanceOf(owner.address)).to.be.eq(9_000);

    await simpleToken1.transfer(checker.address, 1_000);
    var fees = {numerator: 997, denominator: 1000, feePercent: 0};
    var checkResult = await checker.callStatic.checkDex(pairAddress, simpleToken1.address, simpleToken2.address, 100, fees);
    chai.expect(checkResult.amountInStep0).to.be.eq(100);
    chai.expect(checkResult.expectedAmountOutStep0).to.be.eq(98);
    chai.expect(checkResult.actualAmountOutStep0).to.be.eq(98);

    chai.expect(checkResult.amountInStep1).to.be.eq(98);
    chai.expect(checkResult.expectedAmountOutStep1).to.be.eq(98);
    chai.expect(checkResult.actualAmountOutStep1).to.be.eq(98);


    var checkResultTransfer = await checker.callStatic.checkTransfer(pairAddress, simpleToken1.address, simpleToken2.address, 100, fees);
    chai.expect(checkResultTransfer.transfer).to.be.eq(98);
    chai.expect(checkResultTransfer.actualTransfer).to.be.eq(98);

    chai.expect(checkResultTransfer.transferFrom).to.be.eq(98);
    chai.expect(checkResultTransfer.actualTransferFrom).to.be.eq(98);
  });

  it("test pair with tokens fee", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    const [factory, router, simpleToken1, simpleToken2, feeToken1, feeToken2, checker] = await init();

    await factory.createPair(simpleToken1.address, feeToken1.address);
    const pairAddress = await factory.getPair(simpleToken1.address, feeToken1.address);
    const pair = (await ethers.getContractFactory("UniswapV2Pair")).attach(pairAddress);

    await simpleToken1.approve(router.address, 100_000);
    await feeToken1.approve(router.address, 100_000);
    var transaction = router.addLiquidity(simpleToken1.address,
        feeToken1.address, 10_000, 10_000, 0, 0, owner.address);
    await chai.expect(transaction).to.emit(pair, "Mint").withArgs(router.address, 9_500, 10_000);
    chai.expect(await pair.balanceOf(owner.address)).to.be.eq(8746);

    await simpleToken1.transfer(checker.address, 1_000);
    var fees = {numerator: 997, denominator: 1000, feePercent: 50};
    var checkResult = await checker.callStatic.checkDex(pairAddress, simpleToken1.address, feeToken1.address, 100, fees);
    chai.expect(checkResult.amountInStep0).to.be.eq(100);
    chai.expect(checkResult.amountInWithFeeStep0).to.be.eq(50);
    chai.expect(checkResult.expectedAmountOutStep0).to.be.eq(47);
    chai.expect(checkResult.actualAmountOutStep0).to.be.eq(44);

    chai.expect(checkResult.amountInStep1).to.be.eq(44);
    chai.expect(checkResult.amountInWithFeeStep1).to.be.eq(22);
    chai.expect(checkResult.expectedAmountOutStep1).to.be.eq(23);
    chai.expect(checkResult.actualAmountOutStep1).to.be.eq(23);

    var checkResultTransfer = await checker.callStatic.checkTransfer(pairAddress, simpleToken1.address, feeToken1.address, 100, fees);
    chai.expect(checkResultTransfer.transfer).to.be.eq(44);
    chai.expect(checkResultTransfer.actualTransfer).to.be.eq(41);

    chai.expect(checkResultTransfer.transferFrom).to.be.eq(41);
    chai.expect(checkResultTransfer.actualTransferFrom).to.be.eq(38);

    var trans = await checker.checkTransfer(pairAddress, simpleToken1.address, feeToken1.address, 100, fees);
    console.log(trans);
  });

  it("test withdraw tokens", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    const [factory, router, simpleToken1, simpleToken2, feeToken1, feeToken2, checker] = await init();

    await simpleToken1.transfer(checker.address, 100_000);
    await checker.withdrawTokens(simpleToken1.address);
    chai.expect(await simpleToken1.balanceOf(owner.address)).to.be.eq(BigNumber.from(10).pow(BigNumber.from(18)));
  });

  it("test proxy failed", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    var [factory, router, simpleToken1, simpleToken2, feeToken1, feeToken2, checker] = await init();
    var proxy;
    {
      const contract = await ethers.getContractFactory("CheckerProxy");
      proxy = await contract.deploy(checker.address);
      await proxy.deployed();
    }
    checker = await checker.attach(proxy.address);
    chai.expect(await checker.owner()).to.be.eq(owner.address);

  });

});
 */