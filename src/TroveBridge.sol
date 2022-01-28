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
import "./interfaces/ISortedTroves.sol";

contract TroveBridge is IDefiBridge, ERC20, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    IBorrowerOperations public constant operations = IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant troveManager = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves public constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    address payable public immutable rollupProcessor;
    uint256 public immutable initialICR; // ICR is an acronym for individual collateral ratio
    uint256 public immutable maxFee;

    /**
     * @notice Set the address of RollupProcessor.sol and initial ICR
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _initialICRPerc Collateral ratio denominated in percents to be used when opening the Trove
     */
    constructor(
        address payable _rollupProcessor,
        uint256 _initialICRPerc,
        uint256 _maxFee
    ) public ERC20("TroveBridge", string(abi.encodePacked("TB-", _initialICRPerc.toString()))) {
        rollupProcessor = _rollupProcessor;
        initialICR = _initialICRPerc * 1e16;
        maxFee = _maxFee;
    }

    function openTrove(address _upperHint, address _lowerHint) external payable onlyOwner {
        // Note: I am not checking if the trove is already open because IBorrowerOperations.openTrove(...) checks it.
        (uint256 debtIncr, uint256 amtToBorrow) = computeDebitIncrAndAmtToBorrow(msg.value);
        operations.openTrove{value: msg.value}(maxFee, amtToBorrow, _upperHint, _lowerHint);
        IERC20(LUSD).transfer(msg.sender, IERC20(LUSD).balanceOf(address(this)));
        // I mint TB token to msg.sender to be able to track collateral ownership.
        _mint(msg.sender, debtIncr);
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
        // TODO: handle liquidations
        require(msg.sender == rollupProcessor, "TroveBridge: INVALID_CALLER");
        require(troveManager.getTroveStatus(address(this)) == 1, "TroveBridge: INACTIVE_TROVE");
        isAsync = false;

        address upperHint = sortedTroves.getPrev(address(this));
        address lowerHint = sortedTroves.getNext(address(this));

        if (inputAssetA.assetType == Types.AztecAssetType.ETH) {
            // Borrowing
            require(
                outputAssetA.erc20Address == address(this) && outputAssetB.erc20Address == LUSD,
                "TroveBridge: INCORRECT_BORROWING_INPUT"
            );
            // outputValueA = by how much debt will increase and how much TB to mint
            // outputValueB = LUSD amount to borrow
            (outputValueA, outputValueB) = computeDebitIncrAndAmtToBorrow(msg.value);
            operations.adjustTrove{value: inputValue}(maxFee, 0, outputValueA, true, upperHint, lowerHint);
            _mint(rollupProcessor, outputValueA);
            require(IERC20(LUSD).transfer(rollupProcessor, outputValueB), "TroveBridge: LUSD_TRANSFER_FAILED");
        } else {
            // Withdrawing
            require(
                inputAssetA.erc20Address == address(this) &&
                    inputAssetB.erc20Address == LUSD &&
                    outputAssetA.assetType == Types.AztecAssetType.ETH,
                "TroveBridge: INCORRECT_WITHDRAWING_INPUT"
            );
            (, uint256 coll, , ) = troveManager.getEntireDebtAndColl(address(this));
            outputValueA = coll.mul(inputValue).div(this.totalSupply()); // Amount of collateral to withdraw
            operations.adjustTrove(maxFee, outputValueA, inputValue, false, upperHint, lowerHint);
            _burn(address(this), inputValue);
            require(rollupProcessor.send(outputValueA), "TroveBridge: ETH_WITHDRAWAL_FAILED");
        }
    }

    function closeTrove() public onlyOwner {}

    /**
     * @notice Compute how much LUSD to borrow against collateral in order to keep ICR constant and by how much total
     * trove debt will increase.
     * @param _coll Amount of ETH denominated in Wei
     * @return debtIncr Amount of LUSD by which total trove debt will increase (amtToBorrow + gas compensation
     * @return amtToBorrow Amount of LUSD to borrow to keep ICR constant.
     * + borrowing fee)
     * @dev I don't use view modifier here because the function updates PriceFeed state.
     *
     * Since the Trove opening and adjustment processes have desired amount of LUSD to borrow on the input and not
     * the desired ICR I have to do the computation of borrowing fee "backwards". Here are the operations I did in order
     * to get the final formula:
     *      1) debtIncr = amtToBorrow + amtToBorrow * BORROWING_RATE / DECIMAL_PRECISION + 200LUSD
     *      2) debtIncr - 200LUSD = amtToBorrow * (1 + BORROWING_RATE / DECIMAL_PRECISION)
     *      3) amtToBorrow = (debtIncr - 200LUSD) / (1 + BORROWING_RATE / DECIMAL_PRECISION)
     *      4) amtToBorrow = (debtIncr - 200LUSD) * DECIMAL_PRECISION / (DECIMAL_PRECISION + BORROWING_RATE)
     * Note1: For trove adjustments (not opening) remove the 200 LUSD fee compensation from the formulas above.
     * Note2: Step 4 is necessary to avoid loss of precision. BORROWING_RATE / DECIMAL_PRECISION was rounded to 0.
     * Note3: The borrowing fee computation is on this line in Liquity code: https://github.com/liquity/dev/blob/cb583ddf5e7de6010e196cfe706bd0ca816ea40e/packages/contracts/contracts/TroveManager.sol#L1433
     */
    function computeDebitIncrAndAmtToBorrow(uint256 _coll) public returns (uint256 debtIncr, uint256 amtToBorrow) {
        uint256 price = troveManager.priceFeed().fetchPrice();
        bool isRecoveryMode = troveManager.checkRecoveryMode(price);
        if (troveManager.getTroveStatus(address(this)) == 1) {
            // Trove is active - use current ICR and not the initial one
            uint256 ICR = troveManager.getCurrentICR(address(this), price);
            debtIncr = _coll.mul(price).div(ICR);
            if (isRecoveryMode) {
                amtToBorrow = debtIncr;
            } else {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = troveManager.getBorrowingRateWithDecay();
                amtToBorrow = debtIncr.mul(1e18).div(borrowingRate.add(1e18));
            }
        } else {
            // Trove is inactive - I will use initial ICR to compute debt
            debtIncr = _coll.mul(price).div(initialICR);
            // 200e18 - 200 LUSD gas compensation to liquidators
            amtToBorrow = debtIncr.sub(200e18);
            if (!isRecoveryMode) {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = troveManager.getBorrowingRateWithDecay();
                amtToBorrow = amtToBorrow.mul(1e18).div(borrowingRate.add(1e18));
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
