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
contract EscrowVault is IReleasableVault {
    struct Escrow {
        address client;
        address freelancer;
        uint256 target; // agreed price
        uint256 total; // funded so far
        bool released;
    }

    address public owner;
    address public executor;
    uint256 public escrowCount;
    mapping(uint256 => Escrow) public escrows;

    /// @notice Identical signature to GoalVault.Deposited — one Reactive subscription
    ///         shape serves every vault template.
    event Deposited(uint256 indexed goalId, address indexed depositor, uint256 amount, uint256 total, uint256 target);
    event EscrowCreated(uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 target);
    event EscrowReleased(uint256 indexed escrowId, address indexed freelancer, uint256 total);
    event ExecutorSet(address indexed executor);

    error NotOwner();
    error NotExecutor();
    error ExecutorAlreadySet();
    error InvalidFreelancer();
    error InvalidTarget();
    error EscrowNotFound(uint256 escrowId);
    error EscrowAlreadyReleased(uint256 escrowId);
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
        escrows[escrowId] =
            Escrow({ client: msg.sender, freelancer: freelancer, target: target, total: 0, released: false });
        emit EscrowCreated(escrowId, msg.sender, freelancer, target);
    }

    /// @notice Fund an escrow in any number of instalments.
    function deposit(uint256 escrowId) external payable {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.target == 0) revert EscrowNotFound(escrowId);
        if (escrow.released) revert EscrowAlreadyReleased(escrowId);
        if (msg.value == 0) revert ZeroDeposit();
        escrow.total += msg.value;
        emit Deposited(escrowId, msg.sender, msg.value, escrow.total, escrow.target);
    }

    /// @inheritdoc IReleasableVault
    function release(uint256 escrowId) external onlyExecutor {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.target == 0) revert EscrowNotFound(escrowId);
        if (escrow.released) revert EscrowAlreadyReleased(escrowId);
        escrow.released = true;
        uint256 amount = escrow.total;
        emit EscrowReleased(escrowId, escrow.freelancer, amount);
        (bool ok,) = payable(escrow.freelancer).call{ value: amount }("");
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
}
