# Proof trail — the full Reactive loop (LIVE, verified on-chain)

Executed 2026-11-17 on Sepolia + Reactive Lasna testnets. **Both templates ran
the complete loop end-to-end**: origin event → `react()` on Lasna → callback →
payout on Sepolia. Every hash below was verified with `eth_getTransactionReceipt`
(status `0x1`) after the run — nothing here is recorded unverified.

Demo setup (both templates): target **0.03 ETH**, beneficiary
`0x94FECE2447E4c880816d750375125F5A28409BED` (fresh receive-only address,
balance **0** before the run), deposits of 0.01 ETH (below target) then
0.02 ETH (crossing).

## Template #1 — GoalVault (Savings Goal), goal 0

| # | What | Chain | Tx hash | Explorer |
|---|---|---|---|---|
| 0 | `createGoal(beneficiary, 0.03 ETH)` | Sepolia | `0xf578175960e0e59a4b7b32249f517127ddd386e15e52a2394d9e8b2705027e37` | https://sepolia.etherscan.io/tx/0xf578175960e0e59a4b7b32249f517127ddd386e15e52a2394d9e8b2705027e37 |
| 1a | Deposit **below** target: 0.01 ETH (total 0.01 < 0.03) | Sepolia | `0x304ed1a5561a9329e486f15abb0317081bf19fd586a06ad1be3f11cc075e4606` | https://sepolia.etherscan.io/tx/0x304ed1a5561a9329e486f15abb0317081bf19fd586a06ad1be3f11cc075e4606 |
| 1b | `react()` for 1a: ran (status 0x1), **zero logs** — no `GoalTargetHit`, no callback request | Lasna | `0x4db0e39524f39cb96b95d0ee1778e435cc377fad7a4ce82102857a7c20b89224` | https://lasna.reactscan.net/tx/0x4db0e39524f39cb96b95d0ee1778e435cc377fad7a4ce82102857a7c20b89224 |
| 2a | Deposit **crossing** the target: 0.02 ETH (total 0.03 ≥ 0.03) — `Deposited` with total = target | Sepolia | `0x34237a26af37c319c7a8dbc24ee7ace2e7fcca237c8c5cc47afa112945152ef3` | https://sepolia.etherscan.io/tx/0x34237a26af37c319c7a8dbc24ee7ace2e7fcca237c8c5cc47afa112945152ef3 |
| 2b | `react()` for 2a: `GoalTargetHit(0, 0.03, 0.03)` + callback request to the system contract (calldata carries the origin tx hash 2a) | Lasna | `0x134498f8fde439857db7db8df0dfaff5105e1690f72526017a1b3b63340e30e0` | https://lasna.reactscan.net/tx/0x134498f8fde439857db7db8df0dfaff5105e1690f72526017a1b3b63340e30e0 |
| 3 | Callback delivered **one Sepolia block later** (12153732): `CallbackHandled` → `GoalCompleted`, 0.03 ETH paid to the beneficiary | Sepolia | `0xdb51a1193e9d33c74105b955852305e189f1019ef7abbbf64563a918047ca892` | https://sepolia.etherscan.io/tx/0xdb51a1193e9d33c74105b955852305e189f1019ef7abbbf64563a918047ca892 |

## Template #2 — EscrowVault (Pay When Funded), escrow 0

| # | What | Chain | Tx hash | Explorer |
|---|---|---|---|---|
| 0 | `createEscrow(freelancer, 0.03 ETH)` | Sepolia | `0x4042e4a22f4495f9aeae79996d1cff7ab6abb1f3932c0673633ad349414aefab` | https://sepolia.etherscan.io/tx/0x4042e4a22f4495f9aeae79996d1cff7ab6abb1f3932c0673633ad349414aefab |
| 1a | Deposit **below** target: 0.01 ETH — state snapshot +20 s later: `released=false`, beneficiary unchanged | Sepolia | `0xbf4a740161cc64f7f4c8416e5b792cd4d93ede50ffa46f6a8e9764c2015873a1` | https://sepolia.etherscan.io/tx/0xbf4a740161cc64f7f4c8416e5b792cd4d93ede50ffa46f6a8e9764c2015873a1 |
| 1b | `react()` for 1a: ran (status 0x1), **zero logs** — correctly no callback | Lasna | `0x89f944cb5d8fa5c05b9508c9dd2cddc9546904067285da250dcf9baa9f943fff` | https://lasna.reactscan.net/tx/0x89f944cb5d8fa5c05b9508c9dd2cddc9546904067285da250dcf9baa9f943fff |
| 2a | Deposit **crossing** the target: 0.02 ETH (total 0.03 ≥ 0.03) | Sepolia | `0xac6e2fa001e37842c4c746f2b555b8dfd6e44e9ea8c55c1be8af112c9ed6b5f1` | https://sepolia.etherscan.io/tx/0xac6e2fa001e37842c4c746f2b555b8dfd6e44e9ea8c55c1be8af112c9ed6b5f1 |
| 2b | `react()` for 2a: `GoalTargetHit(0, 0.03, 0.03)` + callback request (calldata carries origin tx 2a) | Lasna | `0xfdde19cca914b6bd989bb3f7baafbf3ea65885847e5c4cd388508a6a4bcd1511` | https://lasna.reactscan.net/tx/0xfdde19cca914b6bd989bb3f7baafbf3ea65885847e5c4cd388508a6a4bcd1511 |
| 3 | Callback delivered one Sepolia block later (12153741): `CallbackHandled` → `EscrowReleased`, 0.03 ETH paid to the freelancer | Sepolia | `0x47a2aeda10a1e326371bb199faf67d1674ba90fd908e87bdec28b440331fa722` | https://sepolia.etherscan.io/tx/0x47a2aeda10a1e326371bb199faf67d1674ba90fd908e87bdec28b440331fa722 |

## Outcome checks (read back on-chain after both loops)

- GoalVault goal 0: `getGoalState` = **completed=true, cancelled=false**;
  `getGoal` total = target = 0.03 ETH.
- EscrowVault escrow 0: `getEscrowState` = **released=true, cancelled=false**.
- Beneficiary balance: **0 → 0.03 ETH** (after Template #1) → **0.06 ETH**
  (after Template #2) — exactly the two vault balances, paid by the callbacks
  with no manual transaction from anyone.
- Debt after the loops: `debt(reactive-goal)` = 0, `debt(reactive-escrow)` = 0
  (Lasna system contract); `debt(callback-goal)` = 0, `debt(callback-escrow)` = 0
  (Sepolia callback proxy). Reactive-goal reserves remaining: 0.969 lREACT.
- Negative proof: both below-target deposits produced a Lasna `react()` tx
  whose receipt contains **no logs at all** — the condition was evaluated and
  correctly did not fire — and the Sepolia-side state stayed uncompleted /
  unreleased with the beneficiary balance unchanged at that point.

## Note on `SYSTEM.getCallbacks(reactiveTxHash)`

`scripts/collect-proof.sh` calls `getCallbacks(uint256)` on the Lasna system
contract for the crossing reactive txs. Post-delivery it returns an **empty
array** for both (checked repeatedly) — delivered callbacks appear to be
pruned from that index on Omni. The callback tx hashes above were therefore
located authoritatively on the destination side instead: the `CallbackHandled`
logs emitted by our own `GoalCallback` contracts (indexed with the Lasna
reactive contract's address), then verified by receipt (status, `GoalCompleted`
/ `EscrowReleased` logs, and the ETH transfer to the beneficiary inside the
same tx).
