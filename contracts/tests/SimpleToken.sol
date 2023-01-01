pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleToken is ERC20 {
    constructor() ERC20("NoFeeToken", "T1") {
        _mint(msg.sender, 10 ** 18);
    }
}
