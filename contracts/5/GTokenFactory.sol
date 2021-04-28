// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "./GToken.sol";

contract GTokenFactory {
    function genPToken(string memory _symbol) public returns (address) {
        return address(new PToken(_symbol));
    }
}
