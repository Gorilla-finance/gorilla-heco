// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "./libs/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libs/@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "./libs/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./libs/@openzeppelin/contracts/ownership/Ownable.sol";
import "./libs/@openzeppelin/contracts/math/SafeMath.sol";

contract MonkeyToken is ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public governance;
    mapping(address => bool) public minters;

    constructor() public ERC20Detailed("MonkeyToken", "MKY", 18) {
        governance = tx.origin;
    }

    function mint(address account, uint256 amount) public {
        require(minters[msg.sender], "!minter");
        _mint(account, amount);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function addMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = true;
    }

    function removeMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = false;
    }

    function burn(address account, uint256 amount) public {
        require(msg.sender == account, "!burn");
        _burn(account, amount);
    }
}
