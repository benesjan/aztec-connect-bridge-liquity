// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../TroveBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";
import "./interfaces/IHintHelpers.sol";
import "./interfaces/ISortedTroves.sol";

contract TroveBridgeTest is TestUtil {
    TroveBridge private bridge;
    IHintHelpers private constant hintHelpers = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    function setUp() public {
        setUpTokens();
        address rollupProcessor = address(this);
        uint256 initialCollateralRatio = 250;
        bridge = new TroveBridge(rollupProcessor, initialCollateralRatio);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-250");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testOpenTrove() public {
        uint256 ETHColl = 5 * WAD;
        uint256 LUSDAmount = bridge.computeDebt(ETHColl);
        uint256 NICR_PRECISION = 1e20;
        uint256 NICR = ETHColl.mul(NICR_PRECISION).div(LUSDAmount);

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = hintHelpers.getApproxHint(NICR, numTrials, randomSeed);
        (address upperHint, address lowerHint) = sortedTroves.findInsertPosition(NICR, approxHint, approxHint);

        uint256 maxFee = 5 * 10**16; // Slippage protection: 5%
        bridge.openTrove{value: ETHColl}(maxFee, upperHint, lowerHint);

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint ICR = bridge.troveManager().getCurrentICR(address(bridge), price);

        assertEq(ICR, 250 * 1e16);
        assertGt(IERC20(tokens["LUSD"].addr).balanceOf(address(this)), 1900 * WAD);
    }
}
