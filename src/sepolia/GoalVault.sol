// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReleasableVault } from "../interfaces/IReleasableVault.sol";

/// @title GoalVault — Template #1: "Savings Goal" (Track: Set It and Forget It)
/// @notice A set-and-forget savings vault on Ethereum Sepolia.
///         A user creates a goal (target amount + beneficiary) and tops it up whenever.
///         Every deposit emits `Deposited` carrying the running `total` AND the `target`,
///         so a Reactive contract on Lasna can decide — without calling back to Sepolia —
///         whether the goal has been reached. The instant it has, a Reactive callback
///         calls `release()` (via the executor) and the funds go to the beneficiary.
///         No keeper, no server, no cron, nobody has to press a button at the right moment.
///
/// @dev Security model (audit-hardened):
///      - Checks-Effects-Interactions everywhere + a hand-rolled reentrancy lock on
///        every function that sends ETH (`release`/`completeGoal`, `withdraw`).
///      - Payouts are push-with-pull-fallback: if the beneficiary cannot receive
///        ETH at callback time, `release()` does NOT revert (a reverting callback
///        is still billed and, the Reactive side being one-shot, would strand the
///        funds). The amount is credited to `pendingWithdrawals` instead and the
///        beneficiary claims it with `withdraw()` whenever they can receive.
///      - Per-depositor accounting (`contributions`) powers creator refunds:
///        `cancelGoal` credits every contributor exactly what they put in, from
///        that goal's funds only — other goals' totals are never touched.
contract GoalVault is IReleasableVault {
    struct Goal {
        address owner;
        address beneficiary;
        uint256 target;
        uint256 total;
        bool completed;
        bool cancelled;
    }

    address public owner;
    /// @notice The only address allowed to complete goals — the GoalCallback contract.
    ///         Set exactly once by the owner after the callback contract is deployed.
    address public executor;
    uint256 public goalCount;
    mapping(uint256 => Goal) public goals;

    /// @notice Per-depositor contributions per goal — the refund ledger.
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => address[]) internal _contributors;
    mapping(uint256 => mapping(address => bool)) internal _isContributor;

    /// @notice Pull-payment credits: deferred payouts + cancellation refunds.
    ///         Claim with `withdraw()`. Invariant: vault balance >= sum of all
    ///         active goals' `total` + sum of all `pendingWithdrawals`.
    mapping(address => uint256) public pendingWithdrawals;

    uint256 private _lock = 1;

    /// @notice THE event the whole system listens to. `target` travels with the event on
    ///         purpose: a reactive contract cannot call Sepolia, so the condition data
    ///         must be self-contained in the log.
    ///         topic0 = keccak256("Deposited(uint256,address,uint256,uint256,uint256)")
    event Deposited(uint256 indexed goalId, address indexed depositor, uint256 amount, uint256 total, uint256 target);
    event GoalCreated(uint256 indexed goalId, address indexed owner, address indexed beneficiary, uint256 target);
    event GoalCompleted(uint256 indexed goalId, address indexed beneficiary, uint256 total);
    event GoalCancelled(uint256 indexed goalId, address indexed owner, uint256 total);
    event PayoutDeferred(uint256 indexed goalId, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event ExecutorSet(address indexed executor);

    error NotOwner();
    error NotExecutor();
    error NotGoalOwner(uint256 goalId);
    error ExecutorAlreadySet();
    error InvalidBeneficiary();
    error InvalidTarget();
    error GoalNotFound(uint256 goalId);
    error GoalAlreadyCompleted(uint256 goalId);
    error GoalAlreadyCancelled(uint256 goalId);
    error ZeroDeposit();
    error PayoutFailed();
    error NothingToWithdraw();
    error ReentrantCall();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert NotExecutor();
        _;
    }

    modifier nonReentrant() {
        if (_lock != 1) revert ReentrantCall();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Wire the callback contract as executor. One-time by design: a savings
    ///         vault should not silently change who can release its funds.
    function setExecutor(address executor_) external onlyOwner {
        if (executor != address(0)) revert ExecutorAlreadySet();
        if (executor_ == address(0)) revert InvalidBeneficiary();
        executor = executor_;
        emit ExecutorSet(executor_);
    }

    /// @notice Create a savings goal. Returns the new goal id (0, 1, 2, ...).
    function createGoal(address beneficiary, uint256 target) external returns (uint256 goalId) {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (target == 0) revert InvalidTarget();
        goalId = goalCount++;
        goals[goalId] = Goal({
            owner: msg.sender, beneficiary: beneficiary, target: target, total: 0, completed: false, cancelled: false
        });
        emit GoalCreated(goalId, msg.sender, beneficiary, target);
    }

    /// @notice Top up a goal with native ETH. Emits `Deposited` with the new total and
    ///         the goal's target — the Reactive network reacts to this event.
    function deposit(uint256 goalId) external payable {
        Goal storage goal = goals[goalId];
        if (goal.target == 0) revert GoalNotFound(goalId);
        if (goal.completed) revert GoalAlreadyCompleted(goalId);
        if (goal.cancelled) revert GoalAlreadyCancelled(goalId);
        if (msg.value == 0) revert ZeroDeposit();
        goal.total += msg.value;
        if (!_isContributor[goalId][msg.sender]) {
            _isContributor[goalId][msg.sender] = true;
            _contributors[goalId].push(msg.sender);
        }
        contributions[goalId][msg.sender] += msg.value;
        emit Deposited(goalId, msg.sender, msg.value, goal.total, goal.target);
    }

    /// @notice Cancel a goal BEFORE it completes and refund every contributor
    ///         exactly their own contribution (as pull credits — see `withdraw`).
    ///         Only the goal's creator may cancel. Refund safety, three layers:
    ///         (1) deposits revert once cancelled, so no new `Deposited` events —
    ///             the Reactive side can never be triggered for a cancelled goal;
    ///         (2) if the target was already crossed and a callback is in flight,
    ///             `release()` reverts on cancelled goals, so the payout cannot
    ///             also happen — no double-spend (the callback contract absorbs
    ///             that revert, see GoalCallback);
    ///         (3) credits are moved out of this goal's accounting only; other
    ///             goals' `total`s are untouched.
    /// @dev `goal.total` is kept as the historical funded amount for display;
    ///      the refund claim itself lives in `pendingWithdrawals`.
    function cancelGoal(uint256 goalId) external {
        Goal storage goal = goals[goalId];
        if (goal.target == 0) revert GoalNotFound(goalId);
        if (msg.sender != goal.owner) revert NotGoalOwner(goalId);
        if (goal.completed) revert GoalAlreadyCompleted(goalId);
        if (goal.cancelled) revert GoalAlreadyCancelled(goalId);
        goal.cancelled = true;
        address[] storage list = _contributors[goalId];
        for (uint256 i = 0; i < list.length; i++) {
            address contributor = list[i];
            uint256 amount = contributions[goalId][contributor];
            if (amount > 0) {
                contributions[goalId][contributor] = 0;
                pendingWithdrawals[contributor] += amount;
            }
        }
        emit GoalCancelled(goalId, msg.sender, goal.total);
    }

    /// @inheritdoc IReleasableVault
    /// @notice Called by the executor (GoalCallback) when Reactive reports the target hit.
    function release(uint256 goalId) external onlyExecutor {
        _complete(goalId);
    }

    /// @notice Named alias of `release` — reads naturally in explorer traces.
    function completeGoal(uint256 goalId) external onlyExecutor {
        _complete(goalId);
    }

    function _complete(uint256 goalId) internal nonReentrant {
        Goal storage goal = goals[goalId];
        if (goal.target == 0) revert GoalNotFound(goalId);
        if (goal.completed) revert GoalAlreadyCompleted(goalId);
        if (goal.cancelled) revert GoalAlreadyCancelled(goalId);
        // Effects first (CEI): the goal is completed before any ETH moves, so a
        // reentrant release/deposit from the beneficiary's receive() fails.
        goal.completed = true;
        uint256 amount = goal.total;
        emit GoalCompleted(goalId, goal.beneficiary, amount);
        // The beneficiary address was zero-checked at createGoal time, and the
        // destination is restricted to the goal's own beneficiary — but a push
        // can still fail if that account cannot receive right now. Never let
        // that revert the completion: defer to a pull credit instead.
        // forge-lint: disable-next-line(arbitrary-send-eth, reentrancy-eth) — destination is the goal's own beneficiary, fixed + zero-checked at createGoal, caller executor-only; the call runs under the nonReentrant lock with all state finalised above (CEI), proven by test_PayoutReentrancy_PaysExactlyOnce.
        (bool ok,) = payable(goal.beneficiary).call{ value: amount }("");
        if (!ok) {
            pendingWithdrawals[goal.beneficiary] += amount;
            // forge-lint: disable-next-line(reentrancy-events) — this event reports the call's outcome; it cannot be emitted before the call it describes.
            emit PayoutDeferred(goalId, goal.beneficiary, amount);
        }
    }

    /// @notice Claim pull credits (deferred payout or cancellation refund).
    ///         CEI + reentrancy lock; if the send fails the whole call reverts,
    ///         which restores the credit — claiming is always retryable.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount); // before the call; a failed send reverts and erases it
        // forge-lint: disable-next-line(reentrancy-eth) — nonReentrant lock + credit zeroed above (CEI).
        (bool ok,) = payable(msg.sender).call{ value: amount }("");
        if (!ok) revert PayoutFailed();
    }

    /// @notice Full goal state in one call — this is what the dashboard reads.
    function getGoal(uint256 goalId)
        external
        view
        returns (address goalOwner, address beneficiary, uint256 target, uint256 total, bool completed)
    {
        Goal storage goal = goals[goalId];
        return (goal.owner, goal.beneficiary, goal.target, goal.total, goal.completed);
    }

    /// @notice Lifecycle flags for the dashboard's status rendering.
    function getGoalState(uint256 goalId) external view returns (bool completed, bool cancelled) {
        Goal storage goal = goals[goalId];
        return (goal.completed, goal.cancelled);
    }

    /// @notice How many distinct depositors a goal has (refund loop bound).
    function contributorCount(uint256 goalId) external view returns (uint256) {
        return _contributors[goalId].length;
    }
}
