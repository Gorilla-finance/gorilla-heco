// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./StakingRewards.sol";

contract StakingRewardsFactory is Ownable {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint256 rewardAmount;
    }

    // rewards info by staking token
    mapping(address => StakingRewardsInfo)
        public stakingRewardsInfoByStakingToken;

    constructor(address _rewardsToken) public Ownable() {
        rewardsToken = _rewardsToken;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the total reward amount
    function createStakingReward(
        address stakingToken,
        uint256 rewardAmount,
        uint256 startTime
    ) public onlyOwner {
        createStakingReward1(stakingToken, rewardAmount, startTime, 7 days, 12, 70);
    }

    function createStakingReward1(
        address stakingToken,
        uint256 rewardAmount,
        uint256 startTime,
        uint256 rewardsDuration,
        uint256 leftRewardTimes,
        uint256 nextPercent
    ) public onlyOwner {
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards == address(0),
            "StakingRewardsFactory::deploy: already deployed"
        );
        info.stakingRewards = address(
            new StakingRewards(
                address(this),
                rewardsToken,
                stakingToken,
                rewardAmount,
                startTime,
                rewardsDuration,
                leftRewardTimes,
                nextPercent
            )
        );
        info.rewardAmount = rewardAmount;
        stakingTokens.push(stakingToken);
    }

    // notify initial reward amount for an individual staking token.
    function notifyRewardAmount(address stakingToken, uint256 rewardAmount)
        external
        onlyOwner
    {
        require(rewardAmount > 0, "amount should > 0");
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards != address(0),
            "StakingRewardsFactory::notifyRewardAmount: not deployed"
        );
        if (info.rewardAmount <= 0) {
            info.rewardAmount = rewardAmount;
            StakingRewards(info.stakingRewards).notifyRewardAmount(
                rewardAmount
            );
        }
    }

    function burn(address stakingToken, uint256 amount) external onlyOwner {
        StakingRewardsInfo storage info =
            stakingRewardsInfoByStakingToken[stakingToken];
        require(
            info.stakingRewards != address(0),
            "StakingRewardsFactory::burn: not deployed"
        );
        StakingRewards(info.stakingRewards).burn(amount);
    }
}
