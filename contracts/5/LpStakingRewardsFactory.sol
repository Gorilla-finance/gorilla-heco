// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./LpStakingRewards.sol";

contract LpStakingRewardsFactory is Ownable {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct LpStakingRewardsInfo {
        address lpStakingRewards;
        uint256 rewardAmount;
    }

    // rewards info by staking token
    mapping(address => LpStakingRewardsInfo) public lpStakingRewardsInfoByStakingToken;

    /// gor平台币
    constructor(address _rewardsToken) public Ownable() {
        rewardsToken = _rewardsToken;
    }

    function createStakingReward(
        address operator,
        address stakingToken, // mdxpair
        uint256 rewardAmount,
        uint256 startTime
    ) public onlyOwner {
        createStakingReward1(operator, stakingToken, rewardAmount, startTime, 7 days, 12, 70);
    }

    function createStakingReward1(
        address operator,
        address stakingToken, // mdxpair
        uint256 rewardAmount,
        uint256 startTime,
        uint256 rewardsDuration,
        uint256 leftRewardTimes,
        uint256 nextPercent
    ) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards == address(0), "LpStakingRewardsFactory::deploy: already deployed");
        info.lpStakingRewards = address(
            new LpStakingRewards(
                address(this), /*_rewardsDistribution=*/
                operator,
                rewardsToken,
                rewardAmount,
                startTime,
                rewardsDuration,
                leftRewardTimes,
                nextPercent
            )
        );
        stakingTokens.push(stakingToken);
    }

    // notify initial reward amount for an individual staking token.
    function notifyRewardAmount(address stakingToken, uint256 rewardAmount) external onlyOwner {
        require(rewardAmount > 0, "amount should > 0");
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::notifyRewardAmount: not deployed");
        if (info.rewardAmount <= 0) {
            info.rewardAmount = rewardAmount;
            LpStakingRewards(info.lpStakingRewards).notifyRewardAmount(rewardAmount);
        }
    }

    function setOperator(address stakingToken, address operator) external onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::setOperator: not deployed");
        LpStakingRewards(info.lpStakingRewards).setOperator(operator);
    }

    function burn(address stakingToken, uint256 amount) external onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::burn: not deployed");
        LpStakingRewards(info.lpStakingRewards).burn(amount);
    }
}
