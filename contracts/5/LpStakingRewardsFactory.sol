// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "./libs/@openzeppelin/contracts/ownership/Ownable.sol";
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

    constructor(address _rewardsToken) public Ownable() {
        rewardsToken = _rewardsToken;
    }

    ///// permissioned functions
    // deploy a staking reward contract for the staking token, and store the total reward amount
    // hecoPoolId: set -1 if not stake lpToken to Heco
    function createStakingReward(
        address operator,
        address stakingToken,
        uint256 rewardAmount,
        address pool,
        int256 poolId,
        address earnToken,
        uint256 startTime
    ) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards == address(0), "LpStakingRewardsFactory::deploy: already deployed");
        info.lpStakingRewards = address(
            new LpStakingRewards(
                /*_rewardsDistribution=*/
                address(this),
                operator,
                rewardsToken,
                stakingToken,
                rewardAmount,
                pool,
                poolId,
                earnToken,
                startTime
            )
        );
        stakingTokens.push(stakingToken);
    }

    // notify initial reward amount for an individual staking token.
    function notifyRewardAmount(address stakingToken, uint256 rewardAmount) public onlyOwner {
        require(rewardAmount > 0, "amount should > 0");
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::notifyRewardAmount: not deployed");
        if (info.rewardAmount <= 0) {
            info.rewardAmount = rewardAmount;
            LpStakingRewards(info.lpStakingRewards).notifyRewardAmount(rewardAmount);
        }
    }

    function setOperator(address stakingToken, address operator) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::setOperator: not deployed");
        LpStakingRewards(info.lpStakingRewards).setOperator(operator);
    }

    function setPool(address stakingToken, address pool) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::setOperator: not deployed");
        LpStakingRewards(info.lpStakingRewards).setPool(pool);
    }

    function setPoolId(address stakingToken, int256 poolId) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::setOperator: not deployed");
        LpStakingRewards(info.lpStakingRewards).setPoolId(poolId);
    }

    function claim(address stakingToken, address to) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::claim: not deployed");
        LpStakingRewards(info.lpStakingRewards).claim(to);
    }

    function burn(address stakingToken, uint256 amount) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), "LpStakingRewardsFactory::burn: not deployed");
        LpStakingRewards(info.lpStakingRewards).burn(amount);
    }
}
