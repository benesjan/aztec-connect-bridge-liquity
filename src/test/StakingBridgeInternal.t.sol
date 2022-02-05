// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "../StakingBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StakingBridgeTestInternal is TestUtil, StakingBridge(address(0)) {
    function setUp() public {
        setUpTokens();
    }

    function testSwapRewardsToLQTY() public {
        mint("LUSD", address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 stakedLQTYBeforeSwap = STAKING_CONTRACT.stakes(address(this));
        _swapRewardsToLQTYAndStake();
        uint256 stakedLQTYAfterSwap = STAKING_CONTRACT.stakes(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(stakedLQTYAfterSwap, stakedLQTYBeforeSwap);

        // Verify that all the rewards were swapped and staked
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);
    }
}
