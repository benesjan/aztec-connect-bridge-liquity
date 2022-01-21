// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../TroveBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract TroveBridgeTest is TestUtil {
    TroveBridge private bridge;

    function setUp() public {
        setUpTokens();
        address rollupProcessor = address(this);
        bridge = new TroveBridge(rollupProcessor);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testOpenTrove() public {

    }
}