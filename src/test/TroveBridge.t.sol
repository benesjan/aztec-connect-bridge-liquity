// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../TroveBridge.sol";
import "../Types.sol";
import "../interfaces/ISortedTroves.sol";
import "./TestUtil.sol";
import "./interfaces/IHintHelpers.sol";

contract TroveBridgeTest is TestUtil {
    TroveBridge private bridge;
    IHintHelpers private constant hintHelpers = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    function setUp() public {
        setUpTokens();
        address payable rollupProcessor = payable(address(this));
        uint256 initialCollateralRatio = 250;
        uint256 maxFee = 5e16; // Slippage protection: 5%
        bridge = new TroveBridge(rollupProcessor, initialCollateralRatio, maxFee);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-250");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testOpenTrove() public {
        uint256 ethColl = 5 * WAD;
        (uint256 debtIncr, uint256 amtToBorrow) = bridge.computeDebitIncrAndAmtToBorrow(ethColl);
        uint256 NICR_PRECISION = 1e20;
        uint256 NICR = ethColl.mul(NICR_PRECISION).div(amtToBorrow);

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = hintHelpers.getApproxHint(NICR, numTrials, randomSeed);
        (address upperHint, address lowerHint) = sortedTroves.findInsertPosition(NICR, approxHint, approxHint);

        bridge.openTrove{value: ethColl}(upperHint, lowerHint);

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 ICR = bridge.troveManager().getCurrentICR(address(bridge), price);

        assertEq(ICR, 250e16);

        uint256 TBBalance = IERC20(address(bridge)).balanceOf(address(this));
        uint256 LUSDBalance = IERC20(tokens["LUSD"].addr).balanceOf(address(this));

        assertEq(TBBalance, debtIncr);
        assertEq(LUSDBalance, amtToBorrow);
    }
}
