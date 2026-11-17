# Suggested YouTube title

**GoalVault — Set It and Forget It: No-Code Reactive Automations That Finish Themselves (Reactive Omni Buildathon)**

---

# Full description (paste into YouTube / DoraHacks)

GoalVault is a no-code/low-code builder for Reactive automations, built for the
Reactive Omni Buildathon, track "Set It and Forget It".

Pick a template, answer plain questions ("Who should receive the money?",
"How much is the target?"), and deploy a vault that finishes itself: every
deposit emits an event on Sepolia, a Reactive Smart Contract on Reactive Lasna
checks the total against the target on-chain, and the moment the target is
reached it fires a callback that releases the funds on Sepolia — no keeper,
no server, no cron job, no button to remember.

Two templates run on the same engine:
1. Savings Goal (GoalVault) — save toward a target; at 100% it pays the beneficiary.
2. Pay When Funded (EscrowVault) — an escrow that pays the freelancer the moment it is fully funded.

LIVE PROOF (both templates completed the full loop on testnet, 2026-11-17):

Template #1 — GoalVault, goal 0 (target 0.03 ETH):
• Create goal (Sepolia): https://sepolia.etherscan.io/tx/0xf578175960e0e59a4b7b32249f517127ddd386e15e52a2394d9e8b2705027e37
• Below-target deposit 0.01 ETH (Sepolia): https://sepolia.etherscan.io/tx/0x304ed1a5561a9329e486f15abb0317081bf19fd586a06ad1be3f11cc075e4606
• Its reaction on Lasna — evaluated, ZERO logs, no payout: https://lasna.reactscan.net/tx/0x4db0e39524f39cb96b95d0ee1778e435cc377fad7a4ce82102857a7c20b89224
• Crossing deposit 0.02 ETH, total = target (Sepolia): https://sepolia.etherscan.io/tx/0x34237a26af37c319c7a8dbc24ee7ace2e7fcca237c8c5cc47afa112945152ef3
• Reactive tx — GoalTargetHit + callback request (Lasna): https://lasna.reactscan.net/tx/0x134498f8fde439857db7db8df0dfaff5105e1690f72526017a1b3b63340e30e0
• Callback ONE BLOCK LATER — GoalCompleted, 0.03 ETH paid out (Sepolia): https://sepolia.etherscan.io/tx/0xdb51a1193e9d33c74105b955852305e189f1019ef7abbbf64563a918047ca892

Template #2 — EscrowVault, escrow 0 (target 0.03 ETH):
• Create escrow (Sepolia): https://sepolia.etherscan.io/tx/0x4042e4a22f4495f9aeae79996d1cff7ab6abb1f3932c0673633ad349414aefab
• Below-target deposit 0.01 ETH (Sepolia): https://sepolia.etherscan.io/tx/0xbf4a740161cc64f7f4c8416e5b792cd4d93ede50ffa46f6a8e9764c2015873a1
• Its reaction on Lasna — evaluated, ZERO logs, no payout: https://lasna.reactscan.net/tx/0x89f944cb5d8fa5c05b9508c9dd2cddc9546904067285da250dcf9baa9f943fff
• Crossing deposit 0.02 ETH (Sepolia): https://sepolia.etherscan.io/tx/0xac6e2fa001e37842c4c746f2b555b8dfd6e44e9ea8c55c1be8af112c9ed6b5f1
• Reactive tx — GoalTargetHit + callback request (Lasna): https://lasna.reactscan.net/tx/0xfdde19cca914b6bd989bb3f7baafbf3ea65885847e5c4cd388508a6a4bcd1511
• Callback ONE BLOCK LATER — EscrowReleased, 0.03 ETH paid out (Sepolia): https://sepolia.etherscan.io/tx/0x47a2aeda10a1e326371bb199faf67d1674ba90fd908e87bdec28b440331fa722

Beneficiary balance went 0 → 0.03 → 0.06 ETH, paid entirely by callbacks.
Contract debt after the loops: 0 on all four checks (both reactive contracts, both callbacks).

CONTRACTS:
• GoalVault (Sepolia): 0x974465f83CC332810d475b1092F96A4376434eCD
  https://sepolia.etherscan.io/address/0x974465f83CC332810d475b1092F96A4376434eCD
• EscrowVault (Sepolia): 0x942e0d1cCB31B6C4a12E6b479D6F406C644DeE8E
  https://sepolia.etherscan.io/address/0x942e0d1cCB31B6C4a12E6b479D6F406C644DeE8E
• TemplateRegistry (Sepolia): 0x4a30CD68D2046E37f3f8cF81431d743c0b227400
  https://sepolia.etherscan.io/address/0x4a30CD68D2046E37f3f8cF81431d743c0b227400
• GoalReactive for GoalVault (Lasna): 0x24dB62b02e0D6Fd5863ab554e08aE61A44604e0D
  https://lasna.reactscan.net/address/0x24dB62b02e0D6Fd5863ab554e08aE61A44604e0D
• GoalReactive for EscrowVault (Lasna): 0x974465f83CC332810d475b1092F96A4376434eCD
  https://lasna.reactscan.net/address/0x974465f83CC332810d475b1092F96A4376434eCD
• GoalCallback for GoalVault (Sepolia): 0xfC568793c7f2a04178F4809c10312D98E61e33f1
  https://sepolia.etherscan.io/address/0xfC568793c7f2a04178F4809c10312D98E61e33f1
• GoalCallback for EscrowVault (Sepolia): 0xc772B94E8f61A3BF98A450a85aB11606190432D0
  https://sepolia.etherscan.io/address/0xc772B94E8f61A3BF98A450a85aB11606190432D0
• System contract (Lasna, Omni): 0x8888888888888888888888888888888888888888
• Sepolia callback proxy: 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4

Networks: Ethereum Sepolia (11155111) — origin + destination; Reactive Lasna (5318007) — reactive contracts.
Built with reactive-lib-omni (Omni, not Legacy), Solidity 0.8.29, Foundry. 58/58 tests pass.
Safety: creator cancel & per-contributor refunds, pause/resume, callback retry, push-with-pull-fallback payouts, reentrancy locks.

Timestamps:
0:00 The problem — somebody still has to press the button
0:20 GoalVault — a no-code builder for Reactive automations
0:40 Creating an automation in under a minute
1:00 How Reactive works behind the scenes
1:25 It finishes itself — live automations
1:45 The proof — deposit → reaction → callback, one block later
2:10 Negative proof & safety
2:30 Set it and forget it

(Note: chapter timestamps are approximate — adjust to the final cut.)
