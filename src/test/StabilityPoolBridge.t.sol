// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "../StabilityPoolBridge.sol";
import "../AztecTypes.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private bridge;

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        address rollupProcessor = address(this);
        address frontEndTag = address(0);

        bridge = new StabilityPoolBridge(rollupProcessor, frontEndTag);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StabilityPoolBridge");
        assertEq(bridge.symbol(), "SPB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testFullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 depositAmount = 1e24;

        // 1. Mint the deposit amount of LUSD to the bridge
        mint("LUSD", address(bridge), depositAmount);

        // 2. Deposit LUSD to the StabilityPool contract through the bridge
        bridge.convert(
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 4. Check the SPB balance of this is equal to the amount of LUSD deposited
        assertEq(bridge.balanceOf(address(this)), depositAmount);

        // 5. Check the LUSD balance of the StabilityPoolBridge in the StabilityPool contract is equal to the amount
        // of LUSD deposited
        assertEq(bridge.STABILITY_POOL().getCompoundedLUSDDeposit(address(bridge)), depositAmount);

        // 6. withdrawAmount is equal to depositAmount because there were no rewards claimed -> LUSD/SPB ratio stayed 1
        uint256 withdrawAmount = depositAmount;

        // 7. Transfer the withdraw amount of SPB to the bridge
        require(bridge.transfer(address(bridge), withdrawAmount), "StabilityPoolBridgeTest: WITHDRAW_TRANSFER_FAILED");

        // 8. Withdraw LUSD from StabilityPool through the bridge
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            withdrawAmount,
            0,
            0
        );

        // 9. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 10. Check the LUSD balance of this contract is equal to the initial LUSD deposit
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), depositAmount);
    }

    function test10DepositsWithdrawals() public {
        uint256 i = 0;
        uint256 numIters = 10;
        uint256 depositAmount = 203;
        uint256[] memory spbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. Mint deposit amount of LUSD to the bridge
            mint("LUSD", address(bridge), depositAmount);
            // 2. Mint rewards to the bridge
            mint("LQTY", address(bridge), 1e20);
            mint("WETH", address(bridge), 1e18);

            // 3. Deposit LUSD to StabilityPool through the bridge
            (uint256 outputValueA, , ) = bridge.convert(
                AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                depositAmount,
                0,
                0
            );

            spbBalances[i] = outputValueA;
            i++;
        }

        i = 0;
        while (i < numIters) {
            uint256 withdrawAmount = spbBalances[i];
            // 4. Transfer the withdraw amount of SPB to the bridge
            require(
                bridge.transfer(address(bridge), withdrawAmount),
                "StabilityPoolBridgeTest: WITHDRAW_TRANSFER_FAILED"
            );

            // 5. Withdraw LUSD from StabilityPool through the bridge
            bridge.convert(
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                withdrawAmount,
                0,
                0
            );
            i++;
        }

        // 6. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
    }
}
