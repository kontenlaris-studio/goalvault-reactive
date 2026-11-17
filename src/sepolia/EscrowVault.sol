// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReleasableVault } from "../interfaces/IReleasableVault.sol";

/// @title EscrowVault — Template #2: "Pay When Funded" escrow (Set It and Forget It)
/// @notice A client and a freelancer agree on a price. The client funds the escrow in
///         as many instalments as they like — and that is the last manual step. The
///         moment the funded total reaches the agreed price, the SAME Reactive engine
///         used by GoalVault (identical `Deposited` event, identical `release()`)
///         releases the money to the freelancer automatically. No "release funds"
///         button for the client to forget, delay, or dispute.
/// @dev This template is deliberately a thin vault: it reuses GoalReactive and
///      GoalCallback unchanged, which is the point of the template pattern.
///      It carries the same audit hardening as GoalVault: CEI + reentrancy lock,
///      push-with-pull-fallback payouts (a failed push defers to
///      `pendingWithdrawals` instead of reverting the one-shot callback), and
///      per-depositor contribution accounting for client cancellation refunds.
contract EscrowVault is IReleasableVault {
    struct Escrow {
        address client;
        address freelancer;
        uint256 target; // agreed price
        uint256 total; // funded so far
        bool released;
        bool cancelled;
    }

    address public owner;
    address public executor;
    uint256 public escrowCount;
    mapping(uint256 => Escrow) public escrows;

    /// @notice Per-depositor contributions per escrow — the refund ledger.
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => address[]) internal _contributors;
    mapping(uint256 => mapping(address => bool)) internal _isContributor;

    /// @notice Pull-payment credits: deferred payouts + cancellation refunds.
    mapping(address => uint256) public pendingWithdrawals;

    uint256 private _lock = 1;

    /// @notice Identical signature to GoalVault.Deposited — one Reactive subscription
    ///         shape serves every vault template.
    event Deposited(uint256 indexed goalId, address indexed depositor, uint256 amount, uint256 total, uint256 target);
    event EscrowCreated(uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 target);
    event EscrowReleased(uint256 indexed escrowId, address indexed freelancer, uint256 total);
    event EscrowCancelled(uint256 indexed escrowId, address indexed client, uint256 total);
    event PayoutDeferred(uint256 indexed escrowId, address indexed freelancer, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event ExecutorSet(address indexed executor);

    error NotOwner();
    error NotExecutor();
    error NotClient(uint256 escrowId);
    error ExecutorAlreadySet();
    error InvalidFreelancer();
    error InvalidTarget();
    error EscrowNotFound(uint256 escrowId);
    error EscrowAlreadyReleased(uint256 escrowId);
    error EscrowAlreadyCancelled(uint256 escrowId);
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

    function setExecutor(address executor_) external onlyOwner {
        if (executor != address(0)) revert ExecutorAlreadySet();
        if (executor_ == address(0)) revert InvalidFreelancer();
        executor = executor_;
        emit ExecutorSet(executor_);
    }

    /// @notice Open an escrow for `freelancer` at the agreed `target` price.
    function createEscrow(address freelancer, uint256 target) external returns (uint256 escrowId) {
        if (freelancer == address(0)) revert InvalidFreelancer();
        if (target == 0) revert InvalidTarget();
        escrowId = escrowCount++;
        escrows[escrowId] = Escrow({
            client: msg.sender, freelancer: freelancer, target: target, total: 0, released: false, cancelled: false
        });
        emit EscrowCreated(escrowId, msg.sender, freelancer, target);
    }

    /// @notice Fund an escrow in any number of instalments.
    function deposit(uint256 escrowId) external payable {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.target == 0) revert EscrowNotFound(escrowId);
        if (escrow.released) revert EscrowAlreadyReleased(escrowId);
        if (escrow.cancelled) revert EscrowAlreadyCancelled(escrowId);
        if (msg.value == 0) revert ZeroDeposit();
        escrow.total += msg.value;
        if (!_isContributor[escrowId][msg.sender]) {
            _isContributor[escrowId][msg.sender] = true;
            _contributors[escrowId].push(msg.sender);
        }
        contributions[escrowId][msg.sender] += msg.value;
        emit Deposited(escrowId, msg.sender, msg.value, escrow.total, escrow.target);
    }

    /// @notice Cancel an escrow BEFORE release; every contributor is credited
    ///         exactly their own contribution as a pull refund (`withdraw`).
    ///         Only the client (escrow creator) may cancel. Same three-layer
    ///         protection as GoalVault.cancelGoal: deposits stop, `release()`
    ///         reverts on cancelled escrows, credits come only from this
    ///         escrow's own accounting.
    function cancelEscrow(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.target == 0) revert EscrowNotFound(escrowId);
        if (msg.sender != escrow.client) revert NotClient(escrowId);
        if (escrow.released) revert EscrowAlreadyReleased(escrowId);
        if (escrow.cancelled) revert EscrowAlreadyCancelled(escrowId);
        escrow.cancelled = true;
        address[] storage list = _contributors[escrowId];
        for (uint256 i = 0; i < list.length; i++) {
            address contributor = list[i];
            uint256 amount = contributions[escrowId][contributor];
            if (amount > 0) {
                contributions[escrowId][contributor] = 0;
                pendingWithdrawals[contributor] += amount;
            }
        }
        emit EscrowCancelled(escrowId, msg.sender, escrow.total);
    }

    /// @inheritdoc IReleasableVault
    function release(uint256 escrowId) external nonReentrant onlyExecutor {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.target == 0) revert EscrowNotFound(escrowId);
        if (escrow.released) revert EscrowAlreadyReleased(escrowId);
        if (escrow.cancelled) revert EscrowAlreadyCancelled(escrowId);
        // CEI: mark released before moving ETH.
        escrow.released = true;
        uint256 amount = escrow.total;
        emit EscrowReleased(escrowId, escrow.freelancer, amount);
        // Freelancer was zero-checked at creation; a failed push defers to a
        // pull credit instead of reverting the (one-shot) callback.
        // forge-lint: disable-next-line(reentrancy-eth) — nonReentrant lock + state finalised above (CEI).
        (bool ok,) = payable(escrow.freelancer).call{ value: amount }("");
        if (!ok) {
            pendingWithdrawals[escrow.freelancer] += amount;
            // forge-lint: disable-next-line(reentrancy-events) — reports the call's outcome; cannot precede the call.
            emit PayoutDeferred(escrowId, escrow.freelancer, amount);
        }
    }

    /// @notice Claim pull credits (deferred payout or cancellation refund).
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount); // before the call; a failed send reverts and erases it
        // forge-lint: disable-next-line(reentrancy-eth) — nonReentrant lock + credit zeroed above (CEI).
        (bool ok,) = payable(msg.sender).call{ value: amount }("");
        if (!ok) revert PayoutFailed();
    }

    function getEscrow(uint256 escrowId)
        external
        view
        returns (address client, address freelancer, uint256 target, uint256 total, bool released)
    {
        Escrow storage escrow = escrows[escrowId];
        return (escrow.client, escrow.freelancer, escrow.target, escrow.total, escrow.released);
    }

    /// @notice Lifecycle flags for the dashboard's status rendering.
    function getEscrowState(uint256 escrowId) external view returns (bool released, bool cancelled) {
        Escrow storage escrow = escrows[escrowId];
        return (escrow.released, escrow.cancelled);
    }

    function contributorCount(uint256 escrowId) external view returns (uint256) {
        return _contributors[escrowId].length;
    }
}
