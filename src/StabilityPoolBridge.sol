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
    IStabilityPool stabilityPool;

    uint64 private lastRegisteredFrontendId;
    mapping(uint64 => address) public frontEndTags; // see StabilityPool.sol for details
    mapping(address => uint64) public frontEndIds;

    constructor(address _rollupProcessor, address _lusdToken, address _stabilityPool) public ERC20("StabilityPoolBridge", "SPB") {
        rollupProcessor = _rollupProcessor;
        lusdToken = IERC20(_lusdToken);
        stabilityPool = IStabilityPool(_stabilityPool);
    }

    /* registerFrontEnd():
    * Registers front end address in frontEndTags mappings and generates a corresponding uint64 id.
    *
    * _frontEndTag - front end address (see StabilityPool.sol for details)
    */
    function registerFrontEnd(address _frontEndTag) external {
        require(frontEndIds[_frontEndTag] == 0, "StabilityPoolBridge: TAG_ALREADY_REGISTERED");

        // 18446744073709551615 equals to type(uint64).max
        require(lastRegisteredFrontendId != 18446744073709551615, "StabilityPoolBridge: UINT64_OVERFLOW");
        uint64 id = lastRegisteredFrontendId + 1;

        frontEndTags[id] = _frontEndTag;
        frontEndIds[_frontEndTag] = id;
        lastRegisteredFrontendId = id;
    }

    /*
    * Deposit:
    * inputAssetA - LUSD
    * outputAssetA - StabilityPoolBridge ERC20
    * auxData - frontEndId

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
        uint64 auxData
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
            require(lusdToken.approve(address(stabilityPool), inputValue), "StabilityPoolBridge: APPROVE_FAILED");
            // Note: I am not checking whether the frontEndTag is non-zero because zero address is fine with StabilityPool.sol
            // Rewards are claimed here
            stabilityPool.provideToSP(inputValue, frontEndTags[auxData]);
            _swapRewardsToLUSD();
            uint totalLUSDOwned = lusdToken.balanceOf(address(this)).add(stabilityPool.getCompoundedLUSDDeposit(address(this)));
            uint totalLUSDOwnedBeforeDeposit = totalLUSDOwned.sub(inputValue);
            // outputValueA = how much SPB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1
                outputValueA = inputValue;
            } else {
                // this.totalSupply().div(totalLUSDOwnedBeforeDeposit) = how much one SPB is worth in terms of LUSD
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = this.totalSupply().mul(inputValue).div(totalLUSDOwnedBeforeDeposit);
            }
            _mint(rollupProcessor, outputValueA);
        } else {
            // Withdrawal
            // Rewards are claimed here
            stabilityPool.withdrawFromSP(inputValue);
            _swapRewardsToLUSD();

        }

        return (outputValueA, 0, false);
    }

    function _swapRewardsToLUSD() internal {
        // TODO
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