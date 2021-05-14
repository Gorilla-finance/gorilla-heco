// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "./GToken.sol";

contract GTokenFactory {
    function genWrapperToken(string memory _symbol, uint8 _decimals) public returns (address) {
        return address(new GToken(_symbol, _decimals));
    }
}
