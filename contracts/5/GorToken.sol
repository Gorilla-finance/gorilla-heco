// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Burnable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Detailed.sol";

contract GorToken is ERC20Mintable, ERC20Burnable, ERC20Detailed {
    constructor() public ERC20Detailed("GorToken", "GOR", 18) {
    }
}
