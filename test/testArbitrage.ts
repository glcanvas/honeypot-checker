import {ethers, network} from "hardhat";
import chai from "chai";

import {SimpleToken, TokenWithFee, TokenErc20Checker} from "../typechain";
import {UniswapV2FactoryMy, UniswapV2PairMy, Token, SwapFee} from "../typechain";
import {BigNumber} from "ethers";

const MAX_2_255 = BigNumber.from("57896044618658097711785492504343953926634992332820282019728792003956564819968");
const TWO = BigNumber.from(10).pow(BigNumber.from(18)).mul(BigNumber.from(2));

describe("Arbitrage tests", () => {
  it("test", async () => {
    const [owner, ...addresses] = await ethers.getSigners();
    const token = await ethers.getContractFactory("Token");
    const factory = await ethers.getContractFactory("UniswapV2FactoryMy");
    const dex = await ethers.getContractFactory("UniswapV2PairMy");
    const swapFee = await ethers.getContractFactory("SwapFee");

    const SW = await swapFee.deploy();

    const A = await token.deploy("WFTM", "WFTM", 18, MAX_2_255);
    const B = await token.deploy("LIRA", "LIRA", 9, MAX_2_255);
    const C = await token.deploy("BOO", "BOO", 18, MAX_2_255);

    await A.transfer(SW.address, TWO);

    const F1 = await factory.deploy(owner.address);
    await F1.setFees(3, 1000);

    const F2 = await factory.deploy(owner.address);
    await F2.setFees(2, 1000);

    await F1.createPair(A.address, B.address);
    const AB = dex.attach(await F1.allPairs(0));
    await F2.createPair(B.address, C.address);
    const BC = dex.attach(await F2.allPairs(0));
    await F1.createPair(C.address, A.address);
    const CA = dex.attach(await F1.allPairs(1));

    await A.transfer(AB.address, BigNumber.from("22000000000000000000"));
    await B.transfer(AB.address, BigNumber.from("9123333330000000000000"));
    // 39049534129345137995834
    await AB.sync();
    const ABR = await AB.getReserves();

    await B.transfer(BC.address, BigNumber.from("1250000000000000000000"));
    await C.transfer(BC.address, BigNumber.from("1813380000000000000"));
    await BC.sync();

    await C.transfer(CA.address, BigNumber.from("5753817500122074326"));
    await A.transfer(CA.address, BigNumber.from("31549453158525725243"));
    await CA.sync();

    /*
    const fee = {
      "factory": F1.address,
      "denominator": 1000,
      "numerator": 997,
    };
    var res = await SW.getAmountOut(TWO, await A.balanceOf(AB.address), await B.balanceOf(AB.address), fee);
    console.log(res);
    res = await SW.getAmountOut(res, await B.balanceOf(BC.address), await C.balanceOf(BC.address), fee);
    console.log(res);
    res = await SW.getAmountOut(res, await C.balanceOf(CA.address), await A.balanceOf(CA.address), fee);
    console.log(res);
     */

    const balanceBefore = await A.balanceOf(SW.address);
    console.log(balanceBefore);
    const trans = await SW.makeSwap([{
      "factory": F1.address,
      "denominator": 1000,
      "numerator": 997
    }, {
      "factory": F2.address,
      "denominator": 1000,
      "numerator": 998
    }], TWO, A.address, [[
      {"dex": AB.address, "index": BigNumber.from(0), "firstIdentifier": A.address < B.address},
      {"dex": BC.address, "index": BigNumber.from(1), "firstIdentifier": B.address < C.address},
      {"dex": CA.address, "index": BigNumber.from(0), "firstIdentifier": C.address < A.address}
    ]
    ]);
    console.log((await trans.wait(1)).gasUsed);
    const balanceAfter = await A.balanceOf(SW.address);
    console.log(balanceAfter);
    chai.expect(balanceBefore).lt(balanceAfter);

  })
});