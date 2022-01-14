// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../StakingBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StakingBridgeTest is TestUtil {
    StakingBridge private bridge;

    function setUp() public {
        setUpTokens();
        address rollupProcessor = address(this);
        bridge = new StakingBridge(rollupProcessor);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StakingBridge");
        assertEq(bridge.symbol(), "SB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testFullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LQTY
        uint256 depositAmount = 10**6 * WAD;

        // 1. mint LQTY to this contract
        mint("LQTY", address(this), depositAmount);

        // 2. Allow StakingBridge to spend LQTY of this
        IERC20(tokens["LQTY"].addr).approve(address(bridge), depositAmount);

        // 3. Deposit LQTY to Staking through the bridge
        bridge.convert(
            Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 4. Check the total supply of SPB token is equal to the amount of LQTY deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 5. Check the SPB balance of this is equal to the amount of LQTY deposited
        assertEq(bridge.balanceOf(address(this)), depositAmount);

        // 6. Check the LQTY balance of StakingBridge in Staking is equal to the amount of LQTY deposited
        assertEq(bridge.lqtyBalance(), depositAmount);

        // 7. Withdraw LQTY from Staking through the bridge
        bridge.convert(
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 8. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 9. Check the LQTY balance of this contract is equal to the initial LQTY deposit
        assertEq(IERC20(tokens["LQTY"].addr).balanceOf(address(this)), depositAmount);
    }

    function test10DepositsWithdrawals() public {
        uint256 i = 0;
        uint256 depositAmount = 203;

        uint256 numIters = 10;
        uint256[] memory sbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. mint LQTY to this contract
            mint("LQTY", address(this), depositAmount);
            // 2. mint rewards to bridge
            mint("LUSD", address(bridge), 100 * WAD);
            mint("WETH", address(bridge), 1 * WAD);

            // 3. Allow StakingBridge to spend LQTY of this
            IERC20(tokens["LQTY"].addr).approve(address(bridge), depositAmount);

            // 4. Deposit LQTY to Staking through the bridge
            (uint256 outputValueA, , ) = bridge.convert(
                Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                depositAmount,
                0,
                0
            );

            sbBalances[i] = outputValueA;
            i++;
        }

        i = 0;
        while (i < numIters) {
            // 5. Withdraw LQTY from Staking through the bridge
            bridge.convert(
                Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                sbBalances[i],
                0,
                0
            );
            i++;
        }

        // 6. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
    }
}
