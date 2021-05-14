// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Detailed.sol";
import "./libs/SafeToken.sol";

contract GToken is ERC20, ERC20Detailed, Ownable {
    using SafeToken for address;
    using SafeMath for uint256;

    event Mint(address sender, address account, uint256 amount);
    event Burn(address sender, address account, uint256 amount);

    constructor(string memory _symbol, uint8 _decimals) public ERC20Detailed(_symbol, _symbol, _decimals)  {
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
        emit Mint(msg.sender, account, amount);
    }

    function burn(address account, uint256 value) public onlyOwner {
        _burn(account, value);
        emit Burn(msg.sender, account, value);
    }
}
