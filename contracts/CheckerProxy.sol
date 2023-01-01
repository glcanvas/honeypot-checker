pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract CheckerProxy is ERC1967Proxy {
    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "Only admin");
        _;
    }

    constructor(address checkerAddress) ERC1967Proxy(checkerAddress, new bytes(0)) {
        _changeAdmin(msg.sender);
        address impl = _getImplementation();
        bytes memory initializeFunction = abi.encodePacked(bytes4(keccak256("initialize()")));
        Address.functionDelegateCall(impl, initializeFunction);
    }

    function changeImplementation(address newImplementation) external onlyAdmin {
        bytes memory initializeFunction = abi.encodePacked(bytes4(keccak256("initialize()")));
        _upgradeToAndCall(newImplementation, initializeFunction, false);
    }
}
