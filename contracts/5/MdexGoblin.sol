// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IGoblin.sol";
import "../interfaces/IMdexFactory.sol";
import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdexPair.sol";
import "./interfaces/ILPStakingRewards.sol";
import "./libs/SafeToken.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IMdexChef.sol";

contract MdexGoblin is Ownable, ReentrancyGuard, IGoblin {
    /// @notice Libraries
    using SafeToken for address;
    using SafeMath for uint256;

    /// @notice Events
    event AddPosition(uint256 indexed id, uint256 lpAmount);
    event RemovePosition(uint256 indexed id, uint256 lpAmount);
    event Liquidate(
        uint256 indexed id,
        address lpTokenAddress,
        uint256 lpAmount,
        address debtToken,
        uint256 liqAmount
    );

    /// @notice Immutable variables
    ILPStakingRewards public staking;
    IMdexFactory public factory;
    IMdexRouter public router;
    IMdexPair public lpToken;
    address public wht;
    address public token0;
    address public token1;
    address public operator;

    // posid => lptokenAmount, posid是和用户绑定的，所以这个就是用户一开始投入的lptoken amount
    mapping(uint256 => uint256) public posLPAmount;
    mapping(address => bool) public okStrategies;
    IStrategy public liqStrategy;

    // reinvest

    // 一开始投入的lptoken数量
    uint256 public totalLPAmount;
    // 总的lptoken份额
    uint256 public totalShare;
    // shareid => 份额，由于复投的机制，份额会增加
    mapping(uint256 => uint256) public shares;
    mapping(address => bool) public okReinvestors;
    uint256 public reinvestBountyBps;
    IStrategy public addStrat;
    // mdx heco pool 里面 lp 的 id
    uint256 public poolId;
    // mdx质押lptoken的池子
    IMdexChef public chef;
    // mdx
    IERC20 public earnToken;

    event WithdrawnHecoPool(address indexed user, uint256 amount);
    event StakedHecoPool(address indexed user, uint256 amount);
    event Reinvest(address indexed caller, uint256 reward, uint256 bounty);
    event AddShare(uint256 indexed id, uint256 share);
    event RemoveShare(uint256 indexed id, uint256 share);

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "LpStakingRewards::onlyEOA:: not eoa");
        _;
    }

    constructor(
        address _operator,
        ILPStakingRewards _staking,
        IMdexRouter _router,
        address _token0,
        address _token1,
        IStrategy _liqStrategy,
        address _pool,
        uint256 _poolId,
        address _earnToken,
        uint256 _reinvestBountyBps
    ) public {
        operator = _operator;
        wht = _router.WHT();
        staking = _staking;
        router = _router;
        factory = IMdexFactory(_router.factory());

        _token0 = _token0 == address(0) ? wht : _token0;
        _token1 = _token1 == address(0) ? wht : _token1;

        lpToken = IMdexPair(factory.getPair(_token0, _token1));
        token0 = lpToken.token0();
        token1 = lpToken.token1();

        liqStrategy = _liqStrategy;
        okStrategies[address(liqStrategy)] = true;

        chef = IMdexChef(_pool);
        poolId = _poolId;
        earnToken = IERC20(_earnToken);
        router = _router;
        reinvestBountyBps = _reinvestBountyBps;
    }

    // Require that the caller must be the operator (the bank).
    modifier onlyOperator() {
        require(msg.sender == operator, "not operator");
        _;
    }

    //// @dev Require that the caller must be ok reinvestor.
    modifier onlyReinvestor() {
        require(okReinvestors[msg.sender], "MdexGoblin::onlyReinvestor:: not reinvestor");
        _;
    }

    /// @dev Set the given address's to be reinvestor.
    /// @param reinvestors The reinvest bot addresses.
    /// @param isOk Whether to approve or unapprove the given strategies.
    function setReinvestorOk(address[] calldata reinvestors, bool isOk) external onlyOwner {
        uint256 len = reinvestors.length;
        for (uint256 idx = 0; idx < len; idx++) {
            okReinvestors[reinvestors[idx]] = isOk;
        }
    }
    /// @dev Set the reward bounty for calling reinvest operations.
    /// @param _reinvestBountyBps The bounty value to update.
    function setReinvestBountyBps(uint256 _reinvestBountyBps) external onlyOwner {
        reinvestBountyBps = _reinvestBountyBps;
    }

    function setAddStrat(IStrategy _addStrat) external onlyOwner {
        addStrat = _addStrat;
    }

    /// @dev Return the entitied LP token balance for the given shares.
    /// @param share The number of shares to be converted to LP balance.
    function shareToBalance(uint256 share) public view returns (uint256) {
        
        if (totalShare == 0) return share;
        // When there's no share, 1 share = 1 balance.
        (uint256 totalBalance,,) = chef.userInfo(poolId, address(this));
        
        return share.mul(totalBalance).div(totalShare);
    }

    /// @dev Return the number of shares to receive if staking the given LP tokens.
    /// @param balance the number of LP tokens to be converted to shares.
    function balanceToShare(uint256 balance) public view returns (uint256) {
        
        if (totalShare == 0) return balance;
        // When there's no share, 1 share = 1 balance.
        (uint256 totalBalance,,) = chef.userInfo(poolId, address(this));
        
        
        return balance.mul(totalShare).div(totalBalance);
    }

    // Work on the given position. Must be called by the operator.
    /// @param id The position ID to work on.
    /// @param user The original user that is interacting with the operator.
    /// @param borrowToken The token user borrow from bank.
    /// @param borrow The amount user borrow form bank.
    /// @param debt The user's debt amount.
    /// @param data The encoded data, consisting of strategy address and bytes to strategy.
    function work(
        uint256 id,
        address user,
        address borrowToken,
        uint256 borrow,
        uint256 debt,
        bytes calldata data
    ) external payable onlyOperator nonReentrant {
        

        require(
            borrowToken == token0 ||
            borrowToken == token1 ||
            borrowToken == address(0),
            "borrowToken not token0 and token1"
        );

        // 1. Convert this position back to LP tokens.
        _removePosition(id, user);
        _removeShare(id);

        // 2. Perform the worker strategy; sending LP tokens + borrowToken; expecting LP tokens.
        (address strategy, bytes memory ext) =
        abi.decode(data, (address, bytes));
        require(okStrategies[strategy], "unapproved work strategy");

        
        lpToken.transfer(strategy, lpToken.balanceOf(address(this)));

        // transfer the borrow token.
        if (borrow > 0 && borrowToken != address(0)) {
            borrowToken.safeTransferFrom(msg.sender, address(this), borrow);
            borrowToken.safeApprove(address(strategy), uint256(- 1));
            
        }

        IStrategy(strategy).execute.value(msg.value)(
            user,
            borrowToken,
            borrow,
            debt,
            ext
        );
        //

        // 3. Add LP tokens back to the farming pool.
        _addPosition(id, user);
        _addShare(id);

        if (borrowToken == address(0)) {
            SafeToken.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 borrowTokenAmount = borrowToken.myBalance();
            if (borrowTokenAmount > 0) {
                SafeToken.safeTransfer(
                    borrowToken,
                    msg.sender,
                    borrowTokenAmount
                );
            }
        }
    }

    // Return maximum output given the input amount and the status of Uniswap reserves.
    /// @param aIn The amount of asset to market sell.
    /// @param rIn the amount of asset in reserve for input.
    /// @param rOut The amount of asset in reserve for output.
    function getMktSellAmount(
        uint256 aIn,
        uint256 rIn,
        uint256 rOut
    ) public pure returns (uint256) {
        if (aIn == 0) return 0;
        require(rIn > 0 && rOut > 0, "bad reserve values");
        uint256 aInWithFee = aIn.mul(997);
        uint256 numerator = aInWithFee.mul(rOut);
        uint256 denominator = rIn.mul(1000).add(aInWithFee);
        return numerator / denominator;
    }

    // Return the amount of debt token to 0879\ if we are to liquidate the given position.
    /// @param id The position ID to perform health check.
    /// @param borrowToken The token this position had debt.
    function health(uint256 id, address borrowToken)
    external
    view
    returns (uint256)
    {
        
        bool isDebtHt = borrowToken == address(0);
        require(
            borrowToken == token0 || borrowToken == token1 || isDebtHt,
            "borrowToken not token0 and token1"
        );

        // 1. Get the position's LP balance and LP total supply.
        uint256 lpBalance = shareToBalance(shares[id]);
        

        uint256 lpSupply = lpToken.totalSupply();
        

        // 2. Get the pool's total supply of token0 and token1.
        (uint256 totalAmount0, uint256 totalAmount1,) = lpToken.getReserves();
        

        // 3. Convert the position's LP tokens to the underlying assets.
        uint256 userToken0 = lpBalance.mul(totalAmount0).div(lpSupply);
        uint256 userToken1 = lpBalance.mul(totalAmount1).div(lpSupply);
        

        if (isDebtHt) {
            borrowToken = token0 == wht ? token0 : token1;
        }

        // 4. Convert all farming tokens to debtToken and return total amount.
        if (borrowToken == token0) {
            return
            getMktSellAmount(
                userToken1,
                totalAmount1.sub(userToken1),
                totalAmount0.sub(userToken0)
            )
            .add(userToken0);
        } else {
            return
            getMktSellAmount(
                userToken0,
                totalAmount0.sub(userToken0),
                totalAmount1.sub(userToken1)
            )
            .add(userToken1);
        }
    }

    // Liquidate the given position by converting it to debtToken and return back to caller.
    /// @param id The position ID to perform liquidation.
    /// @param user The address than this position belong to.
    /// @param borrowToken The token user borrow from bank.
    function liquidate(
        uint256 id,
        address user,
        address borrowToken
    ) external onlyOperator nonReentrant {
        
        bool isBorrowHt = borrowToken == address(0);
        require(
            borrowToken == token0 || borrowToken == token1 || isBorrowHt,
            "borrowToken not token0 and token1"
        );

        // 1. Convert the position back to LP tokens and use liquidate strategy.
        _removePosition(id, user);
        _removeShare(id);

        uint256 lpTokenAmount = lpToken.balanceOf(address(this));
        lpToken.transfer(address(liqStrategy), lpTokenAmount);
        liqStrategy.execute(
            address(0),
            borrowToken,
            uint256(0),
            uint256(0),
            abi.encode(address(lpToken))
        );

        // 2. transfer borrowToken and user want back to goblin.
        uint256 tokenLiquidate;
        if (isBorrowHt) {
            tokenLiquidate = address(this).balance;
            SafeToken.safeTransferETH(msg.sender, tokenLiquidate);
        } else {
            tokenLiquidate = borrowToken.myBalance();
            borrowToken.safeTransfer(msg.sender, tokenLiquidate);
        }

        emit Liquidate(
            id,
            address(lpToken),
            lpTokenAmount,
            borrowToken,
            tokenLiquidate
        );
    }

    /// @dev Internal function to stake all outstanding LP tokens to the given position ID.
    function _addShare(uint256 id) internal {
        uint256 balance = lpToken.balanceOf(address(this));
        

        if (balance > 0) {
            // 1. Approve token to be spend by masterChef
            address(lpToken).safeApprove(address(chef), uint256(- 1));

            // 2. Convert balance to share
            uint256 share = balanceToShare(balance);

            // 3. Deposit balance to PancakeMasterChef
            chef.deposit(uint256(poolId), balance);
            emit StakedHecoPool(address(this), balance);

            // 4. Update shares
            shares[id] = shares[id].add(share);
            totalShare = totalShare.add(share);
            // 5. Reset approve token
            address(lpToken).safeApprove(address(chef), 0);
            
            emit AddShare(id, share);
        }
    }

    // Internal function to stake all outstanding LP tokens to the given position ID.
    function _addPosition(uint256 id, address user) internal {
        uint256 lpBalance = lpToken.balanceOf(address(this));
        

        if (lpBalance > 0) {
            // take lpToken to the pool2.
            staking.stake(lpBalance, user);
            totalLPAmount = totalLPAmount.add(lpBalance);
            posLPAmount[id] = posLPAmount[id].add(lpBalance);
            emit AddPosition(id, lpBalance);
        }
    }

    /// @dev Internal function to remove shares of the ID and convert to outstanding LP tokens.
    function _removeShare(uint256 id) internal {
        uint256 share = shares[id];
        
        if (share > 0) {
            uint256 balance = shareToBalance(share);
            // withdraw lp token back
            chef.withdraw(uint256(poolId), balance);
            emit WithdrawnHecoPool(address(this), balance);
            totalShare = totalShare.sub(share);
            
            shares[id] = 0;
            emit RemoveShare(id, share);
        }
    }

    // 处理平台币的奖励
    function _removePosition(uint256 id, address user) internal {
        uint256 lpAmount = posLPAmount[id];

        

        if (lpAmount > 0) {
            posLPAmount[id] = 0;
            totalLPAmount = totalLPAmount.sub(lpAmount);
            staking.withdraw(lpAmount, user);
            emit RemovePosition(id, lpAmount);
        }
    }

    // Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// @param token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// @param to The address to send the tokens to.
    /// @param value The number of tokens to transfer to `to`.
    function recover(
        address token,
        address to,
        uint256 value
    ) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    // Set the given strategies' approval status.
    /// @param strategies The strategy addresses.
    /// @param isOk Whether to approve or unapprove the given strategies.
    function setStrategyOk(address[] calldata strategies, bool isOk)
    external
    onlyOwner
    {
        uint256 len = strategies.length;
        require(len < 10, "strategy too more");
        for (uint256 idx = 0; idx < len; idx++) {
            okStrategies[strategies[idx]] = isOk;
        }
    }

    // Update critical strategy smart contracts. EMERGENCY ONLY. Bad strategies can steal funds.
    /// @param _liqStrategy The new liquidate strategy contract.
    function setCriticalStrategies(IStrategy _liqStrategy) external onlyOwner {
        liqStrategy = _liqStrategy;
    }

    /// @dev Re-invest whatever this worker has earned back to staked LP tokens.
    function reinvest() public onlyEOA onlyReinvestor nonReentrant {
        // 1. Approve tokens
        address(earnToken).safeApprove(address(router), uint256(- 1));
        address(lpToken).safeApprove(address(chef), uint256(- 1));
        // 2. Withdraw all the rewards.
        chef.withdraw(poolId, 0);
        uint256 reward = earnToken.balanceOf(address(this));
        if (reward == 0) return;
        // 3. Send the reward bounty to the caller.
        uint256 bounty = reward.mul(reinvestBountyBps) / 10000;
        if (bounty > 0) address(earnToken).safeTransfer(msg.sender, bounty);
        // 4. Convert all the remaining rewards to BaseToken via Native for liquidity.
        address baseToken = lpToken.token0();
        address farmingToken = lpToken.token1();


        address[] memory path;
        if (baseToken == wht) {
            
            path = new address[](2);
            //mdx
            path[0] = address(earnToken);
            path[1] = address(wht);
        }
        else {
            
            path = new address[](3);
            path[0] = address(earnToken);
            path[1] = address(wht);
            path[2] = address(baseToken);
        }
        
        router.swapExactTokensForTokens(reward.sub(bounty), 0, path, address(this), now);

        // 5. Use add Token strategy to convert all BaseToken to LP tokens.
        // baseToken.safeTransfer(address(addStrat), baseToken.myBalance());
        baseToken.safeApprove(address(addStrat), uint256(- 1));
        addStrat.execute(address(this), farmingToken, 0, 0, abi.encode(baseToken, farmingToken, baseToken.myBalance(), 0, 0));

        // 6. Mint more LP tokens and stake them for more rewards.
        chef.deposit(uint256(poolId), lpToken.balanceOf(address(this)));

        // 7. Reset approve
        baseToken.safeApprove(address(addStrat), 0);
        address(earnToken).safeApprove(address(router), 0);
        address(lpToken).safeApprove(address(chef), 0);
        emit Reinvest(msg.sender, reward, bounty);
    }

    function() external payable {}
}
