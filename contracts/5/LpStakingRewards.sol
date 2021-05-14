// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Burnable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ILPStakingRewards.sol";
import "./RewardsDistributionRecipient.sol";
import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdexPair.sol";
import "./interfaces/IStrategy.sol";
import "./libs/SafeToken.sol";


contract LpStakingRewards is ILPStakingRewards, RewardsDistributionRecipient, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeToken for address;

    /* ========== STATE VARIABLES ========== */

    address public operator;
    IERC20 public rewardsToken; // gor token
    address public stakingToken; // mdxpair lptoken
    address public wNative;     // wht
    uint256 public startTime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewards = 0;
    uint256 private rewardsNext = 0;
    uint256 public rewardsPaid = 0;
    uint256 public rewardsed = 0;
    uint256 public leftRewardTimes = 12;
    uint256 public nextPercent = 70;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // staking token，lp token，在goblin里面处理转账，不在这里处理
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed operator, address indexed user, uint256 amount);
    event Withdrawn(address indexed operator, address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _rewardsDistribution,
        address _operator,
        address _rewardsToken,
        uint256 _rewardAmount,
        uint256 _startTime,
        uint256 _rewardsDuration,
        uint256 _leftRewardTimes,
        uint256 _nextPercent
    ) public {
        operator = _operator;
        rewardsToken = IERC20(_rewardsToken);
        rewardsDistribution = _rewardsDistribution;
        totalRewards = _rewardAmount;
        startTime = _startTime;
        rewardsDuration = _rewardsDuration;
        leftRewardTimes = _leftRewardTimes;
        nextPercent = _nextPercent;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return
        _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
            rewards[account]
        );
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function stake(uint256 amount, address user)
    external
    nonReentrant
    updateReward(user)
    checkhalve
    checkStart
    checkOperator(user, msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        require(user != address(0), "user cannot be 0");
        address from = operator != address(0) ? operator : user;
        _totalSupply = _totalSupply.add(amount);
        _balances[user] = _balances[user].add(amount);
        //goblin 已经把stakingToken给了heco pool了，没办法在给stake
        //stakingToken.safeTransferFrom(from, address(this), amount);
        emit Staked(from, user, amount);
    }

    function withdraw(uint256 amount, address user)
    public
    nonReentrant
    updateReward(user)
    checkhalve
    checkStart
    checkOperator(user, msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        require(user != address(0), "user cannot be 0");
        require(_balances[user] >= amount, "not enough");
        address to = operator != address(0) ? operator : user;
        _totalSupply = _totalSupply.sub(amount);
        _balances[user] = _balances[user].sub(amount);
        // goblin 处理
        //stakingToken.safeTransfer(to, amount);
        emit Withdrawn(to, user, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) checkhalve checkStart {
        require(msg.sender != address(0), "user cannot be 0");
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsPaid = rewardsPaid.add(reward);
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function burn(uint256 amount) external onlyRewardsDistribution {
        leftRewardTimes = 0;
        rewardsNext = 0;
        (ERC20Burnable(address(rewardsToken))).burn(amount);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier checkhalve() {
        if (block.timestamp >= periodFinish && leftRewardTimes > 0) {
            leftRewardTimes = leftRewardTimes.sub(1);
            uint256 reward = leftRewardTimes == 0 ? totalRewards.sub(rewardsed) : rewardsNext;
            (ERC20Mintable(address(rewardsToken))).mint(address(this), reward);
            rewardsed = rewardsed.add(reward);
            rewardRate = reward.div(rewardsDuration);
            periodFinish = block.timestamp.add(rewardsDuration);
            rewardsNext = leftRewardTimes > 0 ? rewardsNext.mul(nextPercent).div(100) : 0;
            emit RewardAdded(reward);
        }
        _;
    }

    modifier checkStart() {
        require(block.timestamp > startTime, "not start");
        _;
    }

    modifier checkOperator(address user, address sender) {
        require(operator != address(0) && operator == sender, "checkOperator fail");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        require(rewardsed == 0, "reward already inited");
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        (ERC20Mintable(address(rewardsToken))).mint(address(this), reward);
        rewardsed = reward;
        rewardsNext = rewardsed.mul(nextPercent).div(100);
        leftRewardTimes = leftRewardTimes.sub(1);
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function setOperator(address _operator) external onlyRewardsDistribution {
        operator = _operator;
    }
}
