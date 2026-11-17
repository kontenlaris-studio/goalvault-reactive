// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { GoalReactive } from "../src/reactive/GoalReactive.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

/// @notice Upgrade B4 — fuzz the threshold logic.
///         Property 1 (reactive): for ANY sequence of deposits, a callback is
///         requested exactly once, and exactly at the first deposit whose
///         cumulative total reaches the target — never before, never twice.
///         Property 2 (vault): for ANY multi-contributor funding of a goal,
///         cancelling credits refunds that sum exactly to the goal total and
///         every contributor recovers precisely their own input.
contract FuzzThresholdTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant DEPOSITED_TOPIC0 =
        uint256(keccak256("Deposited(uint256,address,uint256,uint256,uint256)"));

    MockSystemContract internal system;
    GoalReactive internal reactive;
    address internal vaultAddr = makeAddr("vault");
    address internal callback = makeAddr("callback");

    function setUp() public {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystemContract(payable(SYSTEM_ADDR));
        reactive = new GoalReactive(SEPOLIA, vaultAddr, DEPOSITED_TOPIC0);
        reactive.setRecipient(callback);
    }

    function _deliver(uint256 goalId, uint256 amount, uint256 total, uint256 target) internal {
        IReactive.LogRecord memory log_ = IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: vaultAddr,
            topic0: DEPOSITED_TOPIC0,
            topic1: goalId,
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount, total, target),
            blockNumber: 1,
            opCode: 3,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
    }

    function testFuzz_DepositSequence_FiresExactlyOnceAtCrossing(uint256 targetSeed, uint256[] memory amounts) public {
        uint256 target = bound(targetSeed, 1, 10 ether);
        vm.assume(amounts.length > 0 && amounts.length <= 40);
        uint256 total = 0;
        bool crossed = false;
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = bound(amounts[i], 0, 3 ether);
            total += amount;
            uint256 before = system.callbackRequestCount();
            _deliver(0, amount, total, target);
            uint256 after_ = system.callbackRequestCount();
            if (!crossed && total >= target) {
                assertEq(after_, before + 1, "must fire exactly at the crossing deposit");
                crossed = true;
            } else {
                assertEq(after_, before, "must not fire before crossing or twice after");
            }
        }
        assertEq(system.callbackRequestCount(), crossed ? 1 : 0);
        assertEq(reactive.callbackSent(0), crossed);
    }

    function testFuzz_MultiGoal_SequencesFireIndependently(uint256 targetSeed, uint256[] memory amounts) public {
        uint256 target = bound(targetSeed, 1, 5 ether);
        vm.assume(amounts.length > 1 && amounts.length <= 24);
        uint256[2] memory totals;
        bool[2] memory crossed;
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 g = i % 2;
            uint256 amount = bound(amounts[i], 0, 2 ether);
            totals[g] += amount;
            uint256 before = system.callbackRequestCount();
            _deliver(g, amount, totals[g], target);
            if (!crossed[g] && totals[g] >= target) {
                assertEq(system.callbackRequestCount(), before + 1);
                crossed[g] = true;
            } else {
                assertEq(system.callbackRequestCount(), before);
            }
        }
        assertEq(system.callbackRequestCount(), (crossed[0] ? 1 : 0) + (crossed[1] ? 1 : 0));
    }

    function testFuzz_CancelRefunds_ExactPerContributor(uint256[] memory amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 12);
        GoalVault vault = new GoalVault();
        address creator = makeAddr("creator");
        address beneficiary = makeAddr("beneficiary");
        vm.prank(creator);
        uint256 id = vault.createGoal(beneficiary, type(uint256).max / 2); // never completes

        address[] memory contributors = new address[](amounts.length);
        uint256[] memory expected = new uint256[](amounts.length);
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("c", vm.toString(i))));
            uint256 amount = bound(amounts[i], 1, 2 ether);
            expected[i] = amount;
            total += amount;
            vm.deal(contributors[i], amount);
            vm.prank(contributors[i]);
            vault.deposit{ value: amount }(id);
            assertEq(vault.contributions(id, contributors[i]), amount);
        }
        assertEq(address(vault).balance, total);

        vm.prank(creator);
        vault.cancelGoal(id);

        uint256 credited = 0;
        for (uint256 i = 0; i < contributors.length; i++) {
            credited += vault.pendingWithdrawals(contributors[i]);
            vm.prank(contributors[i]);
            vault.withdraw();
            assertEq(contributors[i].balance, expected[i], "contributor recovered exactly their input");
        }
        assertEq(credited, total, "sum of refund credits must equal the goal total");
        assertEq(address(vault).balance, 0, "every wei refunded, none left, none missing");
    }
}
