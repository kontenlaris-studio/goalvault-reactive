// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IReleasableVault } from "../interfaces/IReleasableVault.sol";

/// @title GoalCallback — the destination receiver on Ethereum Sepolia.
/// @notice The Sepolia callback proxy delivers Reactive callbacks here. Authentication
///         is two-layered, always both:
///           1. `onlyServiceProvider` — msg.sender really is the callback proxy;
///           2. `onlyCallbackSender(reactive_)` — the address the proxy injected into
///              the payload really is our GoalReactive contract (immutable, set at
///              construction — getting it wrong means redeploying, by design).
///         On a valid callback it calls `release(goalId)` on the wired vault template;
///         the vault's executor must be this contract.
///
/// @dev Failure handling (audit-hardened): a REVERTING callback is still billed
///      in full by the proxy and repeated failures can push this contract into
///      debt — and debt halts ALL deliveries. So `onGoalReached` never lets a
///      vault-side failure revert the delivery: `release()` is attempted inside
///      try/catch and a failure is surfaced as a `CallbackFailed` event instead.
///      This is safe because release failures here are either impossible-by-
///      construction (unknown goal id — the reactive side only fires for real
///      vault events) or benign races (goal cancelled by its creator after the
///      target was crossed, or a duplicate delivery after a `retryCallback` —
///      the goal is already completed/refunded and must not be paid twice).
contract GoalCallback is AbstractCallback {
    address public owner;
    /// @notice The vault template this callback releases funds from (GoalVault or
    ///         EscrowVault). Set at construction; the owner may re-point it to a new
    ///         vault template instance without redeploying the reactive side.
    IReleasableVault public vault;

    event CallbackHandled(address indexed reactive, uint256 indexed goalId);
    event CallbackFailed(address indexed reactive, uint256 indexed goalId);
    event VaultSet(address indexed vault);

    error NotOwner();
    error InvalidVault();
    error InvalidCallbackSender();
    error InvalidCallbackProxy();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param callbackProxy_ Sepolia callback proxy: 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
    /// @param callbackSender_ The GoalReactive contract address on Lasna (immutable).
    /// @param vault_ The vault template instance on Sepolia.
    constructor(IPayable callbackProxy_, address callbackSender_, address vault_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        // Zero checks are load-bearing: a zero proxy or sender makes every
        // callback unauthorizable (dead on arrival), and a zero vault makes
        // release() a silent no-op call to an empty account — callbacks would
        // look delivered while nothing ever happens.
        if (address(callbackProxy_) == address(0)) revert InvalidCallbackProxy();
        if (callbackSender_ == address(0)) revert InvalidCallbackSender();
        if (vault_ == address(0)) revert InvalidVault();
        owner = msg.sender;
        vault = IReleasableVault(vault_);
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert InvalidVault();
        vault = IReleasableVault(vault_);
        emit VaultSet(vault_);
    }

    /// @notice Entry point for Reactive callbacks. The first parameter is injected by
    ///         the callback proxy (our reactive contract's address) — never trust it
    ///         without `onlyCallbackSender`, and never call this without the proxy.
    function onGoalReached(address reactive_, uint256 goalId)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        try vault.release(goalId) {
            emit CallbackHandled(reactive_, goalId); // forge-lint: disable-line(reentrancy-events) — reports the try/catch outcome; cannot be emitted before the call.
        } catch {
            // Absorbed on purpose — see the contract-level note on billing/debt.
            emit CallbackFailed(reactive_, goalId); // forge-lint: disable-line(reentrancy-events) — same as above.
        }
    }

    /// @notice Recover from debt on the callback-proxy side (debt halts delivery).
    function coverDebt() external {
        _coverDebt();
    }
}
