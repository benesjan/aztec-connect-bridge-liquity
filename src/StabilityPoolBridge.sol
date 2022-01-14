// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IDefiBridge.sol";
import "./interfaces/IWETH.sol";
import "./Types.sol";
import "./interfaces/ISwapRouter.sol";

contract StabilityPoolBridge is IDefiBridge, ERC20("StabilityPoolBridge", "SPB") {
    using SafeMath for uint256;

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    IStabilityPool public constant STABILITY_POOL = IStabilityPool(0x66017D22b0f8556afDd19FC67041899Eb65a21bb);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public immutable rollupProcessor;
    address public immutable frontEndTag; // see StabilityPool.sol for details

    constructor(address _rollupProcessor, address _frontEndTag) public {
        rollupProcessor = _rollupProcessor;
        // Note: frontEndTag is set only once for msg.sender in StabilityPool.sol. Can be zero address.
        frontEndTag = _frontEndTag;

        // Note: StabilityPoolBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its
        // functions. For this reason the following is not a security risk and makes the convert() function more gas
        // efficient.
        require(
            IERC20(LUSD).approve(address(STABILITY_POOL), type(uint256).max),
            "StabilityPoolBridge: LUSD_APPROVE_FAILED"
        );
        require(
            IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: WETH_APPROVE_FAILED"
        );
        require(
            IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: LQTY_APPROVE_FAILED"
        );
        require(
            IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: USDC_APPROVE_FAILED"
        );
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
        require(msg.sender == rollupProcessor, "StabilityPoolBridge: INVALID_CALLER");
        require(
            inputAssetA.erc20Address == LUSD || inputAssetA.erc20Address == address(this),
            "StabilityPoolBridge: INCORRECT_INPUT"
        );

        if (inputAssetA.erc20Address == LUSD) {
            // Deposit
            require(
                IERC20(LUSD).transferFrom(rollupProcessor, address(this), inputValue),
                "StabilityPoolBridge: DEPOSIT_TRANSFER_FAILED"
            );
            // Rewards are claimed here.
            STABILITY_POOL.provideToSP(inputValue, frontEndTag);
            _swapAndDepositRewards(auxData);
            uint256 totalLUSDOwnedBeforeDeposit = STABILITY_POOL.getCompoundedLUSDDeposit(address(this)).sub(
                inputValue
            );
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
            STABILITY_POOL.withdrawFromSP(0);
            _swapAndDepositRewards(auxData);

            // stabilityPool.getCompoundedLUSDDeposit(address(this)).div(this.totalSupply()) = how much LUSD is one SPB
            // outputValueA = amount of LUSD to be withdrawn and sent to rollupProcessor
            outputValueA = STABILITY_POOL.getCompoundedLUSDDeposit(address(this)).mul(inputValue).div(
                this.totalSupply()
            );
            STABILITY_POOL.withdrawFromSP(outputValueA);
            _burn(rollupProcessor, inputValue);
            require(
                IERC20(LUSD).transfer(rollupProcessor, outputValueA),
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
        uint256 lusdBalance = IERC20(LUSD).balanceOf(address(this));
        if (lusdBalance != 0) {
            STABILITY_POOL.provideToSP(lusdBalance, frontEndTag);
        }
    }

    function _swapRewardsOnUni() internal {
        // Note: The best route for LQTY -> LUSD is consistently LQTY -> WETH -> USDC -> LUSD. Since I want to swap
        // liquidations rewards (ETH) to LUSD as well, I will first swap LQTY to WETH and then swap it all through
        // USDC to LUSD

        uint256 lqtyBalance = IERC20(LQTY).balanceOf(address(this));
        if (lqtyBalance != 0) {
            UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(LQTY, WETH, 3000, address(this), block.timestamp, lqtyBalance, 0, 0)
            );
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance != 0) {
            uint256 usdcBalance = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(WETH, USDC, 500, address(this), block.timestamp, wethBalance, 0, 0)
            );
            UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(USDC, LUSD, 500, address(this), block.timestamp, usdcBalance, 0, 0)
            );
        }
    }

    function _swapRewardsOn1inch() internal {
        require(false, "StabilityPoolBridge: NOT_IMPLEMENTED");
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
