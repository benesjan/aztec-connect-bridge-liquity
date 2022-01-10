// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

import "../../lib/ds-test/src/test.sol";
import "../StabilityPoolBridge.sol";

contract StabilityPoolBridgeTest is DSTest {
    StabilityPoolBridge private stabilityPoolBridge;

    function setUp() public {
        // For now I will set rollupProcessor and stabilityPool to zero addresses
        // as interaction with them is not yet necessary
        stabilityPoolBridge = new StabilityPoolBridge(address(0), address(0), address(0), address(0));
    }

    function test_initialERC20Params() public {
        assertEq(stabilityPoolBridge.name(), "StabilityPoolBridge");
        assertEq(stabilityPoolBridge.symbol(), "SPB");
        assertEq(uint256(stabilityPoolBridge.decimals()), 18);
    }
}
