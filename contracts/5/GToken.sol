// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "./libs/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libs/@openzeppelin/contracts/ownership/Ownable.sol";
import "./libs/@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/SafeToken.sol";

contract GToken is ERC20, Ownable {
    using SafeToken for address;
    using SafeMath for uint256;

    string public name = "";
    string public symbol = "";
    uint8 public decimals = 18;

    event Mint(address sender, address account, uint256 amount);
    event Burn(address sender, address account, uint256 amount);

    constructor(string memory _symbol) public {
        name = _symbol;
        symbol = _symbol;
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
