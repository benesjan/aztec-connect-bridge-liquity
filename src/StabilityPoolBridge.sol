// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IDefiBridge.sol";
import "./Types.sol";

contract StabilityPoolBridge is IDefiBridge, ERC20 {
    using SafeMath for uint256;

    address public immutable rollupProcessor;
    IERC20 public immutable lusdToken;
    IStabilityPool public immutable stabilityPool;
    address public immutable frontEndTag; // see StabilityPool.sol for details

    constructor(address _rollupProcessor, address _lusdToken, address _stabilityPool, address _frontEndTag) public ERC20("StabilityPoolBridge", "SPB") {
        rollupProcessor = _rollupProcessor;
        lusdToken = IERC20(_lusdToken);
        stabilityPool = IStabilityPool(_stabilityPool);
        // Note: frontEndTag is set only once for msg.sender in StabilityPool.sol. Can be zero address.
        frontEndTag = _frontEndTag;

        // Note: StabilityPoolBridge never holds LUSD after an invocation of any of its functions.
        // For this reason the following is not a security risk and makes the convert() function more gas efficient.
        require(IERC20(_lusdToken).approve(_stabilityPool, type(uint256).max), "StabilityPoolBridge: APPROVE_FAILED");
    }

    /*
    * Deposit:
    * inputAssetA - LUSD
    * outputAssetA - StabilityPoolBridge ERC20

    * Withdrawal:
    * inputAssetA - StabilityPoolBridge ERC20
    * outputAssetA - LUSD
    * inputValue - the total amount of StabilityPoolBridge ERC20
    *
    * Note: The function will revert in case there are troves to be liquidated. I am not handling this scenario because
    * I expect the liquidation bots to be so fast that the scenario will never occur. Checking for it would only waste gas.
    * TODO: Is this ^ true even during deposit?
    */
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata outputAssetA,
        Types.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64
    )
    external
    payable
    override
    returns (
        uint256 outputValueA,
        uint256,
        bool isAsync
    ) {
        require(msg.sender == rollupProcessor, "StabilityPoolBridge: INVALID_CALLER");
        require(inputAssetA.erc20Address == address(lusdToken) || inputAssetA.erc20Address == address(this), "StabilityPoolBridge: INCORRECT_INPUT");

        if (inputAssetA.erc20Address == address(lusdToken)) {
            // Deposit
            require(lusdToken.transferFrom(rollupProcessor, address(stabilityPool), inputValue), "StabilityPoolBridge: DEPOSIT_TRANSFER_FAILED");
            // Rewards are claimed here.
            stabilityPool.provideToSP(inputValue, frontEndTag);
            _swapAndDepositRewards();
            uint totalLUSDOwnedBeforeDeposit = stabilityPool.getCompoundedLUSDDeposit(address(this)).sub(inputValue);
            // outputValueA = how much SPB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1.
                outputValueA = inputValue;
            } else {
                // this.totalSupply().div(totalLUSDOwnedBeforeDeposit) = how much SPB one LUSD is worth
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = this.totalSupply().mul(inputValue).div(totalLUSDOwnedBeforeDeposit);
            }
            _mint(rollupProcessor, outputValueA);
        } else {
            // Withdrawal
            // Rewards are claimed here.
            stabilityPool.withdrawFromSP(0);
            _swapAndDepositRewards();

            // stabilityPool.getCompoundedLUSDDeposit(address(this)).div(this.totalSupply()) = how much LUSD one SPB is worth
            // outputValueA = amount of LUSD to be withdrawn and sent to rollupProcessor
            uint outputValueA = stabilityPool.getCompoundedLUSDDeposit(address(this)).mul(inputValue).div(this.totalSupply());
            stabilityPool.withdrawFromSP(outputValueA);
            _burn(rollupProcessor, inputValue);
            require(lusdToken.transferFrom(address(stabilityPool), rollupProcessor, outputValueA), "StabilityPoolBridge: WITHDRAWAL_TRANSFER_FAILED");
        }

        return (outputValueA, 0, false);
    }

    /*
    * Swaps any ETH and LQTY currently held by the contract to LUSD and deposits LUSD to StabilityPool.sol.
    */
    function _swapAndDepositRewards() internal {
        // TODO
        uint lusdHeldByBridge = lusdToken.balanceOf(address(this));
        if (lusdHeldByBridge != 0) {
            stabilityPool.provideToSP(lusdHeldByBridge, frontEndTag);
        }
    }

    function canFinalise(
        uint256 /*interactionNonce*/
    ) external view override returns (bool) {
        return false;
    }

    function finalise(
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        uint256,
        uint64
    ) external payable override returns (uint256, uint256) {
        require(false);
    }
}