// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { GoalVault } from "../../src/sepolia/GoalVault.sol";

/// @notice Beneficiary that rejects ETH until told otherwise — models a contract
///         wallet / multisig whose receive() is temporarily (or permanently)
///         unavailable at the moment the Reactive callback fires.
contract RejectingReceiver {
    bool public accepts;

    function setAccepts(bool v) external {
        accepts = v;
    }

    function withdrawFrom(GoalVault vault) external {
        vault.withdraw();
    }

    receive() external payable {
        if (!accepts) revert("not accepting");
    }
}

/// @notice Beneficiary that tries to reenter the vault during its payout:
///         release() again, deposit(), and withdraw(). A correct vault pays
///         exactly the goal total, exactly once.
contract ReentrantReceiver {
    GoalVault public vault;
    uint256 public goalId;
    uint256 public receiveCount;
    uint256 public totalReceived;

    function arm(GoalVault vault_, uint256 goalId_) external {
        vault = vault_;
        goalId = goalId_;
    }

    function withdrawFrom() external {
        vault.withdraw();
    }

    receive() external payable {
        receiveCount++;
        totalReceived += msg.value;
        // Reentry attempts — all must fail or be harmless; none may pay twice.
        try vault.release(goalId) { } catch { }
        try vault.completeGoal(goalId) { } catch { }
        try vault.withdraw() { } catch { }
    }
}

/// @notice A vault whose release() always reverts — used to prove GoalCallback
///         absorbs destination failures instead of reverting the callback
///         delivery itself (a reverting callback is still billed and can push
///         the callback contract into debt, halting all future deliveries).
contract RevertingVault {
    function release(uint256) external pure {
        revert("vault boom");
    }
}
