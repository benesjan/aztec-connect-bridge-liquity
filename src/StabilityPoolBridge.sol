// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IDefiBridge.sol";
import "./Types.sol";
import "./interfaces/ISwapRouter.sol";

contract StabilityPoolBridge is IDefiBridge, ERC20("StabilityPoolBridge", "SPB") {
    using SafeMath for uint256;

    address public immutable rollupProcessorAddr;
    IStabilityPool public immutable stabilityPool;
    address public immutable frontEndTag; // see StabilityPool.sol for details
    ISwapRouter public immutable uniRouter;
    IERC20 public immutable lusd;
    IERC20 public immutable weth;
    IERC20 public immutable lqty;

    constructor(
        address _rollupProcessor,
        address _stabilityPool,
        address _frontEndTag,
        address _uniRouter,
        address _lusd,
        address _weth,
        address _lqty
    ) public {
        rollupProcessorAddr = _rollupProcessor;
        stabilityPool = IStabilityPool(_stabilityPool);
        // Note: frontEndTag is set only once for msg.sender in StabilityPool.sol. Can be zero address.
        frontEndTag = _frontEndTag;
        uniRouter = ISwapRouter(_uniRouter);
        lusd = IERC20(_lusd);
        weth = IERC20(_weth);
        lqty = IERC20(_lqty);

        // Note: StabilityPoolBridge never holds LUSD or LQTY after or before an invocation of any of its functions.
        // For this reason the following is not a security risk and makes the convert() function more gas efficient.
        require(IERC20(_lusd).approve(_stabilityPool, type(uint256).max), "StabilityPoolBridge: LUSD_APPROVE_FAILED");
        require(IERC20(_lqty).approve(_uniRouter, type(uint256).max), "StabilityPoolBridge: LQTY_APPROVE_FAILED");
    }

    /*
    * Deposit:
    * inputAssetA - LUSD
    * outputAssetA - StabilityPoolBridge ERC20
    * inputValue - the amount of LUSD to deposit
    * auxData - id of DEX used to swap rewards (0 - Uniswap, 1 - 1inch)

    * Withdrawal:
    * inputAssetA - StabilityPoolBridge ERC20
    * outputAssetA - LUSD
    * inputValue - the amount of StabilityPoolBridge ERC20
    * auxData - id of DEX used to swap rewards (0 - Uniswap, 1 - 1inch)
    *
    * Note: The function will revert during withdrawal in case there are troves to be liquidated. I am not handling
    * this scenario because I expect the liquidation bots to be so fast that the scenario will never occur. Checking
    * for it would only waste gas.
    */
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64 auxData
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        require(msg.sender == rollupProcessorAddr, "StabilityPoolBridge: INVALID_CALLER");
        require(
            inputAssetA.erc20Address == address(lusd) || inputAssetA.erc20Address == address(this),
            "StabilityPoolBridge: INCORRECT_INPUT"
        );

        if (inputAssetA.erc20Address == address(lusd)) {
            // Deposit
            require(
                lusd.transferFrom(rollupProcessorAddr, address(this), inputValue),
                "StabilityPoolBridge: DEPOSIT_TRANSFER_FAILED"
            );
            // Rewards are claimed here.
            stabilityPool.provideToSP(inputValue, frontEndTag);
            _swapAndDepositRewards(auxData);
            uint256 totalLUSDOwnedBeforeDeposit = stabilityPool.getCompoundedLUSDDeposit(address(this)).sub(inputValue);
            // outputValueA = how much SPB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1.
                outputValueA = inputValue;
            } else {
                // this.totalSupply().div(totalLUSDOwnedBeforeDeposit) = how much SPB one LUSD is worth
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = this.totalSupply().mul(inputValue).div(totalLUSDOwnedBeforeDeposit);
            }
            _mint(rollupProcessorAddr, outputValueA);
        } else {
            // Withdrawal
            // Rewards are claimed here.
            stabilityPool.withdrawFromSP(0);
            _swapAndDepositRewards(auxData);

            // stabilityPool.getCompoundedLUSDDeposit(address(this)).div(this.totalSupply()) = how much LUSD is one SPB
            // outputValueA = amount of LUSD to be withdrawn and sent to rollupProcessor
            outputValueA = stabilityPool.getCompoundedLUSDDeposit(address(this)).mul(inputValue).div(
                this.totalSupply()
            );
            stabilityPool.withdrawFromSP(outputValueA);
            _burn(rollupProcessorAddr, inputValue);
            require(
                lusd.transfer(rollupProcessorAddr, outputValueA),
                "StabilityPoolBridge: WITHDRAWAL_TRANSFER_FAILED"
            );
        }

        return (outputValueA, 0, false);
    }

    /*
     * Swaps any ETH and LQTY currently held by the contract to LUSD and deposits LUSD to StabilityPool.sol.
     */
    function _swapAndDepositRewards(uint64 dexId) internal {
        if (dexId == 0) {
            _swapRewardsOnUni();
        } else {
            _swapRewardsOn1inch();
        }
        uint256 lusdHeldByBridge = lusd.balanceOf(address(this));
        if (lusdHeldByBridge != 0) {
            stabilityPool.provideToSP(lusdHeldByBridge, frontEndTag);
        }
    }

    function _swapRewardsOnUni() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            uniRouter.exactInputSingle{value: ethBalance}(
                ISwapRouter.ExactInputSingleParams(
                    address(weth),
                    address(lusd),
                    3000,
                    address(this),
                    block.timestamp,
                    ethBalance,
                    0,
                    0
                )
            );
        }

        uint256 lqtyBalance = lqty.balanceOf(address(this));
        if (lqtyBalance != 0) {
            uniRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(
                    address(lqty),
                    address(lusd),
                    3000,
                    address(this),
                    block.timestamp,
                    lqtyBalance,
                    0,
                    0
                )
            );
        }
    }

    function _swapRewardsOn1inch() internal {
        if (address(this).balance != 0) {}
        if (lqty.balanceOf(address(this)) != 0) {}
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
        require(false, "StabilityPoolBridge: ASYNC_MODE_DISABLED");
    }
}
