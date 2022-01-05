// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;


import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IDefiBridge.sol";
import "./Types.sol";

contract LiquityStabilityPoolBridge is IDefiBridge {
    using SafeMath for uint256;

    address public immutable rollupProcessor;

    IStabilityPool stabilityPool;

    constructor(address _rollupProcessor, address _stabilityPool) public {
        rollupProcessor = _rollupProcessor;
        stabilityPool = IStabilityPool(_stabilityPool);
    }

    // Deposit:
    // inputAssetA - LUSD (during deposit)
    // outputAssetA - virtual asset representing the position
    // (Note: Liquity doesn't mint any token representing the position)

    // Withdrawal:
    // inputAssetA - virtual asset
    // outputAssetA - LUSD
    // outputAssetB - LQTY reward
    // Note: There is also ETH reward transferred during withdrawal.
    // Since only 2 output assets are allowed I will swap ETH for LUSD.
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata outputAssetA,
        Types.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData
    )
    external
    payable
    override
    returns (
        uint256 outputValueA,
        uint256 outputValueB,
        bool isAsync
    ) {
        // TODO
        // Based on the input/output assets determine whether the call is deposit or withdrawal
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