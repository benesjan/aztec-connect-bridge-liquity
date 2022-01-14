// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../StabilityPoolBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private bridge;

    function setUp() public {
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
        uint256 depositAmount = 10**6 * WAD;

        // 1. mint LUSD to this contract
        mint("LUSD", address(this), depositAmount);

        // 2. Allow StabilityPoolBridge to spend LUSD of this
        IERC20(tokens["LUSD"].addr).approve(address(bridge), depositAmount);

        // 3. Deposit LUSD to StabilityPool through the bridge
        bridge.convert(
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 4. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 5. Check the SPB balance of this is equal to the amount of LUSD deposited
        assertEq(bridge.balanceOf(address(this)), depositAmount);

        // 6. Check the LUSD balance of StabilityPoolBridge in StabilityPool is equal to the amount of LUSD deposited
        assertEq(bridge.STABILITY_POOL().getCompoundedLUSDDeposit(address(bridge)), depositAmount);

        // 7. Withdraw LUSD from StabilityPool through the bridge
        bridge.convert(
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 8. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 9. Check the LUSD balance of this contract is equal to the initial LUSD deposit
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(this)), depositAmount);
    }

    function test10DepositsWithdrawals() public {
        uint256 i = 0;
        uint256 depositAmount = 203;

        uint256 numIters = 10;
        uint256[] memory spbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. mint LUSD to this contract
            mint("LUSD", address(this), depositAmount);
            // 2. mint rewards to bridge
            mint("LQTY", address(bridge), 100 * WAD);
            mint("WETH", address(bridge), 1 * WAD);

            // 3. Allow StabilityPoolBridge to spend LUSD of this
            IERC20(tokens["LUSD"].addr).approve(address(bridge), depositAmount);

            // 4. Deposit LUSD to StabilityPool through the bridge
            (uint256 spbBalance, uint256 _, bool __) = bridge.convert(
                Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                depositAmount,
                0,
                0
            );

            spbBalances[i] = spbBalance;
            i++;
        }

        i = 0;
        while (i < numIters) {
            // 5. Withdraw LUSD from StabilityPool through the bridge
            bridge.convert(
                Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                spbBalances[i],
                0,
                0
            );
            i++;
        }

        // 6. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
    }
}
