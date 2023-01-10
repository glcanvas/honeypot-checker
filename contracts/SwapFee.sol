// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface ISwapFee {

    struct FactoryFee {
        address factory;
        uint16 denominator;
        uint16 numerator;
    }

    struct DexToFactory {
        address dex;
        uint8 index;
        bool firstIdentifier; // 0 -> current token is token0, 1 otherwise
    }

    function swapOnDex(FactoryFee[] calldata factoryFees,
        uint256 amountIn,
        address startToken,
        DexToFactory[3] calldata dexRoute) external returns (bool);

}

contract SwapFee is ISwapFee {
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('swapOnDex((address,uint16,uint16)[],uint256,address,(address,uint8,bool)[3])')));


    function makeSwap(FactoryFee[] calldata factoryFees,
        uint256 amountIn,
        address startToken,
        DexToFactory[3][] calldata dexRoutes
    ) external returns (uint256 successSwaps){
        successSwaps = 0;
        for (uint i = 0; i < dexRoutes.length; i++) {
            (bool success,) = address(this).call(abi.encodeWithSelector(SELECTOR, factoryFees, amountIn, startToken, dexRoutes[i]));
            if (success) {
                successSwaps += 1;
            }
        }
    }

    function swapOnDex(FactoryFee[] calldata factoryFees,
        uint256 amountIn,
        address startToken,
        DexToFactory[3] calldata dexRoute) external override returns (bool) {
        require(msg.sender == address(this), "Fuck u");

        uint256 balanceBefore = IERC20(startToken).balanceOf(address(this));
        uint256 reserve0;
        uint256 reserve1;
        address token0;
        uint256 amountOut;


        // make swap 1
        (reserve0, reserve1,) = IUniswapV2Pair(dexRoute[0].dex).getReserves();
        // gas savings
        //token0 = IUniswapV2Pair(dexRoute[0].dex).token0();
        // first swap -- transfer to dex0
        safeTransfer(startToken, dexRoute[0].dex, amountIn);
        if (dexRoute[0].firstIdentifier) {
            amountOut = getAmountOut(amountIn, reserve0, reserve1, factoryFees[dexRoute[0].index]);
            // startToken = IUniswapV2Pair(dexRoute[0].dex).token1();
            IUniswapV2Pair(dexRoute[0].dex).swap(0, amountOut, dexRoute[1].dex, new bytes(0));
        } else {
            amountOut = getAmountOut(amountIn, reserve1, reserve0, factoryFees[dexRoute[0].index]);
            // startToken = token0;
            IUniswapV2Pair(dexRoute[0].dex).swap(amountOut, 0, dexRoute[1].dex, new bytes(0));
        }
        amountIn = amountOut;

        // make swap 2
        (reserve0, reserve1,) = IUniswapV2Pair(dexRoute[1].dex).getReserves();
        if (dexRoute[1].firstIdentifier) {
            amountOut = getAmountOut(amountIn, reserve0, reserve1, factoryFees[dexRoute[1].index]);
            IUniswapV2Pair(dexRoute[1].dex).swap(0, amountOut, dexRoute[2].dex, new bytes(0));
        } else {
            amountOut = getAmountOut(amountIn, reserve1, reserve0, factoryFees[dexRoute[1].index]);
            IUniswapV2Pair(dexRoute[1].dex).swap(amountOut, 0, dexRoute[2].dex, new bytes(0));
        }
        amountIn = amountOut;

        // make swap 3
        (reserve0, reserve1,) = IUniswapV2Pair(dexRoute[2].dex).getReserves();
        // gas savings
        //token0 = IUniswapV2Pair(dexRoute[2].dex).token0();
        // safeTransfer(startToken, dexRoute[2].dex, amountIn); no need to swap
        if (dexRoute[2].firstIdentifier) {// token0 == startToken
            amountOut = getAmountOut(amountIn, reserve0, reserve1, factoryFees[dexRoute[2].index]);
            //startToken = IUniswapV2Pair(dexRoute[2].dex).token1();
            IUniswapV2Pair(dexRoute[2].dex).swap(0, amountOut, address(this), new bytes(0));
        } else {
            amountOut = getAmountOut(amountIn, reserve1, reserve0, factoryFees[dexRoute[2].index]);
            //startToken = token0;
            IUniswapV2Pair(dexRoute[2].dex).swap(amountOut, 0, address(this), new bytes(0));
        }
        amountIn = amountOut;

        require(IERC20(startToken).balanceOf(address(this)) > balanceBefore, "Failed to make swap");
        return true;
    }

    function getAmountOut(uint amountIn,
        uint reserveIn,
        uint reserveOut,
        FactoryFee calldata fee
    ) public pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // 997 line bellow
        uint amountInWithFee = amountIn * fee.numerator;
        uint numerator = amountInWithFee * reserveOut;
        // 1000 line bellow
        uint denominator = (reserveIn * fee.denominator) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function safeTransfer(address token, address to, uint value) private {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    struct Reserves {
        uint112 reserve0;
        uint112 reserve1;
    }

    function requestReservesV2(address[] calldata dexes) external view returns (Reserves[] memory) {
        Reserves[] memory reserves = new Reserves[](dexes.length);
        for (uint i = 0; i < dexes.length; i++) {
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(dexes[i]).getReserves();
            reserves[i] = Reserves(reserve0, reserve1);
        }
        return reserves;
    }
}