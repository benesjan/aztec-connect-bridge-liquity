// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import "./Types.sol";
import "./interfaces/IDefiBridge.sol";
import "./interfaces/IBorrowerOperations.sol";
import "./interfaces/ITroveManager.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract TroveBridge is IDefiBridge, ERC20, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    IBorrowerOperations public constant operations = IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant troveManager = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);

    address public immutable rollupProcessor;
    uint256 public immutable initialICR; // ICR is an acronym for individual collateral ratio

    /**
     * @notice Set the address of RollupProcessor.sol and initial ICR
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _initialICRPerc Collateral ratio denominated in percents to be used when opening the Trove
     */
    constructor(address _rollupProcessor, uint256 _initialICRPerc)
        public
        ERC20("TroveBridge", string(abi.encodePacked("TB-", _initialICRPerc.toString())))
    {
        rollupProcessor = _rollupProcessor;
        initialICR = _initialICRPerc * 10**16;
    }

    function openTrove(
        uint256 _maxFee,
        address _upperHint,
        address _lowerHint
    ) external payable onlyOwner {
        // Note: I am not checking if the trove is already open because IBorrowerOperations.openTrove(...) checks it
        // I will compute LUSD amount borrowed based on initialICR (has to stay constant) and msg.value
        uint256 _LUSDAmount = computeLUSDToBorrow(msg.value);
        operations.openTrove{value: msg.value}(_maxFee, _LUSDAmount, _upperHint, _lowerHint);
        IERC20(LUSD).transfer(msg.sender, IERC20(LUSD).balanceOf(address(this)));
    }

    /**
     * @notice Function which stakes or unstakes LQTY to/from LQTYStaking.sol.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is ETH, borrowing flow is
     * executed. If TB, repaying. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert.
     *
     * @param inputAssetA - ETH (Borrowing) or TB (Repaying)
     * @param inputAssetB - None (Borrowing) or LUSD (Repaying)
     * @param outputAssetA - TB (Borrowing) or ETH (Repaying)
     * @param outputAssetB - LUSD (Borrowing) or None (Repaying)
     * @param inputValue - the amount of ETH to borrow against (Borrowing) or the amount of TB to burn and LUSD debt to
     * repay (Repaying)
     * @return outputValueA - the amount of TB (Borrowing) or ETH (Repaying) minted/transferred to
     * the RollupProcessor.sol
     * @return outputValueB - the amount of LUSD (Borrowing) transferred to the the RollupProcessor.sol (0 when
     * repaying)
     */
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata inputAssetB,
        Types.AztecAsset calldata outputAssetA,
        Types.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256,
        uint64
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        require(msg.sender == rollupProcessor, "TroveBridge: INVALID_CALLER");
        require(troveManager.getTroveStatus(address(this)) == 1, "TroveBridge: INACTIVE_TROVE");
        require(
            (inputAssetA.assetType == Types.AztecAssetType.ETH &&
                outputAssetA.erc20Address == address(this) &&
                outputAssetB.erc20Address == LUSD) ||
                (inputAssetA.erc20Address == address(this) &&
                    inputAssetB.erc20Address == LUSD &&
                    outputAssetA.assetType == Types.AztecAssetType.ETH),
            "TroveBridge: INCORRECT_INPUT"
        );
    }

    function closeTrove() public onlyOwner {}

    /**
     * @notice Compute how much LUSD to borrow against collateral in order to keep ICR constant.
     * @param _coll Amount of ETH denominated in Wei
     * @dev I don't use view modifier here because the function updates PriceFeed state.
     */
    function computeLUSDToBorrow(uint256 _coll) public returns (uint256 debt) {
        uint256 price = troveManager.priceFeed().fetchPrice();
        bool isRecoveryMode = troveManager.checkRecoveryMode(price);
        if (troveManager.getTroveStatus(address(this)) == 1) {
            // Trove is active - use current ICR and not the initial one
            uint256 ICR = troveManager.getCurrentICR(address(this), price);
            debt = _coll.mul(price).div(ICR);
            if (!isRecoveryMode) {
                // borrowing fee
                // TODO
            }
        } else {
            // Trove is inactive - I will use initial ICR to compute debt
            // 200e18 - 200 LUSD gas compensation (compensation to liquidators)
            debt = _coll.mul(price).div(initialICR) - 200e18;
            if (!isRecoveryMode) {
                // borrowing fee
                uint256 borrowingRate = troveManager.getBorrowingRate();
                debt = debt.div(1 + borrowingRate.div(1e18));
            }
        }
    }

    // @return Always false because this contract does not implement async flow.
    function canFinalise(
        uint256 /*interactionNonce*/
    ) external view override returns (bool) {
        return false;
    }

    // @notice This function always reverts because this contract does not implement async flow.
    function finalise(
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata,
        uint256,
        uint64
    ) external payable override returns (uint256, uint256) {
        require(false, "TroveBridge: ASYNC_MODE_DISABLED");
    }

    receive() external payable {}

    fallback() external payable {}
}
