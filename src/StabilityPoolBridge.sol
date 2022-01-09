// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;


import "../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "./interfaces/IStabilityPool.sol";
import "./interfaces/IDefiBridge.sol";
import "./Types.sol";

contract StabilityPoolBridge is IDefiBridge {
    using SafeMath for uint256;

    address public immutable rollupProcessor;

    IStabilityPool stabilityPool;

    uint64 private lastRegisteredFrontendId;
    mapping(uint64 => address) public frontEndTags; // see StabilityPool.sol for details
    mapping(address => uint64) public frontEndIds;

    constructor(address _rollupProcessor, address _stabilityPool) public {
        rollupProcessor = _rollupProcessor;
        stabilityPool = IStabilityPool(_stabilityPool);
    }

    /* registerFrontEnd():
    * Registers front end address in frontEndTags mappings and generates a corresponding uint64 id.
    *
    * _frontEndTag - front end address (see StabilityPool.sol for details)
    */
    function registerFrontEnd(address _frontEndTag) external {
        require(frontEndIds[_frontEndTag] == 0, "StabilityPoolBridge: Tag already registered");

        uint64 id = lastRegisteredFrontendId + 1;
        // 18446744073709551615 equals to type(uint64).max
        require(id < 18446744073709551615, "StabilityPoolBridge: Max number of frontends registered");

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
    */
    function convert(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata outputAssetA,
        Types.AztecAsset calldata,
        uint256 inputValue,
        uint256 interactionNonce,
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