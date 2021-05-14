// SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

// Inheritance
interface IBank {
    function deposit(address token, uint256 amount) external;

    function withdraw(address token, uint256 amount) external;
}
