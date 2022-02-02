// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

import "../../interfaces/IRollupProcessor.sol";

contract MockRollupProcessor is IRollupProcessor {
    function receiveEthFromBridge(uint256 interactionNonce) external payable override {}
}
