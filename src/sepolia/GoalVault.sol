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
contract GoalVault is IReleasableVault {
    struct Goal {
        address owner;
        address beneficiary;
        uint256 target;
        uint256 total;
        bool completed;
    }

    address public owner;
    /// @notice The only address allowed to complete goals — the GoalCallback contract.
    ///         Set exactly once by the owner after the callback contract is deployed.
    address public executor;
    uint256 public goalCount;
    mapping(uint256 => Goal) public goals;

    /// @notice THE event the whole system listens to. `target` travels with the event on
    ///         purpose: a reactive contract cannot call Sepolia, so the condition data
    ///         must be self-contained in the log.
    ///         topic0 = keccak256("Deposited(uint256,address,uint256,uint256,uint256)")
    event Deposited(uint256 indexed goalId, address indexed depositor, uint256 amount, uint256 total, uint256 target);
    event GoalCreated(uint256 indexed goalId, address indexed owner, address indexed beneficiary, uint256 target);
    event GoalCompleted(uint256 indexed goalId, address indexed beneficiary, uint256 total);
    event ExecutorSet(address indexed executor);

    error NotOwner();
    error NotExecutor();
    error ExecutorAlreadySet();
    error InvalidBeneficiary();
    error InvalidTarget();
    error GoalNotFound(uint256 goalId);
    error GoalAlreadyCompleted(uint256 goalId);
    error ZeroDeposit();
    error PayoutFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert NotExecutor();
        _;
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
        goals[goalId] = Goal({ owner: msg.sender, beneficiary: beneficiary, target: target, total: 0, completed: false });
        emit GoalCreated(goalId, msg.sender, beneficiary, target);
    }

    /// @notice Top up a goal with native ETH. Emits `Deposited` with the new total and
    ///         the goal's target — the Reactive network reacts to this event.
    function deposit(uint256 goalId) external payable {
        Goal storage goal = goals[goalId];
        if (goal.target == 0) revert GoalNotFound(goalId);
        if (goal.completed) revert GoalAlreadyCompleted(goalId);
        if (msg.value == 0) revert ZeroDeposit();
        goal.total += msg.value;
        emit Deposited(goalId, msg.sender, msg.value, goal.total, goal.target);
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

    function _complete(uint256 goalId) internal {
        Goal storage goal = goals[goalId];
        if (goal.target == 0) revert GoalNotFound(goalId);
        if (goal.completed) revert GoalAlreadyCompleted(goalId);
        goal.completed = true;
        uint256 amount = goal.total;
        emit GoalCompleted(goalId, goal.beneficiary, amount);
        (bool ok,) = payable(goal.beneficiary).call{ value: amount }("");
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
}
