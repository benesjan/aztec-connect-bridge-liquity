// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../StabilityPoolBridge.sol";
import "../Types.sol";
import "./TestUtil.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private stabilityPoolBridge;

    function setUp() public {
        setUpTokens();

        address rollupProcessor = address(this);
        address stabilityPool = 0x66017D22b0f8556afDd19FC67041899Eb65a21bb;
        address frontEndTag = address(0);
        address uniRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        stabilityPoolBridge = new StabilityPoolBridge(rollupProcessor, stabilityPool, frontEndTag, uniRouter, tokens["LUSD"].addr, tokens["WETH"].addr, tokens["LQTY"].addr);
    }

    function test_initialERC20Params() public {
        assertEq(stabilityPoolBridge.name(), "StabilityPoolBridge");
        assertEq(stabilityPoolBridge.symbol(), "SPB");
        assertEq(uint256(stabilityPoolBridge.decimals()), 18);
    }

    function test_fullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LUSD
        uint depositAmount = 10 ** 6 * 10 ** 18;

        // 1. mint LUSD to this contract
        mint("LUSD", address(this), depositAmount);

        // 2. Allow StabilityPoolBridge to spend LUSD of this
        IERC20(tokens["LUSD"].addr).approve(address(stabilityPoolBridge), depositAmount);

        // 3. Deposit LUSD to StabilityPool through the bridge
        stabilityPoolBridge.convert(
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(2, address(stabilityPoolBridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 4. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(stabilityPoolBridge.totalSupply(), depositAmount);

        // 5. Check the SPB balance of this is equal to the amount of LUSD deposited
        assertEq(stabilityPoolBridge.balanceOf(address(this)), depositAmount);

        // 6. Check the LUSD balance of StabilityPoolBridge in StabilityPool is equal to the amount of LUSD deposited
        assertEq(stabilityPoolBridge.stabilityPool().getCompoundedLUSDDeposit(address(stabilityPoolBridge)), depositAmount);

        // 7. Withdraw LUSD from StabilityPool through the bridge
        stabilityPoolBridge.convert(
            Types.AztecAsset(2, address(stabilityPoolBridge), Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            Types.AztecAsset(1, tokens["LUSD"].addr, Types.AztecAssetType.ERC20),
            Types.AztecAsset(0, address(0), Types.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 8. Check the total supply of SPB token is 0
        assertEq(stabilityPoolBridge.totalSupply(), 0);

        // 9. Check the LUSD balance of this contract is equal to the initial LUSD deposit
        assertEq(IERC20(tokens["LUSD"].addr).balanceOf(address(this)), depositAmount);
    }
}
