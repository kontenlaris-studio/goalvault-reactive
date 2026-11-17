# Proof trail — the full Reactive loop

Filled in during the deployment stage. The submission needs a few transaction
hashes showing the complete loop: **origin event → reaction → callback**.

| # | What | Chain | Tx hash | Explorer |
|---|---|---|---|---|
| 1 | Deposit that crosses the target (`Deposited` with total ≥ target) | Sepolia | _TBD_ | https://sepolia.etherscan.io/tx/_TBD_ |
| 2 | `react()` runs: `GoalTargetHit` + `CallbackRequest` (its LogRecord points back to tx #1) | Lasna | _TBD_ | https://lasna.reactscan.net/tx/_TBD_ |
| 3 | Callback delivered: `onGoalReached` → `GoalCompleted`, beneficiary paid | Sepolia | _TBD_ | https://sepolia.etherscan.io/tx/_TBD_ |
| + | Below-target deposit: `react()` ran and correctly requested NO callback | Lasna | _TBD_ | https://lasna.reactscan.net/tx/_TBD_ |

Beneficiary balance before / after: _TBD_ / _TBD_
Debt check after the loop (`debt(reactive)`, `debt(callback)`): _TBD_ — must be 0.
