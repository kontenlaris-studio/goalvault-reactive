// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";

contract GoalVaultTest is Test {
    GoalVault internal vault;
    address internal alice = makeAddr("alice");
    address internal beneficiary = makeAddr("beneficiary");
    address internal executor = makeAddr("executor");

    function setUp() public {
        vault = new GoalVault();
        vault.setExecutor(executor);
        vm.deal(alice, 10 ether);
    }

    function test_CreateGoal_StoresFields() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        assertEq(id, 0);
        (address goalOwner, address ben, uint256 target, uint256 total, bool completed) = vault.getGoal(id);
        assertEq(goalOwner, alice);
        assertEq(ben, beneficiary);
        assertEq(target, 0.03 ether);
        assertEq(total, 0);
        assertFalse(completed);
    }

    function test_CreateGoal_RejectsZeroTargetAndZeroBeneficiary() public {
        vm.expectRevert(GoalVault.InvalidTarget.selector);
        vault.createGoal(beneficiary, 0);
        vm.expectRevert(GoalVault.InvalidBeneficiary.selector);
        vault.createGoal(address(0), 1 ether);
    }

    function test_Deposit_AccumulatesAndEmitsFullEvent() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);

        vm.expectEmit(true, true, false, true, address(vault));
        emit GoalVault.Deposited(id, alice, 0.01 ether, 0.01 ether, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.01 ether }(id);

        vm.prank(alice);
        vault.deposit{ value: 0.02 ether }(id);
        (,,, uint256 total,) = vault.getGoal(id);
        assertEq(total, 0.03 ether);
        assertEq(address(vault).balance, 0.03 ether);
    }

    function test_Deposit_RejectsZeroAndUnknownGoal() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 1 ether);
        vm.prank(alice);
        vm.expectRevert(GoalVault.ZeroDeposit.selector);
        vault.deposit(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalNotFound.selector, 99));
        vault.deposit{ value: 0.1 ether }(99);
    }

    function test_Release_OnlyExecutor_PaysBeneficiary() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);

        uint256 before = beneficiary.balance;
        vm.prank(executor);
        vault.release(id);

        assertEq(beneficiary.balance, before + 0.03 ether);
        (,,,, bool completed) = vault.getGoal(id);
        assertTrue(completed);
    }

    function test_Release_RevertsForNonExecutor() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);
        vm.prank(alice);
        vm.expectRevert(GoalVault.NotExecutor.selector);
        vault.release(id);
    }

    function test_DoubleRelease_Reverts() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);
        vm.prank(executor);
        vault.release(id);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCompleted.selector, id));
        vault.release(id);
    }

    function test_DepositAfterCompletion_Reverts() public {
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);
        vm.prank(executor);
        vault.completeGoal(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GoalVault.GoalAlreadyCompleted.selector, id));
        vault.deposit{ value: 0.01 ether }(id);
    }

    function test_SetExecutor_OneTimeOnly() public {
        vm.expectRevert(GoalVault.ExecutorAlreadySet.selector);
        vault.setExecutor(makeAddr("second"));
    }
}
