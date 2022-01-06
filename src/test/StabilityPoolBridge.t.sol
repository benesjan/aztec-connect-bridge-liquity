// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

import "../../lib/ds-test/src/test.sol";
import "../StabilityPoolBridge.sol";

contract StabilityPoolBridgeTest is DSTest {
    StabilityPoolBridge private stabilityPoolBridge;

    function setUp() public {
        // For now I will set rollupProcessor and stabilityPool to zero addresses
        // as interaction with them is not yet necessary
        stabilityPoolBridge = new StabilityPoolBridge(address(0), address(0));
    }

    function test_registerFrontEnd() public {
        stabilityPoolBridge.registerFrontEnd(address(0));
        assertEq(stabilityPoolBridge.frontEndIds(address(0)), uint(1));
        assertEq(stabilityPoolBridge.frontEndTags(uint64(1)), address(0));

        stabilityPoolBridge.registerFrontEnd(address(1));
        assertEq(stabilityPoolBridge.frontEndIds(address(1)), uint(2));
        assertEq(stabilityPoolBridge.frontEndTags(uint64(2)), address(1));
    }
}
