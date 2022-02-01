// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../TroveBridge.sol";
import "../Types.sol";
import "../interfaces/ISortedTroves.sol";
import "../interfaces/IRollupProcessor.sol";
import "./TestUtil.sol";
import "./interfaces/IHintHelpers.sol";

contract TroveBridgeTest is TestUtil, IRollupProcessor {
    TroveBridge private bridge;
    IHintHelpers private constant hintHelpers = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    function receiveEthFromBridge(uint256 interactionNonce) external payable override {}

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
        uint256 depositAmount = 5 * WAD;
        uint256 amtToBorrow = bridge.computeAmtToBorrow(depositAmount);
        uint256 NICR_PRECISION = 1e20;
        uint256 NICR = depositAmount.mul(NICR_PRECISION).div(amtToBorrow);

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = hintHelpers.getApproxHint(NICR, numTrials, randomSeed);
        (address upperHint, address lowerHint) = sortedTroves.findInsertPosition(NICR, approxHint, approxHint);

        // Open the trove
        bridge.openTrove{value: depositAmount}(upperHint, lowerHint);

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 ICR = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Verify the ICR equals the one specified in the bridge constructor
        assertEq(ICR, 250e16);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the TB total supply equals totalDebt
        assertEq(IERC20(address(bridge)).totalSupply(), debtAfterBorrowing);
        // Check the trove's collateral equals deposit amount
        assertEq(collAfterBorrowing, depositAmount);

        uint256 LUSDBalance = IERC20(tokens["LUSD"].addr).balanceOf(address(this));
        assertEq(LUSDBalance, amtToBorrow);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(bridge)), 0);
    }

    function testBorrowRepaymentFlow() public {
        // TODO: figure out how to make this test conditional on testOpenTrove without calling it directly
        testOpenTrove();

        // I will deposit and withdraw 1 ETH
        uint256 depositAmount = WAD;
        // Send depositAmount to the bridge contract
        require(address(bridge).send(depositAmount), "TroveBridgeTest: ETH_TRANSFER_FAILED");

        uint256 balanceTBBeforeBorrowing = bridge.balanceOf(address(this));

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 ICRBeforeBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(address(bridge));

        // Borrow against depositAmount
        bridge.convert(
            Types.AztecAsset(3, address(0), Types.AztecAssetType.ETH),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            depositAmount,
            0,
            0
        );

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the collateral increase equals depositAmount
        assertEq(collAfterBorrowing.sub(collBeforeBorrowing), depositAmount);

        uint256 ICRAfterBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Check the the ICR didn't change
        assertEq(ICRBeforeBorrowing, ICRAfterBorrowing);

        // Check the TB total supply equals totalDebt
        assertEq(IERC20(address(bridge)).totalSupply(), debtAfterBorrowing);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(bridge)), 0);

        uint256 changeInTB = bridge.balanceOf(address(this)).sub(balanceTBBeforeBorrowing);

        // Transfer TB and LUSD to the bridge before repaying
        require(bridge.transfer(address(bridge), changeInTB), "TroveBridgeTest: TB_TRANSFER_FAILED");
        require(
            IERC20(tokens["LUSD"].addr).transfer(address(bridge), changeInTB),
            "TroveBridgeTest: LUSD_TRANSFER_FAILED"
        );

        uint256 balanceETHBeforeRepaying = address(this).balance;

        bridge.convert(
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(3, address(0), Types.AztecAssetType.ETH),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            changeInTB,
            0,
            0
        );

        // I want to check whether withdrawn amount of ETH is the same as the depositAmount.
        // There is some imprecision so the amount is allowed to be different by 1 wei.
        uint256 changeInETH = address(this).balance.sub(balanceETHBeforeRepaying);
        uint256 diffInETH = changeInETH < depositAmount
            ? depositAmount.sub(changeInETH)
            : changeInETH.sub(depositAmount);
        assertLe(diffInETH, 1);
    }

    function testCloseTrove() public {
        // TODO: figure out how to make this test conditional on testBorrowRepaymentFlow without calling it directly
        testBorrowRepaymentFlow();

        (uint256 remainingDebt, , , ) = bridge.troveManager().getEntireDebtAndColl(address(bridge));
        uint256 amountToRepay = remainingDebt.sub(200e18);
        IERC20 lusdToken = IERC20(tokens["LUSD"].addr);
        uint256 amountToMint = amountToRepay.sub(lusdToken.balanceOf(address(this)));

        mint("LUSD", address(this), amountToMint);
        lusdToken.approve(address(bridge), amountToRepay);

        bridge.closeTrove();

        uint256 troveStatus = bridge.troveManager().getTroveStatus(address(bridge));
        assertEq(troveStatus, 2); // 2 equals closedByOwner status
    }
}
