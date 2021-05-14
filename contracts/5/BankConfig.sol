// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./interfaces/IBankConfig.sol";
import "./interfaces/InterestModel.sol";

contract BankConfig is IBankConfig, Ownable {
    uint256 public reserveBps;
    uint256 public liquidateBps;
    InterestModel interestModel;
    constructor() public {}
}
