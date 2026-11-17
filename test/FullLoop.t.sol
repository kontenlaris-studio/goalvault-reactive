// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { GoalVault } from "../src/sepolia/GoalVault.sol";
import { EscrowVault } from "../src/sepolia/EscrowVault.sol";
import { GoalReactive } from "../src/reactive/GoalReactive.sol";
import { GoalCallback } from "../src/sepolia/GoalCallback.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

/// @notice End-to-end simulation of the full Reactive loop on one EVM:
///         deposit on "Sepolia" -> system delivers log to react() on "Lasna" ->
///         mock system records the callback request -> "proxy" delivers it on
///         "Sepolia" -> funds land with the beneficiary. Run for BOTH templates
///         to prove the same engine serves GoalVault and EscrowVault unchanged.
contract FullLoopTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant DEPOSITED_TOPIC0 =
        uint256(keccak256("Deposited(uint256,address,uint256,uint256,uint256)"));

    MockSystemContract internal system;
    address internal proxy = makeAddr("sepoliaCallbackProxy");
    address internal alice = makeAddr("alice");

    function setUp() public {
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystemContract(payable(SYSTEM_ADDR));
        vm.deal(alice, 100 ether);
    }

    function _deliverLog(address vaultAddr, uint256 id, address depositor, uint256 amount, uint256 total, uint256 target)
        internal
    {
        IReactive.LogRecord memory log_ = IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: vaultAddr,
            topic0: DEPOSITED_TOPIC0,
            topic1: id,
            topic2: uint256(uint160(depositor)),
            topic3: 0,
            data: abi.encode(amount, total, target),
            blockNumber: 1,
            opCode: 3,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        // The reactive contract instance is discovered from the recorded request sender
        // in each test; here we just call react() on the instance passed via storage-free
        // convention: tests set it through _reactiveFor before calling.
        GoalReactive reactive = _reactiveFor[vaultAddr];
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
    }

    mapping(address => GoalReactive) internal _reactiveFor;

    function _wire(address vaultAddr) internal returns (GoalReactive reactive, GoalCallback callback) {
        reactive = new GoalReactive(SEPOLIA, vaultAddr, DEPOSITED_TOPIC0);
        callback = new GoalCallback(IPayable(payable(proxy)), address(reactive), vaultAddr);
        reactive.setRecipient(address(callback));
        _reactiveFor[vaultAddr] = reactive;
    }

    function _deliverCallback(GoalReactive reactive, GoalCallback callback) internal {
        (,,, bytes memory payload,) = system.lastCallbackRequest();
        // Decode the payload the way the proxy would execute it: the proxy overwrites
        // the first argument with the reactive contract's address, then calls the
        // recipient. We emulate that by calling with the injected address directly.
        (address placeholder, uint256 id) = abi.decode(_skipSelector(payload), (address, uint256));
        assertEq(placeholder, address(0));
        vm.prank(proxy);
        callback.onGoalReached(address(reactive), id);
    }

    function _skipSelector(bytes memory payload) internal pure returns (bytes memory args) {
        args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
    }

    // --- Template #1: GoalVault ---

    function test_FullLoop_GoalVault() public {
        GoalVault vault = new GoalVault();
        (GoalReactive reactive, GoalCallback callback) = _wire(address(vault));
        vault.setExecutor(address(callback));

        address beneficiary = makeAddr("beneficiary");
        vm.prank(alice);
        uint256 id = vault.createGoal(beneficiary, 0.03 ether);

        // Deposit 1: below target -> react() runs, NO callback, funds stay put.
        vm.prank(alice);
        vault.deposit{ value: 0.01 ether }(id);
        _deliverLog(address(vault), id, alice, 0.01 ether, 0.01 ether, 0.03 ether);
        assertEq(system.callbackRequestCount(), 0);
        assertEq(beneficiary.balance, 0);

        // Deposit 2: target reached -> exactly one callback -> delivery pays out.
        vm.prank(alice);
        vault.deposit{ value: 0.02 ether }(id);
        _deliverLog(address(vault), id, alice, 0.02 ether, 0.03 ether, 0.03 ether);
        assertEq(system.callbackRequestCount(), 1);

        _deliverCallback(reactive, callback);
        assertEq(beneficiary.balance, 0.03 ether);
        (,,,, bool completed) = vault.getGoal(id);
        assertTrue(completed);
    }

    // --- Template #2: EscrowVault, same engine, zero code changes ---

    function test_FullLoop_EscrowVault_SameEngine() public {
        EscrowVault escrow = new EscrowVault();
        (GoalReactive reactive, GoalCallback callback) = _wire(address(escrow));
        escrow.setExecutor(address(callback));

        address freelancer = makeAddr("freelancer");
        vm.prank(alice);
        uint256 id = escrow.createEscrow(freelancer, 0.05 ether);

        vm.prank(alice);
        escrow.deposit{ value: 0.05 ether }(id);
        _deliverLog(address(escrow), id, alice, 0.05 ether, 0.05 ether, 0.05 ether);
        assertEq(system.callbackRequestCount(), 1);

        _deliverCallback(reactive, callback);
        assertEq(freelancer.balance, 0.05 ether);
        (,,,, bool released) = escrow.getEscrow(id);
        assertTrue(released);
    }
}
