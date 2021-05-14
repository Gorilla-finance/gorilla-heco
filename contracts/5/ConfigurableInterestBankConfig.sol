// SPDX-License-Identifier: MIT

pragma solidity 0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

import "./BankConfig.sol";
import "./interfaces/IGoblin.sol";
import "./interfaces/IPriceOracle.sol";
import "./libs/SafeToken.sol";


contract ConfigurableInterestBankConfig is Ownable, BankConfig {
    using SafeToken for address;
    using SafeMath for uint256;

    struct GoblinConfig {
        bool isGoblin;
        uint64 maxPriceDiff;
    }
    /// Mapping for goblin address to its configuration.
    mapping(address => GoblinConfig) public goblins;
    IPriceOracle public oracle;
    bool checkPrice = false;

    constructor(
        uint256 _reservePoolBps,
        uint256 _liquidateBps,
        InterestModel _interestModel
    ) public {
        setParams(_reservePoolBps, _liquidateBps, _interestModel);
    }

    /// @dev Set oracle address. Must be called by owner.
    function setOracle(IPriceOracle _oracle) external onlyOwner {
        oracle = _oracle;
    }

    /// @dev Set oracle address. Must be called by owner.
    function setCheckPrice(bool _checkPrice) external onlyOwner {
        checkPrice = _checkPrice;
    }

    // Set all the basic parameters. Must only be called by the owner.
    function setParams(
        uint256 _reservePoolBps,
        uint256 _liquidateBps,
        InterestModel _interestModel
    ) public onlyOwner {
        reserveBps = _reservePoolBps;
        liquidateBps = _liquidateBps;
        interestModel = _interestModel;
    }

    /// @dev Set the configuration for the given goblin. Must only be called by the owner.
    function setGoblin(
        address _goblin,
        bool _isGoblin,
        uint64 _maxPriceDiff

    ) public onlyOwner {
        goblins[_goblin] = GoblinConfig({
        isGoblin : _isGoblin,
        maxPriceDiff : _maxPriceDiff
        });
    }

    // Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256) {
        return interestModel.getInterestRate(debt, floating);
    }

    function getReserveBps() external view returns (uint256){
        return reserveBps;
    }

    function getLiquidateBps() external view returns (uint256){
        return liquidateBps;
    }

    /// @dev Return whether the given address is a goblin.
    function isGoblin(address goblin) external view returns (bool) {
        require(isStable(goblin), "!stable");
        return goblins[goblin].isGoblin;
    }

    /// @dev Return whether the given goblin is stable, presumably not under manipulation.
    function isStable(address goblin) public view returns (bool) {
        if (!checkPrice || address(oracle) == address(0)) return true;
        IMdexPair lp = IGoblin(goblin).lpToken();
        address token0 = lp.token0();
        address token1 = lp.token1();
        // 1. Check that reserves and balances are consistent (within 1%)
        (uint256 r0, uint256 r1,) = lp.getReserves();
        uint256 t0bal = token0.balanceOf(address(lp));
        uint256 t1bal = token1.balanceOf(address(lp));
        require(t0bal.mul(100) <= r0.mul(101), "bad t0 balance");
        require(t1bal.mul(100) <= r1.mul(101), "bad t1 balance");
        // 2. Check that price is in the acceptable range
        (uint256 price, uint256 lastUpdate) = oracle.getPrice(token0, token1);
        require(lastUpdate >= now - 7 days, "price too stale");
        uint256 lpPrice = r1.mul(1e18).div(r0);
        uint256 maxPriceDiff = goblins[goblin].maxPriceDiff;
        require(lpPrice <= price.mul(maxPriceDiff).div(10000), "price too high");
        require(lpPrice >= price.mul(10000).div(maxPriceDiff), "price too low");
        // 3. Done
        return true;
    }
}
