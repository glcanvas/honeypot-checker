// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface Checker {
    struct DexReport {
        uint256 amountIn;
        uint256 amountInWithFee;
        uint256 expectedAmountOut;
        uint256 actualAmountOut;
        uint256 gas;
    }

    struct ApproveReport {
        uint256 gas;
    }

    struct TransferReport {
        uint256 transfer;
        uint256 actualTransfer;
        uint256 gas;
    }

    struct Report {
        DexReport exchangeTo; // from verified token, to shitcoin
        DexReport exchangeFrom; // from shitcoin to verified token
        TransferReport transfer; // use transfer function
        ApproveReport approve; // calculate approve function
        TransferReport transferFrom; // use transferFrom function
    }
}

contract Bob is Ownable, Checker {
    uint256 immutable MAX_INT = 2 ** 256 - 1;

    function approveForOwner(address token) public onlyOwner returns (ApproveReport memory report) {
        uint usedGas = gasleft();
        IERC20(token).approve(owner(), MAX_INT);
        usedGas = usedGas - gasleft();
        return ApproveReport(usedGas);
    }
}

contract TokenErc20Checker is Ownable, Initializable, Checker {

    struct DexFee {
        uint16 denominator;
        uint16 numerator;
    }

    struct SingleDexRequest {
        address fromToken;
        address[] dexPath;
        DexFee[] dexFee;
        uint256 feeSlippage;
    }

    uint256 immutable ONE_HUNDRED = 100;
    Bob private bob;
    bytes4 private constant VALIDATE_DEX_SELECTOR = bytes4(keccak256(bytes('validateDex(address,(address,address[],(uint16,uint16)[],uint256))')));
    bytes4 private constant VALIDATE_DEX_INTERNAL_SELECTOR = bytes4(keccak256(bytes('validateDexInternal(address,(address,address[],(uint16,uint16)[],uint256))')));

    constructor() {
        _transferOwnership(_msgSender());
        bob = new Bob();
    }

    function initialize() external // reinitializer(4)
    {
        _transferOwnership(_msgSender());
        bob = new Bob();
    }

    function withdrawTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        safeTransfer(tokenAddress, owner(), contractBalance);
    }

    function checkDexesMulticall(SingleDexRequest[] calldata request) external returns (Report[] memory reports) {
        reports = new Report[](request.length);

        address initializer = msg.sender;
        for (uint256 i = 0; i < request.length; i++) {
            require(request[i].dexFee.length == request[i].dexPath.length, "Incorrect fee & path");
            (bool success, bytes memory data) = address(this).call(abi.encodePacked(VALIDATE_DEX_SELECTOR, abi.encode(initializer, request[i])));
            require(!success, "Can't be passed");

            uint offset = 32 + 32 + 4;
            bytes memory reportByte =  slice(data, offset, data.length - offset); //abi.decode(data, (string));

            reports[i] = abi.decode(reportByte, (Report));

        }
        // 00000000000000000000000000000000000000000000000000000000000003e8

        return reports;
    }

    function validateDex(address initializer, SingleDexRequest memory route) external {
        require(msg.sender == address(this), "Only recursive");
        require(route.feeSlippage < ONE_HUNDRED, "Huge slippage");
        (bool success, bytes memory data) = address(this).call(abi.encodePacked(VALIDATE_DEX_INTERNAL_SELECTOR, abi.encode(initializer, route)));
        Report memory result;
        if (success) {
            result = abi.decode(data, (Report));
        } else {
            result = Report(DexReport(0, 0, 0, 0, 0), DexReport(0, 0, 0, 0, 0), TransferReport(0, 0, 0), ApproveReport(0), TransferReport(0, 0, 0));
        }
        string memory msg = string(abi.encode(result));
        revert(msg);
    }

    // 00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e2000000000000000000000000000000000000000000000000000000000001709b00000000000000000000000000000000000000000000000000000000000002e2000000000000000000000000000000000000000000000000000000000000024e000000000000000000000000000000000000000000000000000000000000029000000000000000000000000000000000000000000000000000000000000002900000000000000000000000000000000000000000000000000000000000009c9a00000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e20000000000000000000000000000000000000000000000000000000000005c6c000000000000000000000000000000000000000000000000000000000000631400000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e20000000000000000000000000000000000000000000000000000000000005e34
    function validateDexInternal(address initializer, SingleDexRequest memory route) external returns (Report memory) {
        require(msg.sender == address(this), "Only recursive");
        require(route.feeSlippage < ONE_HUNDRED, "Huge slippage");

        address initialToken = route.fromToken;
        uint256 balance = min(IERC20(initialToken).allowance(initializer, address(this)), IERC20(initialToken).balanceOf(initializer));
        require(balance > 0, "Not enough approve");
        IERC20(initialToken).transferFrom(initializer, address(this), balance);

        DexReport memory forwardSwapReport;
        for (uint i = 0; i < route.dexPath.length; i++) {
            // we got last report
            forwardSwapReport = makeTrade(initialToken, route.dexPath[i], route.dexFee[i], route.feeSlippage);
            IUniswapV2Pair pair = IUniswapV2Pair(route.dexPath[i]);
            initialToken = pair.token0() == initialToken ? pair.token1() : pair.token0();
        }
        // initial token here == token we want validate
        // this address owns tokens

        TransferReport memory transferReport = makeTransfer(initialToken);
        ApproveReport memory approveReport = makeApprove(initialToken);
        TransferReport memory transferFromReport = makeTransferFrom(initialToken);
        DexReport memory backwardSwapReport = makeTrade(initialToken,
            route.dexPath[route.dexPath.length - 1],
            route.dexFee[route.dexFee.length - 1],
            route.feeSlippage);

        Report memory report = Report(forwardSwapReport, backwardSwapReport, transferReport, approveReport, transferFromReport);
        return report;
    }

    // 000000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e2000000000000000000000000000000000000000000000000000000000001709b00000000000000000000000000000000000000000000000000000000000002e2000000000000000000000000000000000000000000000000000000000000024e000000000000000000000000000000000000000000000000000000000000029000000000000000000000000000000000000000000000000000000000000002900000000000000000000000000000000000000000000000000000000000009c9a00000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e20000000000000000000000000000000000000000000000000000000000005c6c000000000000000000000000000000000000000000000000000000000000631400000000000000000000000000000000000000000000000000000000000002e200000000000000000000000000000000000000000000000000000000000002e20000000000000000000000000000000000000000000000000000000000005e34

    function makeTrade(address inputToken, address dex, DexFee memory fee, uint256 slippage) private returns (DexReport memory result) {
        // x
        uint256 balance = IERC20(inputToken).balanceOf(address(this));
        // x * 97 / 100 (for example)
        uint256 balanceWithSlippage = balance * (100 - slippage) / ONE_HUNDRED;

        uint amountOut;
        address outputToken;
        // prevents stack too deep error
        {
            (uint112 reserves0, uint112 reserves1,) = IUniswapV2Pair(dex).getReserves();
            // determines amountOut and dest token
            if (IUniswapV2Pair(dex).token0() == inputToken) {
                amountOut = getAmountOut(balanceWithSlippage, reserves0, reserves1, fee);
                outputToken = IUniswapV2Pair(dex).token1();
            } else {
                amountOut = getAmountOut(balanceWithSlippage, reserves1, reserves0, fee);
                outputToken = IUniswapV2Pair(dex).token0();
            }
        }

        // A bit more tokens transferred to dex, but passed only balanceWithSlippage
        // we compare new balance with desired amount => outputToken

        // buy stage
        safeTransfer(inputToken, dex, balance);

        // determines output tokens before swap
        uint256 actualAmountOut = IERC20(outputToken).balanceOf(address(this));
        // make swap, records gas
        uint usedGas = gasleft();

        // prevents stack too deep
        {
            (uint amount0Out, uint amount1Out) = inputToken == IUniswapV2Pair(dex).token0() ? (uint(0), amountOut) : (amountOut, uint(0));
            IUniswapV2Pair(dex).swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
        // figure out how many gas has been spent
        usedGas = usedGas - gasleft();

        // no safe math needed due to compile version above 0.8
        actualAmountOut = IERC20(outputToken).balanceOf(address(this)) - actualAmountOut;

        result = DexReport(balance, balanceWithSlippage, amountOut, actualAmountOut, usedGas);
    }

    function makeTransfer(address token) private returns (TransferReport memory report) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "Empty account");

        uint balanceBefore = IERC20(token).balanceOf(address(bob));

        uint usedGas = gasleft();
        IERC20(token).transfer(address(bob), balance);
        usedGas = usedGas - gasleft();

        uint balanceAfter = IERC20(token).balanceOf(address(bob));

        report = TransferReport(balance, balanceAfter - balanceBefore, usedGas);
    }

    function makeApprove(address token) private returns (ApproveReport memory report) {
        return bob.approveForOwner(token);
    }

    function makeTransferFrom(address token) private returns (TransferReport memory report) {
        uint balanceBefore = IERC20(token).balanceOf(address(this));

        uint balance = IERC20(token).balanceOf(address(bob));
        uint usedGas = gasleft();
        IERC20(token).transferFrom(address(bob), address(this), balance);
        usedGas = usedGas - gasleft();

        uint balanceAfter = IERC20(token).balanceOf(address(this));

        return TransferReport(balance, balanceAfter - balanceBefore, usedGas);
    }

    function sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    function getAmountOut(uint amountIn,
        uint reserveIn,
        uint reserveOut,
        DexFee memory fee
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

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }


    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    )
    internal
    pure
    returns (bytes memory)
    {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
                tempBytes := mload(0x40)

            // The first word of the slice result is potentially a partial
            // word read from the original array. To read it, we calculate
            // the length of that partial word and start copying that many
            // bytes into the array. The first word we copy will start with
            // data we don't care about, but the last `lengthmod` bytes will
            // land at the beginning of the contents of the new array. When
            // we're done copying, we overwrite the full first word with
            // the actual length of the slice.
                let lengthmod := and(_length, 31)

            // The multiplication in the next line is necessary
            // because when slicing multiples of 32 bytes (lengthmod == 0)
            // the following copy loop was copying the origin's length
            // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                // The multiplication in the next line has the same exact purpose
                // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

            //update free-memory pointer
            //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
            //zero out the 32 bytes slice we are about to return
            //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

}
