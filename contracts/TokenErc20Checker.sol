// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./TokenApprover.sol";

contract TokenErc20Checker is Ownable, Initializable {

    uint256 immutable MAX_INT = 2 ** 256 - 1;
    uint256 immutable ONE_HUNDRED = 100;

    TokenApprover private tokenApprover;
    address private nextAddress;

    constructor() {}

    struct DexResponse {
        uint256 amountInStep0;
        uint256 amountInWithFeeStep0;
        uint256 expectedAmountOutStep0;
        uint256 actualAmountOutStep0;
        uint256 gasStep0;

        uint256 amountInStep1;
        uint256 amountInWithFeeStep1;
        uint256 expectedAmountOutStep1;
        uint256 actualAmountOutStep1;
        uint256 gasStep1;
    }

    struct TransferResponse {
        uint256 transfer;
        uint256 actualTransfer;
        uint256 gasTransfer;

        uint256 transferFrom;
        uint256 actualTransferFrom;
        uint256 gasTransferFrom;
    }

    struct FeeComponent {
        uint256 numerator;
        uint256 denominator;
        uint256 feePercent;
    }

    function initialize() external reinitializer(2) {
        _transferOwnership(_msgSender());
        tokenApprover = new TokenApprover();
        nextAddress = addressFrom(address(this), 100500);
    }

    function withdrawTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        safeTransfer(tokenAddress, owner(), contractBalance);
    }

    function checkDex(address dexAddress,
        address inputToken,
        address verifyToken,
        uint256 amountIn,
        FeeComponent calldata fees) external onlyOwner returns (DexResponse memory) {
        require(fees.feePercent < ONE_HUNDRED, "Huge percent");
        IUniswapV2Pair dex = IUniswapV2Pair(dexAddress);
        (address token0, address token1) = sortTokens(inputToken, verifyToken);
        // gas savings
        require(dex.token0() == token0, "Token 0 different");
        require(dex.token1() == token1, "Token 1 different");

        DexResponse memory response = DexResponse(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        (response.amountInStep0,
        response.amountInWithFeeStep0,
        response.expectedAmountOutStep0,
        response.actualAmountOutStep0,
        response.gasStep0) = _calculateSwapStat(dexAddress, inputToken, amountIn, fees);

        (response.amountInStep1,
        response.amountInWithFeeStep1,
        response.expectedAmountOutStep1,
        response.actualAmountOutStep1,
        response.gasStep1) = _calculateSwapStat(dexAddress, verifyToken, response.actualAmountOutStep0, fees);
        return response;
    }

    function checkTransfer(address dexAddress,
        address inputToken,
        address verifyToken,
        uint256 amountIn,
        FeeComponent calldata fees) external onlyOwner returns (TransferResponse memory) {
        require(fees.feePercent < ONE_HUNDRED, "Huge percent");
        IUniswapV2Pair dex = IUniswapV2Pair(dexAddress);
        (address token0, address token1) = sortTokens(inputToken, verifyToken);
        // gas savings
        require(dex.token0() == token0, "Token 0 different");
        require(dex.token1() == token1, "Token 1 different");

        TransferResponse memory response = TransferResponse(0, 0, 0, 0, 0, 0);
        // we need a bit of verify tokens
        _calculateSwapStat(dexAddress, inputToken, amountIn, fees);

        (response.transfer,
        response.actualTransfer,
        response.gasTransfer) = _calculateTransfer(verifyToken);

        (response.transferFrom,
        response.actualTransferFrom,
        response.gasTransferFrom) = _calculateTransferFrom(verifyToken);

        return response;
    }

    function _calculateSwapStat(address dexAddress,
        address inputToken,
        uint256 amountIn,
        FeeComponent calldata fee
    ) private returns (uint256, uint256, uint256, uint256, uint256){

        // amountIn will be sent to THE DEX
        // amountInWithFee will be used to exchange
        uint256 amountInWithFee = amountIn * (ONE_HUNDRED - fee.feePercent) / ONE_HUNDRED;

        uint amountOut;
        address outputToken;
        // prevents stack too deep error
        {
            (uint112 reserves0, uint112 reserves1,) = IUniswapV2Pair(dexAddress).getReserves();
            // determines amountOut and dest token
            if (IUniswapV2Pair(dexAddress).token0() == inputToken) {
                amountOut = getAmountOut(amountInWithFee, reserves0, reserves1, fee);
                outputToken = IUniswapV2Pair(dexAddress).token1();
            } else {
                amountOut = getAmountOut(amountInWithFee, reserves1, reserves0, fee);
                outputToken = IUniswapV2Pair(dexAddress).token0();
            }
        }

        // buy stage!
        safeTransfer(inputToken, dexAddress, amountIn);

        // determines output tokens before swap
        uint256 actualAmountOut = IERC20(outputToken).balanceOf(address(this));

        // make swap, records gas
        uint usedGas = gasleft();

        // prevents stack too deep
        {
            (uint amount0Out, uint amount1Out) = inputToken == IUniswapV2Pair(dexAddress).token0() ? (uint(0), amountOut) : (amountOut, uint(0));
            IUniswapV2Pair(dexAddress).swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
        // figure out how many gas has been spent
        usedGas = usedGas - gasleft();

        // no safe math needed due to compile version above 0.8
        actualAmountOut = IERC20(outputToken).balanceOf(address(this)) - actualAmountOut;

        return (amountIn, amountInWithFee, amountOut, actualAmountOut, usedGas);
    }

    function _calculateTransfer(address inputToken) private returns (uint256, uint256, uint256){
        uint256 balanceBefore = IERC20(inputToken).balanceOf(address(this));
        uint usedGas = gasleft();
        safeTransfer(inputToken, address(tokenApprover), balanceBefore);
        usedGas = usedGas - gasleft();
        uint256 balanceAfter = IERC20(inputToken).balanceOf(address(tokenApprover));
        return (balanceBefore, balanceAfter, usedGas);
    }

    function _calculateTransferFrom(address inputToken) private returns (uint256, uint256, uint256){
        address approverAddress = address(tokenApprover);
        uint256 balanceBefore = IERC20(inputToken).balanceOf(approverAddress);
        tokenApprover.giveApprove(inputToken, balanceBefore);
        uint usedGas = gasleft();
        safeTransferFrom(inputToken, approverAddress, nextAddress, balanceBefore);
        usedGas = usedGas - gasleft();
        uint256 balanceAfter = IERC20(inputToken).balanceOf(nextAddress);
        return (balanceBefore, balanceAfter, usedGas);
    }

    function sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn,
        uint reserveIn,
        uint reserveOut,
    // numerator is 997
    // denominator is 1000
        FeeComponent calldata fee
    ) private pure returns (uint amountOut) {
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

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function addressFrom(address _origin, uint _nonce) private pure returns (address _address) {
        bytes memory data;
        if (_nonce == 0x00) data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        else if (_nonce <= 0x7f) data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
        else if (_nonce <= 0xff) data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
        else if (_nonce <= 0xffff) data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
        else if (_nonce <= 0xffffff) data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
        else data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
        bytes32 hash = keccak256(data);
        assembly {
            mstore(0, hash)
            _address := mload(0)
        }
    }

    ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////
    // SWAP ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////

    struct FactoryFee {
        address factory;
        uint16 denominator;
        uint16 numerator;
    }

    function makeSwap(FactoryFee[] calldata factoryFees,
        uint256 amountIn,
        address startToken,
        address[][3] calldata dexRoute
    ) external onlyOwner {
        for(uint i = 0; i < dexRoute.length; i++) {

        }
    }


    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn,
        uint reserveIn,
        uint reserveOut,
        FactoryFee calldata fee
    ) private pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // 997 line bellow
        uint amountInWithFee = amountIn * fee.numerator;
        uint numerator = amountInWithFee * reserveOut;
        // 1000 line bellow
        uint denominator = (reserveIn * fee.denominator) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
