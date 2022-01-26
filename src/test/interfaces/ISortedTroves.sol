// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ISortedTroves {
    function findInsertPosition(
        uint256 _ICR,
        address _prevId,
        address _nextId
    ) external view returns (address, address);
}
