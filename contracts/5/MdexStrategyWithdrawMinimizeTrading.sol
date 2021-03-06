// SPDX-License-Identifier: MIT

pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "./libs/SafeToken.sol";
import "./interfaces/IStrategy.sol";
import "../interfaces/IWHT.sol";
import "../interfaces/IMdexPair.sol";
import "../interfaces/IMdexRouter.sol";
import "../interfaces/IMdexFactory.sol";
import "../interfaces/ISwapMining.sol";

contract MdexStrategyWithdrawMinimizeTrading is Ownable, ReentrancyGuard, IStrategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IMdexFactory public factory;
    IMdexRouter public router;
    address public wht;

    /// @dev Create a new withdraw minimize trading strategy instance for mdx.
    /// @param _router The mdx router smart contract.
    constructor(IMdexRouter _router) public {
        factory = IMdexFactory(_router.factory());
        router = _router;
        wht = _router.WHT();
    }

    /// @dev Execute worker strategy. Take LP tokens. Return debt token + token want back.
    /// @param user User address to withdraw liquidity.
    /// @param borrowToken The token user borrow from bank.
    /// @param debt User's debt amount.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(
        address user,
        address borrowToken,
        uint256, /* borrow */
        uint256 debt,
        bytes calldata data
    ) external payable nonReentrant {
        
        // 1. Find out lpToken and liquidity.
        // whichWantBack: 0:token0;1:token1;2:token what surplus.
        (address token0, address token1, uint256 whichWantBack) = abi.decode(data, (address, address, uint256));

        // is borrowToken is ht.
        bool isBorrowHt = borrowToken == address(0);
        borrowToken = isBorrowHt ? wht : borrowToken;

        // the relative token when token0 or token1 is ht.
        address htRelative = address(0);
        {
            if (token0 == address(0)) {
                token0 = wht;
                htRelative = token1;
            }
            if (token1 == address(0)) {
                token1 = wht;
                htRelative = token0;
            }
        }
        require(borrowToken == token0 || borrowToken == token1, "borrowToken not token0 and token1");
        require(
            whichWantBack == uint256(0) || whichWantBack == uint256(1) || whichWantBack == uint256(2),
            "whichWantBack not in (0,1,2)"
        );

        address tokenUserWant = whichWantBack == uint256(0) ? token0 : token1;
        IMdexPair lpToken = IMdexPair(factory.getPair(token0, token1));
        token0 = lpToken.token0();
        token1 = lpToken.token1();

        {
            
            
            lpToken.approve(address(router), uint256(- 1));
            router.removeLiquidity(token0, token1, lpToken.balanceOf(address(this)), 0, 0, address(this), now);
        }
        {
            address tokenRelative = borrowToken == token0 ? token1 : token0;

            
            swapIfNeed(borrowToken, tokenRelative, debt);

            if (isBorrowHt) {
                IWHT(wht).withdraw(debt);
                SafeToken.safeTransferETH(msg.sender, debt);
            } else {
                SafeToken.safeTransfer(borrowToken, msg.sender, debt);
            }
        }

        

        // 2. swap remaining token to what user want.
        if (whichWantBack != uint256(2)) {
            address tokenAnother = tokenUserWant == token0 ? token1 : token0;
            uint256 anotherAmount = tokenAnother.myBalance();
            if (anotherAmount > 0) {
                tokenAnother.safeApprove(address(router), 0);
                tokenAnother.safeApprove(address(router), uint256(- 1));
                
                address[] memory path = new address[](2);
                path[0] = tokenAnother;
                path[1] = tokenUserWant;
                router.swapExactTokensForTokens(anotherAmount, 0, path, address(this), now);
            }
        }

        // 3. send all tokens back.
        if (htRelative == address(0)) {
            token0.safeTransfer(user, token0.myBalance());
            token1.safeTransfer(user, token1.myBalance());
        } else {
            safeUnWrapperAndAllSend(wht, user);
            safeUnWrapperAndAllSend(htRelative, user);
        }
    }

    /// swap if need.
    function swapIfNeed(
        address borrowToken,
        address tokenRelative,
        uint256 debt
    ) internal {
        uint256 borrowTokenAmount = borrowToken.myBalance();
        if (debt > borrowTokenAmount) {
            tokenRelative.safeApprove(address(router), uint256(- 1));
            uint256 remainingDebt = debt.sub(borrowTokenAmount);
            address[] memory path = new address[](2);
            path[0] = tokenRelative;
            path[1] = borrowToken;
            
            
            
            router.swapTokensForExactTokens(remainingDebt, tokenRelative.myBalance(), path, address(this), now);
            tokenRelative.safeApprove(address(router), 0);
        }
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

    /// @param minter The address of MDex SwapMining contract.
    /// @param pid pid pid of pair in SwapMining config.
    function getSwapReward(address minter, uint256 pid) public view returns (uint256, uint256) {
        ISwapMining swapMining = ISwapMining(minter);
        return swapMining.getUserReward(pid);
    }

    /// @param minter The address of MDex SwapMining contract.
    /// @param token Token of reward. Result of pairOfPid(lpTokenAddress)
    function swapMiningReward(address minter, address token) external onlyOwner {
        ISwapMining swapMining = ISwapMining(minter);
        swapMining.takerWithdraw();
        token.safeTransfer(msg.sender, token.myBalance());
    }

    /// @dev Recover ERC20 tokens that were accidentally sent to this smart contract.
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
