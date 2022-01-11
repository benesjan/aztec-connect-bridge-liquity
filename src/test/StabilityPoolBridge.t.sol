// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

import "../StabilityPoolBridge.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private stabilityPoolBridge;

    function setUp() public {
        setUpTokens();

        address rollupProcessor = address(0);
        address stabilityPool = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        address frontEndTag = address(0);

        stabilityPoolBridge = new StabilityPoolBridge(rollupProcessor, tokens["LUSD"].addr, stabilityPool, frontEndTag);
    }

    function test_initialERC20Params() public {
        assertEq(stabilityPoolBridge.name(), "StabilityPoolBridge");
        assertEq(stabilityPoolBridge.symbol(), "SPB");
        assertEq(uint256(stabilityPoolBridge.decimals()), 18);
    }
}
