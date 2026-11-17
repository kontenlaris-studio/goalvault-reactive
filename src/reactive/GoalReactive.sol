// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title GoalReactive — the brain, deployed on Reactive Lasna (Omni).
/// @notice Subscribes to `Deposited` events from a vault template on Sepolia. Every
///         deposit is checked here: if the running total has reached the target that
///         travels inside the event data, exactly one callback is requested back to
///         Sepolia to release the funds. One-shot per goal id, forever.
/// @dev Omni notes that matter:
///      - SYSTEM is the hardcoded 0x8888...8888 system contract (AbstractReactive).
///      - `react()` is guarded by `onlySystem` and must NEVER revert as a filter —
///        a reverting reaction is still billed in full. All filtering falls through.
///      - The callback payload reserves its first argument as `address(0)`: the
///        destination callback proxy overwrites it with this contract's address.
contract GoalReactive is AbstractReactive {
    /// @notice Callback gas on the destination. The proxy withholds some for its own
    ///         accounting; the official examples use 1,000,000 — do not size tightly.
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public owner;
    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable vault;
    uint256 public immutable depositedTopic0;

    /// @notice The GoalCallback contract on Sepolia. Set after deployment — this is the
    ///         documented cycle-breaker (a contract cannot be both reactive and callback,
    ///         and the callback needs this contract's address immutably at construction).
    address public recipient;

    /// @notice One-shot guard: a goal id fires at most one callback, even if more
    ///         deposits arrive after the target was reached.
    mapping(uint256 => bool) public callbackSent;

    event RecipientSet(address indexed recipient);
    /// @notice Emitted on Lasna when a target is hit — the Lasna tx carrying this log is
    ///         itself readable proof of the reaction, next to the CallbackRequest.
    event GoalTargetHit(uint256 indexed goalId, uint256 total, uint256 target);

    error NotOwner();
    error InvalidRecipient();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param originChainId_ Chain the vault lives on (Sepolia = 11155111).
    /// @param vault_ The vault contract emitting `Deposited`.
    /// @param depositedTopic0_ keccak256("Deposited(uint256,address,uint256,uint256,uint256)")
    constructor(uint256 originChainId_, address vault_, uint256 depositedTopic0_) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        destinationChainId = originChainId_; // origin == destination in this design
        vault = vault_;
        depositedTopic0 = depositedTopic0_;
        // Subscribe to every Deposited from this vault. We deliberately do NOT filter
        // on goalId (topic1): criteria match by exact equality only, and per-goal
        // subscriptions would be brittle. The decision happens in code, below.
        SYSTEM.subscribe(originChainId_, vault_, depositedTopic0_, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Point callbacks at the GoalCallback contract. Owner-only, re-settable
    ///         (unlike the callback side's immutable sender, this side is the flexible one).
    function setRecipient(address recipient_) external onlyOwner {
        if (recipient_ == address(0)) revert InvalidRecipient();
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // --- Silent filters (never revert: a reverting react() is still billed) ---
        if (log_.topic0 != depositedTopic0) return;
        if (log_.contractAddress != vault) return;
        if (log_.data.length < 96) return; // need (amount, total, target)

        uint256 goalId = log_.topic1;
        (, uint256 total, uint256 target) = abi.decode(log_.data, (uint256, uint256, uint256));

        // --- The one condition this automation exists for ---
        if (total < target) return; // below target: no callback
        if (recipient == address(0)) return; // not wired yet
        if (callbackSent[goalId]) return; // one-shot guard
        callbackSent[goalId] = true;

        emit GoalTargetHit(goalId, total, target);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                // First arg MUST be address(0): the callback proxy injects this
                // contract's address there, and the receiver authenticates against it.
                payload: abi.encodeWithSignature("onGoalReached(address,uint256)", address(0), goalId)
            })
        );
    }

    /// @notice Recover from debt (debt > 0 halts all execution). Anyone may trigger it;
    ///         it only ever pays this contract's own debt from its own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
