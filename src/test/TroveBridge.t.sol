// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../TroveBridge.sol";
import "../Types.sol";
import "../interfaces/ISortedTroves.sol";
import "./TestUtil.sol";
import "./interfaces/IHintHelpers.sol";
import "./mocks/MockRollupProcessor.sol";

contract TroveBridgeTest is TestUtil {
    address private rollupProcessor;
    TroveBridge private bridge;

    IHintHelpers private constant hintHelpers = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    address private constant OWNER = address(24);

    uint256 private constant OWNER_WEI_BALANCE = 5e18; // 5 ETH
    uint256 private constant ROLLUP_PROCESSOR_WEI_BALANCE = 1e18; // 1 ETH

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    function setUp() public {
        setUpTokens();
        uint256 initialCollateralRatio = 160;
        uint256 maxFee = 5e16; // Slippage protection: 5%

        rollupProcessor = address(new MockRollupProcessor());

        hevm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, initialCollateralRatio, maxFee);

        // Set OWNER's and ROLLUP_PROCESSOR's balances
        hevm.deal(OWNER, OWNER_WEI_BALANCE);
        hevm.deal(rollupProcessor, ROLLUP_PROCESSOR_WEI_BALANCE);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-160");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testFailIncorrectTroveState() public {
        // Set msg.sender to ROLLUP_PROCESSOR
        hevm.prank(rollupProcessor);

        // Borrow when trove was not opened - state 0
        bridge.convert(
            Types.AztecAsset(3, address(0), Types.AztecAssetType.ETH),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(1, LUSD_ADDR, Types.AztecAssetType.ERC20),
            ROLLUP_PROCESSOR_WEI_BALANCE,
            0,
            0
        );
    }

    function testFailIncorrectInput() public {
        // Set msg.sender to ROLLUP_PROCESSOR
        hevm.prank(rollupProcessor);

        // Borrow when trove was not opened - state 0
        bridge.convert(
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            0,
            0,
            0
        );
    }

    function _openTrove() private {
        // Set msg.sender to OWNER
        hevm.startPrank(OWNER);

        uint256 amtToBorrow = bridge.computeAmtToBorrow(OWNER_WEI_BALANCE);
        uint256 NICR_PRECISION = 1e20;
        uint256 NICR = OWNER_WEI_BALANCE.mul(NICR_PRECISION).div(amtToBorrow);

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = hintHelpers.getApproxHint(NICR, numTrials, randomSeed);
        (address upperHint, address lowerHint) = sortedTroves.findInsertPosition(NICR, approxHint, approxHint);

        // Open the trove
        bridge.openTrove{value: OWNER_WEI_BALANCE}(upperHint, lowerHint);

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 ICR = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Verify the ICR equals the one specified in the bridge constructor
        assertEq(ICR, 160e16);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the TB total supply equals totalDebt
        assertEq(IERC20(address(bridge)).totalSupply(), debtAfterBorrowing);
        // Check the trove's collateral equals deposit amount
        assertEq(collAfterBorrowing, OWNER_WEI_BALANCE);

        uint256 LUSDBalance = LUSD_TOKEN.balanceOf(OWNER);
        assertEq(LUSDBalance, amtToBorrow);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(LUSD_TOKEN.balanceOf(address(bridge)), 0);

        hevm.stopPrank();
    }

    function _borrow() private {
        // Set msg.sender to ROLLUP_PROCESSOR
        hevm.startPrank(rollupProcessor);

        // Send ROLLUP_PROCESSOR_WEI_BALANCE to the bridge contract
        require(address(bridge).send(ROLLUP_PROCESSOR_WEI_BALANCE), "TroveBridgeTest: ETH_TRANSFER_FAILED");

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 ICRBeforeBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(address(bridge));

        // Borrow against ROLLUP_PROCESSOR_WEI_BALANCE
        bridge.convert(
            Types.AztecAsset(3, address(0), Types.AztecAssetType.ETH),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(1, LUSD_ADDR, Types.AztecAssetType.ERC20),
            ROLLUP_PROCESSOR_WEI_BALANCE,
            0,
            0
        );

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the collateral increase equals ROLLUP_PROCESSOR_WEI_BALANCE
        assertEq(collAfterBorrowing.sub(collBeforeBorrowing), ROLLUP_PROCESSOR_WEI_BALANCE);

        uint256 ICRAfterBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Check the the ICR didn't change
        assertEq(ICRBeforeBorrowing, ICRAfterBorrowing);

        // Check the TB total supply equals totalDebt
        assertEq(IERC20(address(bridge)).totalSupply(), debtAfterBorrowing);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(LUSD_TOKEN.balanceOf(address(bridge)), 0);

        hevm.stopPrank();
    }

    function _repay() private {
        // Set msg.sender to ROLLUP_PROCESSOR
        hevm.startPrank(rollupProcessor);

        uint256 processorTBBalance = bridge.balanceOf(rollupProcessor);
        uint256 processorLUSDBalance = LUSD_TOKEN.balanceOf(rollupProcessor);

        uint256 borrowerFee = processorTBBalance.sub(processorLUSDBalance);
        // Mint the borrower fee to ROLLUP_PROCESSOR in order to have a big enough balance for repaying
        mint("LUSD", rollupProcessor, borrowerFee);

        // Transfer TB and LUSD to the bridge before repaying
        require(bridge.transfer(address(bridge), processorTBBalance), "TroveBridgeTest: TB_TRANSFER_FAILED");
        require(LUSD_TOKEN.transfer(address(bridge), processorTBBalance), "TroveBridgeTest: LUSD_TRANSFER_FAILED");

        bridge.convert(
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(1, LUSD_ADDR, Types.AztecAssetType.ERC20),
            Types.AztecAsset(3, address(0), Types.AztecAssetType.ETH),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            processorTBBalance,
            0,
            0
        );

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(LUSD_TOKEN.balanceOf(address(bridge)), 0);

        // I want to check whether withdrawn amount of ETH is the same as the ROLLUP_PROCESSOR_WEI_BALANCE.
        // There is some imprecision so the amount is allowed to be different by 1 wei.
        uint256 diffInETH = rollupProcessor.balance < ROLLUP_PROCESSOR_WEI_BALANCE
            ? ROLLUP_PROCESSOR_WEI_BALANCE.sub(rollupProcessor.balance)
            : rollupProcessor.balance.sub(ROLLUP_PROCESSOR_WEI_BALANCE);
        assertLe(diffInETH, 1);

        hevm.stopPrank();
    }

    function _closeTrove() private {
        // Set msg.sender to OWNER
        hevm.startPrank(OWNER);

        uint256 ownerTBBalance = bridge.balanceOf(OWNER);
        uint256 ownerLUSDBalance = LUSD_TOKEN.balanceOf(OWNER);

        uint256 borrowerFee = ownerTBBalance.sub(ownerLUSDBalance).sub(200e18);
        uint256 amountToRepay = ownerLUSDBalance.add(borrowerFee);

        mint("LUSD", OWNER, borrowerFee);
        LUSD_TOKEN.approve(address(bridge), amountToRepay);

        bridge.closeTrove();

        Status troveStatus = Status(bridge.troveManager().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(LUSD_TOKEN.balanceOf(address(bridge)), 0);

        // I want to check whether withdrawn amount of ETH is the same as the ROLLUP_PROCESSOR_WEI_BALANCE.
        // There is some imprecision so the amount is allowed to be different by 1 wei.
        uint256 diffInETH = OWNER.balance < OWNER_WEI_BALANCE
            ? OWNER_WEI_BALANCE.sub(OWNER.balance)
            : OWNER.balance.sub(OWNER_WEI_BALANCE);
        assertLe(diffInETH, 1);

        hevm.stopPrank();
    }

    function testFullFlow() public {
        // This is the only way how to make 1 part of test depend on another in DSTest because tests are otherwise ran
        // in parallel in different EVM instances. For this reason these parts of tests can't be evaluated individually
        // unless ran repeatedly.
        _openTrove();
        _borrow();
        _repay();
        _closeTrove();
    }

    function testLiquidationFlow() public {
        _openTrove();
        _borrow();

        // Drop price and liquidate the trove
        dropLiquityPriceByHalf();
        bridge.troveManager().liquidate(address(bridge));
        Status troveStatus = Status(bridge.troveManager().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByLiquidation);
        // TODO
    }

    function testRedeemFlow() public {
        _openTrove();
        _borrow();

        // Mint 40 million LUSD and redeem
        uint256 amountToRedeem = 4e25;
        mint("LUSD", address(this), amountToRedeem);

        bridge.troveManager().redeemCollateral(amountToRedeem, address(0), address(0), address(0), 0, 0, 5e16);
        Status troveStatus = Status(bridge.troveManager().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByRedemption);
        // TODO
    }

    // Here so that I can successfully liquidate a trove from within this contract.
    fallback() external payable {}
}
