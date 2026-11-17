// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";
import { GoalCallback } from "../src/sepolia/GoalCallback.sol";

contract GoalCallbackTest is Test {
    GoalVault internal vault;
    GoalCallback internal callback;
    address internal proxy = makeAddr("sepoliaCallbackProxy");
    address internal reactiveAddr = makeAddr("goalReactiveOnLasna");
    address internal alice = makeAddr("alice");
    address internal beneficiary = makeAddr("beneficiary");
    uint256 internal goalId;

    function setUp() public {
        vault = new GoalVault();
        callback = new GoalCallback(IPayable(payable(proxy)), reactiveAddr, address(vault));
        vault.setExecutor(address(callback));

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        goalId = vault.createGoal(beneficiary, 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(goalId);
    }

    function test_Callback_FromProxy_WithReactiveSender_ReleasesFunds() public {
        uint256 before = beneficiary.balance;
        vm.prank(proxy); // onlyServiceProvider: caller must be the callback proxy
        callback.onGoalReached(reactiveAddr, goalId);
        assertEq(beneficiary.balance, before + 0.03 ether);
        (,,,, bool completed) = vault.getGoal(goalId);
        assertTrue(completed);
    }

    function test_Callback_WrongInjectedSender_Reverts() public {
        address evil = makeAddr("evilReactive");
        vm.prank(proxy);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, evil, reactiveAddr)
        );
        callback.onGoalReached(evil, goalId);
    }

    function test_Callback_DirectCallWithoutProxy_Reverts() public {
        // Even with the correct reactive_ value, a direct call must fail:
        // without the proxy check, anyone could forge the injected sender.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, alice, proxy));
        callback.onGoalReached(reactiveAddr, goalId);
    }
}
