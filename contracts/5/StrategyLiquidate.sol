// SPDX-License-Identifier: MIT

pragma solidity 0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

import "./libs/SafeToken.sol";
import "./interfaces/IStrategy.sol";
import "../interfaces/IMdexFactory.sol";
import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdexPair.sol";
import "../interfaces/IWHT.sol";

contract StrategyLiquidate is Ownable, ReentrancyGuard, IStrategy {
    using SafeToken for address;

    IMdexFactory public factory;
    IMdexRouter public router;
    address public wht;

    //TODO: 参数改成，MdexRouter
    // Create a new liquidate strategy instance.
    /// @param _router The Uniswap router smart contract.
    constructor(IMdexRouter _router) public {
        factory = IMdexFactory(_router.factory());
        router = _router;
        wht = _router.WHT();
    }

    // Execute worker strategy. Take LP tokens + ETH. Return LP tokens + ETH .
    /// @param data Extra calldata information passed along to this strategy.
    /// 不处理ht的情况，直接拿wht
    function execute(
        address,
        address borrowToken,
        uint256,
        uint256,
        bytes calldata data
    ) external payable nonReentrant {
        
        // 1. Find out what farming token we are dealing with.
        bool isBorrowHt = borrowToken == address(0);
        borrowToken = isBorrowHt ? wht : borrowToken;
        address lpToken = abi.decode(data, (address));
        IMdexPair pair = IMdexPair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        (address baseToken, address farmingToken) = borrowToken == token0 ? (token0, token1) : (token1, token0);
        // 2. Approve router to do their stuffs
        lpToken.safeApprove(address(router), uint256(- 1));
        farmingToken.safeApprove(address(router), uint256(- 1));

        // 3. Remove all liquidity back to ETH and farming tokens.
        router.removeLiquidity(baseToken, farmingToken, lpToken.balanceOf(address(this)), 0, 0, address(this), now);

        // 4. Convert farming tokens to baseToken.
        address[] memory path = new address[](2);
        path[0] = farmingToken;
        path[1] = baseToken;
        router.swapExactTokensForTokens(farmingToken.myBalance(), 0, path, address(this), now);

        // 5. Return all baseToken back to the original caller.
        safeUnWrapperAndAllSend(borrowToken, msg.sender);

        // 6. Reset approve for safety reason
        lpToken.safeApprove(address(router), 0);
        farmingToken.safeApprove(address(router), 0);
    }

    /// get token balance, if is WHT un wrapper to HT and send to 'to'
    function safeUnWrapperAndAllSend(address token, address to) internal {
        uint256 total = SafeToken.myBalance(token);
        if (total > 0) {
            if (token == wht) {
                IWHT(wht).withdraw(total);
                SafeToken.safeTransferETH(to, total);
            } else {
                SafeToken.safeTransfer(token, to, total);
            }
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

    function() external payable {}
}
