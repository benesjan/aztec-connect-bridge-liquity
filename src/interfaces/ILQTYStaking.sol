// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ILQTYStaking {
    // I included only functions relevant for the Aztec bridge

    function stakes(address _user) external view returns (uint);

    function stake(uint _LQTYamount) external;

    function unstake(uint _LQTYamount) external;

    function getPendingETHGain(address _user) external view returns (uint);

    function getPendingLUSDGain(address _user) external view returns (uint);
}
