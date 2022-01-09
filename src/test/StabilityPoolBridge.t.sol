// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

import "../../lib/ds-test/src/test.sol";
import "../StabilityPoolBridge.sol";

contract StabilityPoolBridgeTest is DSTest {
    StabilityPoolBridge private stabilityPoolBridge;

    function setUp() public {
        // For now I will set rollupProcessor and stabilityPool to zero addresses
        // as interaction with them is not yet necessary
        stabilityPoolBridge = new StabilityPoolBridge(address(0), address(0), address(0));
    }

    function test_registerFrontEnd() public {
        // Testing addresses
        address addr1 = address(1);
        address addr2 = address(2);

        // Check if first frontend registration sets id to 1 and
        // if the return address is correct
        stabilityPoolBridge.registerFrontEnd(addr1);
        assertEq(stabilityPoolBridge.frontEndIds(addr1), uint(1));
        assertEq(stabilityPoolBridge.frontEndTags(uint64(1)), addr1);

        // Check if frontend id got incremented the second time
        stabilityPoolBridge.registerFrontEnd(addr2);
        assertEq(stabilityPoolBridge.frontEndIds(addr2), uint(2));
        assertEq(stabilityPoolBridge.frontEndTags(uint64(2)), addr2);

        // Verify that frontend can't be registered twice
        try stabilityPoolBridge.registerFrontEnd(addr1) {
            assertTrue(false, "StabilityPoolBridgeTest: REPEATED_REGISTRATION_CHECK_FAILED");
        } catch Error(string memory reason) {
            assertEq(reason, "StabilityPoolBridge: TAG_ALREADY_REGISTERED");
        }
    }
}
