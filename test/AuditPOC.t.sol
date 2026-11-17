// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";
import { GoalReactive } from "../src/reactive/GoalReactive.sol";
import { GoalCallback } from "../src/sepolia/GoalCallback.sol";
import { TemplateRegistry } from "../src/sepolia/TemplateRegistry.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";
import { RejectingReceiver, ReentrantReceiver } from "./mocks/AuditActors.sol";

/// @notice Proof-of-concept tests for the audit findings. Each test encodes the
///         CORRECT post-fix behaviour; several fail against the pre-fix code,
///         which is the point (run recorded in the audit notes).
contract AuditPOCTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant DEPOSITED_TOPIC0 =
        uint256(keccak256("Deposited(uint256,address,uint256,uint256,uint256)"));

    GoalVault internal vault;
    address internal alice = makeAddr("alice");
    address internal executor = makeAddr("executor");

    function setUp() public {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        vault = new GoalVault();
        vault.setExecutor(executor);
        vm.deal(alice, 10 ether);
    }

    // BUG-1 (critical): a beneficiary that cannot receive at callback time made
    // release() revert in full. Because the Reactive side is one-shot, the
    // callback would never be re-requested and the executor could never be
    // triggered again — funds locked forever. Correct behaviour: release()
    // succeeds, the payout is deferred to a pull balance, and the beneficiary
    // claims it later via withdraw().
    function test_PayoutFailure_DefersToPullBalance_NotLocked() public {
        RejectingReceiver ben = new RejectingReceiver(); // accepts == false
        vm.prank(alice);
        uint256 id = vault.createGoal(address(ben), 0.03 ether);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);

        vm.prank(executor);
        vault.release(id); // must NOT revert

        (,,,, bool completed) = vault.getGoal(id);
        assertTrue(completed, "goal must complete even if push payout fails");
        assertEq(vault.pendingWithdrawals(address(ben)), 0.03 ether);
        assertEq(address(vault).balance, 0.03 ether, "funds stay in vault as pull credit");

        ben.setAccepts(true);
        ben.withdrawFrom(vault);
        assertEq(address(ben).balance, 0.03 ether);
        assertEq(vault.pendingWithdrawals(address(ben)), 0);
    }

    // BUG-1b: reentrancy during payout must never pay twice.
    function test_PayoutReentrancy_PaysExactlyOnce() public {
        ReentrantReceiver ben = new ReentrantReceiver();
        vm.prank(alice);
        uint256 id = vault.createGoal(address(ben), 0.03 ether);
        ben.arm(vault, id);
        vm.prank(alice);
        vault.deposit{ value: 0.03 ether }(id);

        vm.prank(executor);
        vault.release(id);

        assertEq(ben.receiveCount(), 1);
        assertEq(ben.totalReceived(), 0.03 ether);
        assertEq(address(vault).balance, 0);
    }

    // BUG-2: GoalReactive constructor accepted a zero vault (subscription to
    // address(0), immutable — guaranteed-dead deployment) and chainId 0
    // (which in Reactive subscription semantics is the ANY-chain wildcard).
    function test_ReactiveConstructor_RejectsZeroVault() public {
        vm.expectRevert(GoalReactive.InvalidVault.selector);
        new GoalReactive(SEPOLIA, address(0), DEPOSITED_TOPIC0);
    }

    function test_ReactiveConstructor_RejectsZeroChainId() public {
        vm.expectRevert(GoalReactive.InvalidChainId.selector);
        new GoalReactive(0, makeAddr("vault"), DEPOSITED_TOPIC0);
    }

    function test_ReactiveConstructor_RejectsZeroTopic0() public {
        vm.expectRevert(GoalReactive.InvalidTopic0.selector);
        new GoalReactive(SEPOLIA, makeAddr("vault"), 0);
    }

    // BUG-3: GoalCallback accepted vault == address(0) — release() on an empty
    // account returns success while doing nothing, so callbacks would be
    // silently swallowed. It also accepted callbackSender == address(0),
    // which can never match the proxy-injected address (dead on arrival).
    function test_CallbackConstructor_RejectsZeroVault() public {
        vm.expectRevert(GoalCallback.InvalidVault.selector);
        new GoalCallback(IPayable(payable(makeAddr("proxy"))), makeAddr("reactive"), address(0));
    }

    function test_CallbackConstructor_RejectsZeroSender() public {
        vm.expectRevert(GoalCallback.InvalidCallbackSender.selector);
        new GoalCallback(IPayable(payable(makeAddr("proxy"))), address(0), address(vault));
    }

    function test_CallbackConstructor_RejectsZeroProxy() public {
        vm.expectRevert(GoalCallback.InvalidCallbackProxy.selector);
        new GoalCallback(IPayable(payable(address(0))), makeAddr("reactive"), address(vault));
    }

    // BUG-4: TemplateRegistry accepted a zero callback address.
    function test_Registry_RejectsZeroCallback() public {
        TemplateRegistry registry = new TemplateRegistry();
        vm.expectRevert(TemplateRegistry.InvalidCallback.selector);
        registry.registerTemplate("X", "x", makeAddr("vault"), address(0));
    }

    // BUG-5: TemplateRegistry.setTemplateActive on a nonexistent id panicked
    // (array out-of-bounds) instead of reverting with a named error.
    function test_Registry_SetActiveUnknownId_NamedRevert() public {
        TemplateRegistry registry = new TemplateRegistry();
        vm.expectRevert(abi.encodeWithSelector(TemplateRegistry.TemplateNotFound.selector, 7));
        registry.setTemplateActive(7, false);
    }
}
