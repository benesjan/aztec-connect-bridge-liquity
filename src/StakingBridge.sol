// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IDefiBridge.sol";
import "./interfaces/IWETH.sol";
import "./Types.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/ILQTYStaking.sol";

contract StakingBridge is IDefiBridge, ERC20("StakingBridge", "SB") {
    using SafeMath for uint256;

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    ILQTYStaking public constant STAKING_CONTRACT = ILQTYStaking(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public lqtyBalance = 0;

    address public immutable rollupProcessor;
    address public immutable frontEndTag; // see StabilityPool.sol for details

    constructor(address _rollupProcessor, address _frontEndTag) public {
        rollupProcessor = _rollupProcessor;
        // Note: frontEndTag is set only once for msg.sender in StabilityPool.sol. Can be zero address.
        frontEndTag = _frontEndTag;

        // Note: StakingBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its
        // functions. For this reason the following is not a security risk and makes the convert() function more gas
        // efficient.
        require(
            IERC20(LQTY).approve(address(STAKING_CONTRACT), type(uint256).max),
            "StakingBridge: LQTY_APPROVE_FAILED"
        );
        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: WETH_APPROVE_FAILED");
        require(IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: LUSD_APPROVE_FAILED");
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: USDC_APPROVE_FAILED");
    }

    /*
    * Deposit:
    * inputAssetA - LQTY
    * outputAssetA - StakingBridge ERC20
    * inputValue - the amount of LQTY to deposit

    * Withdrawal:
    * inputAssetA - StakingBridge ERC20
    * outputAssetA - LQTY
    * inputValue - the amount of StakingBridge ERC20
    */
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
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
        )
    {
        require(msg.sender == rollupProcessor, "StakingBridge: INVALID_CALLER");
        require(
            inputAssetA.erc20Address == LQTY || inputAssetA.erc20Address == address(this),
            "StakingBridge: INCORRECT_INPUT"
        );

        if (inputAssetA.erc20Address == LQTY) {
            // Deposit
            require(
                IERC20(LQTY).transferFrom(rollupProcessor, address(this), inputValue),
                "StakingBridge: DEPOSIT_TRANSFER_FAILED"
            );
            // Claim rewards
            STAKING_CONTRACT.unstake(0);
            uint256 rewardInLQTY = _swapRewardsToLQTY();
            uint256 totalLQTYOwnedBeforeDeposit = lqtyBalance.add(rewardInLQTY);
            // outputValueA = how much SB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SB/LQTY ratio to be 1.
                outputValueA = inputValue;
            } else {
                // this.totalSupply().div(totalLQTYOwnedBeforeDeposit) = how much SB one LQTY is worth
                // When I multiply this ^ with the amount of LQTY deposited I get the amount of SB to be minted.
                outputValueA = this.totalSupply().mul(inputValue).div(totalLQTYOwnedBeforeDeposit);
            }
            uint256 depositAmount = inputValue.add(rewardInLQTY);
            STAKING_CONTRACT.stake(depositAmount);
            _mint(rollupProcessor, outputValueA);
            lqtyBalance = lqtyBalance.add(depositAmount);
        } else {
            // Withdrawal
            // Claim rewards
            STAKING_CONTRACT.unstake(0);
            uint256 rewardInLQTY = _swapRewardsToLQTY();
            if (rewardInLQTY != 0) {
                // Stake the reward
                STAKING_CONTRACT.stake(rewardInLQTY);
                lqtyBalance = lqtyBalance.add(rewardInLQTY);
            }

            // lqtyBalance.div(this.totalSupply()) = how much LQTY is one SB
            // outputValueA = amount of LQTY to be withdrawn and sent to rollupProcessor
            outputValueA = lqtyBalance.mul(inputValue).div(this.totalSupply());
            STAKING_CONTRACT.unstake(outputValueA);
            _burn(rollupProcessor, inputValue);
            require(IERC20(LQTY).transfer(rollupProcessor, outputValueA), "StakingBridge: WITHDRAWAL_TRANSFER_FAILED");
        }

        return (outputValueA, 0, false);
    }

    /*
     * Swaps any ETH and LUSD currently held by the contract to LQTY.
     */
    function _swapRewardsToLQTY() internal returns (uint256 amountLQTYOut) {
        // Note: The best route for LUSD -> LQTY is consistently LUSD -> USDC -> WETH -> LQTY. Since I want to swap
        // liquidation rewards (ETH) to LQTY as well, I will first swap LUSD to WETH through USDC and then swap it all
        // to LQTY
        amountLQTYOut = 0;

        uint256 lusdBalance = IERC20(LUSD).balanceOf(address(this));
        if (lusdBalance != 0) {
            uint256 usdcBalance = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(LUSD, USDC, 500, address(this), block.timestamp, lusdBalance, 0, 0)
            );
            UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(USDC, WETH, 500, address(this), block.timestamp, usdcBalance, 0, 0)
            );
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance != 0) {
            amountLQTYOut = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(WETH, LQTY, 3000, address(this), block.timestamp, wethBalance, 0, 0)
            );
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
        require(false, "StakingBridge: ASYNC_MODE_DISABLED");
    }
}
