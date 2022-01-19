// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../StabilityPoolBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTestInternal is TestUtil, StabilityPoolBridge(address(0), address(0)) {
    function setUp() public {
        setUpTokens();
    }

    function testSwapRewardsOnUni() public {
        mint("LQTY", address(this), 1000 * WAD);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        address(0).transfer(address(this).balance - 1 ether);

        uint256 depositedLUSDBeforeSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));
        _swapRewardsToLUSDAndDeposit();
        uint256 depositedLUSDAfterSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(depositedLUSDAfterSwap, depositedLUSDBeforeSwap);

        // Verify that all the rewards were swapped to LUSD
        assertEq(IERC20(tokens["WETH"].addr).balanceOf(address(this)), 0);
        assertEq(IERC20(tokens["LQTY"].addr).balanceOf(address(this)), 0);
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);
    }
}
