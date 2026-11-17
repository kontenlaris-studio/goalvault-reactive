// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { GoalReactive } from "../src/reactive/GoalReactive.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

/// @notice Upgrade B2 — GoalReactive lifecycle: owner pause/resume of the
///         subscription, and owner retry of a lost callback delivery.
contract ReactiveLifecycleTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant DEPOSITED_TOPIC0 =
        uint256(keccak256("Deposited(uint256,address,uint256,uint256,uint256)"));

    MockSystemContract internal system;
    GoalReactive internal reactive;
    address internal vault = makeAddr("vault");
    address internal callback = makeAddr("callback");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystemContract(payable(SYSTEM_ADDR));
        reactive = new GoalReactive(SEPOLIA, vault, DEPOSITED_TOPIC0);
        reactive.setRecipient(callback);
    }

    function _log(uint256 goalId, uint256 total, uint256 target) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: vault,
            topic0: DEPOSITED_TOPIC0,
            topic1: goalId,
            topic2: 0,
            topic3: 0,
            data: abi.encode(total, total, target),
            blockNumber: 1,
            opCode: 3,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
    }

    // --- pause / resume ---

    function test_Pause_UnsubscribesWithExactCriteria_AndBlocksReact() public {
        reactive.pause();
        assertTrue(reactive.paused());
        assertEq(system.unsubscriptionCount(), 1);
        (uint256 chainId, address contractAddress, uint256 topic0, uint256 t1, uint256 t2, uint256 t3, address sub) =
            system.unsubscriptions(0);
        assertEq(chainId, SEPOLIA);
        assertEq(contractAddress, vault);
        assertEq(topic0, DEPOSITED_TOPIC0);
        // Wildcards must match the constructor's subscribe exactly.
        (,,,,,, address sub0) = system.subscriptions(0);
        assertEq(t1, 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad);
        assertEq(t2, t1);
        assertEq(t3, t1);
        assertEq(sub, address(reactive));
        assertEq(sub0, address(reactive));

        // An in-flight log arriving while paused is ignored (no billing waste, no callback).
        _react(_log(0, 0.03 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 0);
        assertFalse(reactive.callbackSent(0));
    }

    function test_Resume_Resubscribes_AndReactWorksAgain() public {
        reactive.pause();
        reactive.resume();
        assertFalse(reactive.paused());
        assertEq(system.subscriptionCount(), 2); // constructor + resume
        _react(_log(0, 0.03 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 1);
    }

    function test_PauseResume_StateAndOwnerGuards() public {
        vm.expectRevert(GoalReactive.NotPaused.selector);
        reactive.resume();
        reactive.pause();
        vm.expectRevert(GoalReactive.AlreadyPaused.selector);
        reactive.pause();
        vm.prank(stranger);
        vm.expectRevert(GoalReactive.NotOwner.selector);
        reactive.resume();
        vm.prank(stranger);
        vm.expectRevert(GoalReactive.NotOwner.selector);
        reactive.pause();
    }

    // --- retry ---

    function test_RetryCallback_ReRequestsForFiredGoal() public {
        _react(_log(3, 0.05 ether, 0.03 ether));
        assertEq(system.callbackRequestCount(), 1);
        (uint256 total, uint256 target) = reactive.lastHit(3);
        assertEq(total, 0.05 ether);
        assertEq(target, 0.03 ether);

        reactive.retryCallback(3);
        assertEq(system.callbackRequestCount(), 2);
        (uint256 chainId, address recipient,, bytes memory payload,) = system.lastCallbackRequest();
        assertEq(chainId, SEPOLIA);
        assertEq(recipient, callback);
        assertEq(payload, abi.encodeWithSignature("onGoalReached(address,uint256)", address(0), uint256(3)));
        // Guard stays set — retry is explicit, react() still won't re-fire.
        assertTrue(reactive.callbackSent(3));
    }

    function test_RetryCallback_UnfiredGoalReverts_AndOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(GoalReactive.NothingToRetry.selector, 9));
        reactive.retryCallback(9);
        _react(_log(1, 0.03 ether, 0.03 ether));
        vm.prank(stranger);
        vm.expectRevert(GoalReactive.NotOwner.selector);
        reactive.retryCallback(1);
    }

    // --- react() extra filter: wrong origin chain in the record ---

    function test_WrongChainIdInRecord_IgnoredSilently() public {
        IReactive.LogRecord memory log_ = _log(0, 0.03 ether, 0.03 ether);
        log_.chainId = 84532; // Base Sepolia — not our origin
        _react(log_);
        assertEq(system.callbackRequestCount(), 0);
    }
}
