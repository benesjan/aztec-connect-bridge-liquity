// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../StakingBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StakingBridgeTestInternal is TestUtil, StakingBridge(address(0)) {
    function setUp() public {
        setUpTokens();
    }

    function testSwapRewardsToLQTY() public {
        mint("LUSD", address(this), 1000 * WAD);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        address(0).transfer(address(this).balance - 1 ether);

        uint256 lqtyBalanceBefore = IERC20(tokens["LUSD"].addr).balanceOf(address(STAKING_CONTRACT));

        uint amountLQTYOut = _swapRewardsToLQTY();

        // Verify that rewards were swapped for non-zero amount
        assertGt(amountLQTYOut, 0);

        uint256 lqtyBalanceAfter = IERC20(tokens["LUSD"].addr).balanceOf(address(STAKING_CONTRACT));

        // Verify that all the rewards were swapped
        assertEq(IERC20(tokens["WETH"].addr).balanceOf(address(this)), 0);
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(this)), 0);
        assertEq(IERC20(tokens["LQTY"].addr).balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);

        // Verify that LQTY was correctly deposited
//        assertGt(lqtyBalanceAfter, lqtyBalanceBefore);
    }
}
