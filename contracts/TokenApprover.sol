pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenApprover {

    address private immutable thisAddress;

    constructor() {
        thisAddress = address(this);
    }

    function giveApprove(address token, uint256 amount) external {
        safeApprove(token, msg.sender, amount);
    }

    function safeApprove(address token, address to, uint value) private {
        bytes4 signature = bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(signature, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Approve failed');
    }
}
