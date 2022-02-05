// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.0 <=0.8.10;

interface IRollupProcessor {
    function receiveEthFromBridge(uint256 interactionNonce) external payable;
}
