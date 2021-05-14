// SPDX-License-Identifier: MIT

pragma solidity 0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import './BankConfig.sol';

contract SimpleBankConfig is Ownable, BankConfig {
    /// @notice Configuration for each goblin.
    struct GoblinConfig {
        bool isGoblin;
    }

    /// The interest rate per second, multiplied by 1e18.
    uint public interestRate;

    /// Mapping for goblin address to its configuration.
    mapping(address => GoblinConfig) public goblins;

    constructor(
        uint _interestRate,
        uint _reservePoolBps,
        uint _liquidateBps
    ) public {
        setParams(_interestRate, _reservePoolBps, _liquidateBps);
    }

    /// @dev Set all the basic parameters. Must only be called by the owner.
    function setParams(
        uint _interestRate,
        uint _reservePoolBps,
        uint _liquidateBps
    ) public onlyOwner {
        interestRate = _interestRate;
        reserveBps = _reservePoolBps;
        liquidateBps = _liquidateBps;
    }

    /// @dev Set the configuration for the given goblin. Must only be called by the owner.
    /// @param goblin The goblin address to set configuration.
    /// @param _isGoblin Whether the given address is a valid goblin.
    function setGoblin(
        address goblin,
        bool _isGoblin
    ) public onlyOwner {
        goblins[goblin] = GoblinConfig({
        isGoblin : _isGoblin
        });
    }

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(
        uint, /* debt */
        uint /* floating */
    ) external view returns (uint) {
        return interestRate;
    }

    function getReserveBps() external view returns (uint256){
        return reserveBps;
    }

    function getLiquidateBps() external view returns (uint256){
        return liquidateBps;
    }

    /// @dev Return whether the given address is a goblin.
    function isGoblin(address goblin) external view returns (bool) {
        return goblins[goblin].isGoblin;
    }
}
