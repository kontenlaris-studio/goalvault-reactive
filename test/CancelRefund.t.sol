// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";
import { EscrowVault } from "../src/sepolia/EscrowVault.sol";

/// @notice Upgrade B1 — creator cancel/refund for BOTH vault templates.
///         The accounting properties under test:
///           * only the creator can cancel, only before completion;
///           * every contributor is credited EXACTLY their own contributions;
///           * a cancel never touches another goal's funds (balance invariant);
///           * after cancel: no deposits, and release() reverts — so a callback
///             already in flight cannot also pay out (no double-spend).
contract CancelRefundTest is Test {
    GoalVault internal vault;
    EscrowVault internal escrow;
    address internal alice = makeAddr("alice"); // creator
    address internal bob = makeAddr("bob"); // second contributor
    address internal beneficiary = makeAddr("beneficiary");
    address internal freelancer = makeAddr("freelancer");
    address internal executor = makeAddr("executor");

    function setUp() public {
        vault = new GoalVault();
        vault.setExecutor(executor);
        escrow = new EscrowVault();
        escrow.setExecutor(executor);
        vm.deal(alice, 20 ether);
        vm.deal(bob, 20 ether);
    }

    function _fundedGoal() internal returns (uint256 id) {
        vm.prank(alice);
        id = vault.createGoal(beneficiary, 1 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.4 ether }(id);
        vm.prank(bob);
        vault.deposit{ value: 0.25 ether }(id);
    }

    // --- GoalVault ---

    function test_CancelGoal_CreditsEachContributorExactly() public {
        uint256 id = _fundedGoal();
        vm.prank(alice);
        vault.cancelGoal(id);

        assertEq(vault.pendingWithdrawals(alice), 0.4 ether);
        assertEq(vault.pendingWithdrawals(bob), 0.25 ether);
        assertEq(vault.contributions(id, alice), 0);
        assertEq(vault.contributions(id, bob), 0);
        (bool completed, bool cancelled) = vault.getGoalState(id);
        assertFalse(completed);
        assertTrue(cancelled);

        // bob claims his refund
        vm.prank(bob);
        vault.withdraw();
        assertEq(bob.balance, 20 ether); // started with 20, deposited .25, got .25 back
        vm.prank(alice);
        vault.withdraw();
        assertEq(alice.balance, 20 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_CancelGoal_DoesNotTouchOtherGoals() public {
        uint256 idA = _fundedGoal(); // 0.65 funded
        vm.prank(alice);
        uint256 idB = vault.createGoal(beneficiary, 0.5 ether);
        vm.prank(bob);
        vault.deposit{ value: 0.5 ether }(idB);

        vm.prank(alice);
        vault.cancelGoal(idA);

        // Goal B intact and still completable for its full amount.
        (,,, uint256 totalB, bool doneB) = vault.getGoal(idB);
        assertEq(totalB, 0.5 ether);
        assertFalse(doneB);
        uint256 before = beneficiary.balance;
        vm.prank(executor);
        vault.release(idB);
        assertEq(beneficiary.balance, before + 0.5 ether);
        // Vault still holds exactly goal A's refund credits.
        assertEq(address(vault).balance, 0.65 ether);
        assertEq(vault.pendingWithdrawals(alice) + vault.pendingWithdrawals(bob), 0.65 ether);
    }

    function test_CancelGoal_OnlyCreator() public {
        uint256 id = _fundedGoal();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.NotGoalOwner.selector, id));
        vault.cancelGoal(id);
    }

    function test_CancelGoal_AfterCompletionReverts() public {
        uint256 id = _fundedGoal();
        vm.prank(alice);
        vault.deposit{ value: 0.35 ether }(id); // reaches 1.0 target
        vm.prank(executor);
        vault.release(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCompleted.selector, id));
        vault.cancelGoal(id);
    }

    function test_CancelledGoal_NoDeposits_NoRelease_DoubleCancelReverts() public {
        uint256 id = _fundedGoal();
        vm.prank(alice);
        vault.cancelGoal(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCancelled.selector, id));
        vault.deposit{ value: 0.1 ether }(id);

        // The in-flight-callback case: release must refuse a cancelled goal.
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCancelled.selector, id));
        vault.release(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCancelled.selector, id));
        vault.cancelGoal(id);
    }

    function test_CancelGoal_CrossedTarget_RefundWinsOverInFlightCallback() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id); // target crossed; callback "in flight"
        vm.prank(alice);
        vault.cancelGoal(id); // still before completion: allowed
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCancelled.selector, id));
        vault.release(id);
        assertEq(beneficiary.balance, 0);
        assertEq(vault.pendingWithdrawals(alice), 0.03 ether);
    }

    function test_Withdraw_NothingToWithdrawReverts() public {
        vm.prank(alice);
        vm.expectRevert(GoalVault.NothingToWithdraw.selector);
        vault.withdraw();
    }

    // --- EscrowVault (mirror behaviour) ---

    function test_CancelEscrow_RefundsContributors_ReleaseBlocked() public {
        vm.prank(alice);
        uint256 id = escrow.createEscrow(freelancer, 1 ether);
        vm.prank(alice);
        escrow.deposit{ value: 0.7 ether }(id);
        vm.prank(bob);
        escrow.deposit{ value: 0.1 ether }(id);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.NotClient.selector, id));
        escrow.cancelEscrow(id);

        vm.prank(alice);
        escrow.cancelEscrow(id);
        assertEq(escrow.pendingWithdrawals(alice), 0.7 ether);
        assertEq(escrow.pendingWithdrawals(bob), 0.1 ether);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(EscrowVault.EscrowAlreadyCancelled.selector, id));
        escrow.release(id);
        assertEq(freelancer.balance, 0);
    }
}
