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

        // 1. Mint the deposit amount of LQTY to the bridge
        mint("LQTY", address(bridge), depositAmount);

        // 2. Deposit LQTY to the staking contract through the bridge
        bridge.convert(
            Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SB token is equal to the amount of LQTY deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 4. Check the SB balance of this is equal to the amount of LQTY deposited
        assertEq(bridge.balanceOf(address(this)), depositAmount);

        // 5. Check the LQTY balance of StakingBridge in the staking contract is equal to the amount of LQTY deposited
        assertEq(bridge.STAKING_CONTRACT().stakes(address(bridge)), depositAmount);

        // 6. withdrawAmount is equal to depositAmount because there were no rewards claimed -> LQTY/SB ratio stayed 1
        uint256 withdrawAmount = depositAmount;

        // 7. Transfer the withdraw amount of SB to the bridge
        require(bridge.transfer(address(bridge), withdrawAmount), "StakingBridgeTest: WITHDRAW_TRANSFER_FAILED");

        // 8. Withdraw LQTY from the staking contract through the bridge
        bridge.convert(
            Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 9. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 10. Check the LQTY balance of this contract is equal to the initial LQTY deposit
        assertEq(IERC20(tokens["LQTY"].addr).balanceOf(address(this)), depositAmount);
    }

    function test10DepositsWithdrawals() public {
        uint256 i = 0;
        uint256 numIters = 10;
        uint256 depositAmount = 203;
        uint256[] memory sbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. Mint deposit amount of LQTY to the bridge
            mint("LQTY", address(bridge), depositAmount);
            // 2. Mint rewards to the bridge
            mint("LUSD", address(bridge), 100 * WAD);
            mint("WETH", address(bridge), 1 * WAD);

            // 3. Deposit LQTY to the staking contract through the bridge
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
            uint256 withdrawAmount = sbBalances[i];
            // 4. Transfer the withdraw amount of SB to the bridge
            require(bridge.transfer(address(bridge), withdrawAmount), "StakingBridgeTest: WITHDRAW_TRANSFER_FAILED");

            // 5. Withdraw LQTY from Staking through the bridge
            bridge.convert(
                Types.AztecAsset(2, address(bridge), Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
                Types.AztecAsset(1, tokens["LQTY"].addr, Types.AztecAssetType.ERC20),
                Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
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
