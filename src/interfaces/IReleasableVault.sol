// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title IReleasableVault — the common "release" surface every vault template implements.
/// @notice The Reactive callback contract only ever calls `release(id)`. Any vault that
///         (a) emits the shared `Deposited(uint256,address,uint256,uint256,uint256)` event
///         (goalId, depositor, amount, total, target) and
///         (b) implements this interface
///         can be plugged into the same GoalReactive + GoalCallback engine with no code
///         changes. This is the template pattern behind the dashboard's template list.
interface IReleasableVault {
    /// @notice Release the accumulated funds of entry `id` to its beneficiary.
    /// @dev Must be callable only by the vault's executor (the callback contract).
    function release(uint256 id) external;
}
