// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { GoalReactive } from "../src/reactive/GoalReactive.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

/// @notice Unit tests for GoalReactive.react() against a mock system contract etched
///         onto the real SYSTEM address (0x8888...8888).
///         The three behaviours the buildathon submission depends on:
///           1. below target  -> NO callback request
///           2. at/above target -> EXACTLY ONE callback request, correctly encoded
///           3. one-shot guard -> further deposits never request a second callback
contract GoalReactiveTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant DEPOSITED_TOPIC0 =
        uint256(keccak256("Deposited(uint256,address,uint256,uint256,uint256)"));

    MockSystemContract internal system; // interface onto the etched code at SYSTEM_ADDR
    GoalReactive internal reactive;
    address internal vault = makeAddr("vault");
    address internal callback = makeAddr("callback");
    address internal depositor = makeAddr("depositor");

    function setUp() public {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystemContract(payable(SYSTEM_ADDR));

        reactive = new GoalReactive(SEPOLIA, vault, DEPOSITED_TOPIC0);
        reactive.setRecipient(callback);
    }

    function _log(uint256 goalId, uint256 amount, uint256 total, uint256 target)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: vault,
            topic0: DEPOSITED_TOPIC0,
            topic1: goalId,
            topic2: uint256(uint160(depositor)),
            topic3: 0,
            data: abi.encode(amount, total, target),
            blockNumber: 1,
            opCode: 3,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR); // onlySystem: caller must be the system contract
        reactive.react(log_);
    }

    // --- Subscription ---

    function test_ConstructorSubscribesToVaultDeposited() public view {
        assertEq(system.subscriptionCount(), 1);
        (uint256 chainId, address contractAddress, uint256 topic0,,,, address subscriber) = system.subscriptions(0);
        assertEq(chainId, SEPOLIA);
        assertEq(contractAddress, vault);
        assertEq(topic0, DEPOSITED_TOPIC0);
        assertEq(subscriber, address(reactive));
    }

    // --- 1. Below target: no callback ---

    function test_BelowTarget_NoCallback() public {
        _react(_log(0, 0.01 ether, 0.01 ether, 0.03 ether));
        _react(_log(0, 0.01 ether, 0.02 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 0);
        assertFalse(reactive.callbackSent(0));
    }

    // --- 2. At target: exactly one, correctly-encoded callback ---

    function test_AtTarget_ExactlyOneCallback() public {
        vm.expectEmit(true, false, false, true, address(reactive));
        emit GoalReactive.GoalTargetHit(0, 0.03 ether, 0.03 ether);
        _react(_log(0, 0.02 ether, 0.03 ether, 0.03 ether));

        assertEq(system.callbackRequestCount(), 1);
        assertTrue(reactive.callbackSent(0));

        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload, address sender) =
            system.lastCallbackRequest();
        assertEq(chainId, SEPOLIA);
        assertEq(recipient, callback);
        assertEq(gasLimit, 1_000_000);
        assertEq(sender, address(reactive));
        // First payload arg MUST be address(0) — the proxy injects the reactive address.
        assertEq(payload, abi.encodeWithSignature("onGoalReached(address,uint256)", address(0), uint256(0)));
    }

    function test_AboveTarget_AlsoFires() public {
        _react(_log(7, 0.05 ether, 0.05 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 1);
        assertTrue(reactive.callbackSent(7));
    }

    // --- 3. One-shot guard ---

    function test_OneShotGuard_SecondDepositAboveTarget_NoSecondCallback() public {
        _react(_log(0, 0.03 ether, 0.03 ether, 0.03 ether));
        _react(_log(0, 0.01 ether, 0.04 ether, 0.03 ether));
        _react(_log(0, 0.01 ether, 0.05 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 1);
    }

    function test_DifferentGoals_FireIndependently() public {
        _react(_log(0, 0.03 ether, 0.03 ether, 0.03 ether));
        _react(_log(1, 0.02 ether, 0.02 ether, 0.02 ether));
        assertEq(system.callbackRequestCount(), 2);
    }

    // --- Silent filters: no revert, no callback ---

    function test_WrongTopic_IgnoredSilently() public {
        IReactive.LogRecord memory log_ = _log(0, 0.03 ether, 0.03 ether, 0.03 ether);
        log_.topic0 = uint256(keccak256("SomethingElse(uint256)"));
        _react(log_);
        assertEq(system.callbackRequestCount(), 0);
    }

    function test_WrongContract_IgnoredSilently() public {
        IReactive.LogRecord memory log_ = _log(0, 0.03 ether, 0.03 ether, 0.03 ether);
        log_.contractAddress = makeAddr("otherVault");
        _react(log_);
        assertEq(system.callbackRequestCount(), 0);
    }

    function test_ShortData_IgnoredSilently() public {
        IReactive.LogRecord memory log_ = _log(0, 0.03 ether, 0.03 ether, 0.03 ether);
        log_.data = abi.encode(uint256(1)); // truncated payload must not revert
        _react(log_);
        assertEq(system.callbackRequestCount(), 0);
    }

    // --- Guards ---

    function test_React_RevertsForNonSystemCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDR)
        );
        reactive.react(_log(0, 0.03 ether, 0.03 ether, 0.03 ether));
    }

    function test_NoRecipientYet_NoCallback_AndGuardNotConsumed() public {
        GoalReactive unwired = new GoalReactive(SEPOLIA, vault, DEPOSITED_TOPIC0);
        vm.prank(SYSTEM_ADDR);
        unwired.react(_log(0, 0.03 ether, 0.03 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 0);
        assertFalse(unwired.callbackSent(0)); // can still fire once wired
    }

    function test_SetRecipient_OnlyOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(GoalReactive.NotOwner.selector);
        reactive.setRecipient(makeAddr("newCallback"));
    }
}
