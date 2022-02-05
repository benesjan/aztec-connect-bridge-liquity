// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "../StabilityPoolBridge.sol";
import "../AztecTypes.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTestInternal is TestUtil, StabilityPoolBridge(address(0), address(0)) {
    function setUp() public {
        _aztecPreSetup();
        setUpTokens();
    }

    function testSwapRewardsOnUni() public {
        mint("LQTY", address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 depositedLUSDBeforeSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));
        _swapRewardsToLUSDAndDeposit();
        uint256 depositedLUSDAfterSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(depositedLUSDAfterSwap, depositedLUSDBeforeSwap);

        // Verify that all the rewards were swapped to LUSD
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);
    }
}
