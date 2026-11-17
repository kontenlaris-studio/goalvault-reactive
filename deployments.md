# Deployments — GoalVault (Reactive Omni Buildathon)

Status: **DEPLOYED & LIVE-PROVEN 2026-11-17.** All 7 contracts deployed, wired,
funded, debt == 0, and both templates completed the full Reactive loop on-chain
(see [PROOF.md](PROOF.md)).
Toolchain used for the build: Foundry `forge 1.9.0`, solc `0.8.29`.
Deployer: `0xf389eC3AcaCE9B1062F113a72af6Db4AE1eA204F` (testnet-only wallet;
key lives outside this repo, never committed).
Note: `GoalReactive (for EscrowVault)` on Lasna has the same address string as
`GoalVault` on Sepolia (`0x9744…4eCD`) — same deployer + same nonce on two
different chains; not a typo.

## Networks

| Role | Network | Chain ID | RPC |
|---|---|---|---|
| Origin + destination | Ethereum Sepolia | 11155111 | https://ethereum-sepolia-rpc.publicnode.com |
| Reactive | Reactive Lasna | 5318007 | https://lasna-rpc.rnk.dev/ |

## Constants

| Item | Value |
|---|---|
| System contract (Lasna + mainnet) | `0x8888888888888888888888888888888888888888` |
| Sepolia callback proxy | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` |
| lREACT faucet (Sepolia) | `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` (1 ETH → 100 lREACT) |
| `Deposited` topic0 | `0x893e8a14c42d0303c66e296f4c3e4ed772edf8097f8d41ab8d08099654172ec0` |

## Contract addresses (fill in at deployment)

| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| GoalVault | Sepolia | `0x974465f83CC332810d475b1092F96A4376434eCD` | `0xf107a59d1da07bd7aeb21743e2aa6d8ccc6a60ed0808652ff121103b95460559` |
| EscrowVault | Sepolia | `0x942e0d1cCB31B6C4a12E6b479D6F406C644DeE8E` | `0xee50d6c328b8cc7bca879bb7207259b61e2e622d3b0d252b0b09b32d7bb6b7ea` |
| TemplateRegistry | Sepolia | `0x4a30CD68D2046E37f3f8cF81431d743c0b227400` | `0xeec9ff04b2ea68afe2d39cb6a23700c49a84583cccde3969425072a367a35dad` |
| GoalReactive (for GoalVault) | Lasna | `0x24dB62b02e0D6Fd5863ab554e08aE61A44604e0D` | `0x8126d15b56e4e8d7c26a3f2bd20555ba6d62856741f17c159c93075fd3fffea3` |
| GoalReactive (for EscrowVault) | Lasna | `0x974465f83CC332810d475b1092F96A4376434eCD` | `0x75ada755b803c8fcc04b8038948593ee130754c302cfeabc95570b98cf540a82` |
| GoalCallback (for GoalVault) | Sepolia | `0xfC568793c7f2a04178F4809c10312D98E61e33f1` | `0xefbe9ea35bd785e7483bbf0e462bb0f2587a204253574a1a50f992559b812551` |
| GoalCallback (for EscrowVault) | Sepolia | `0xc772B94E8f61A3BF98A450a85aB11606190432D0` | `0x191961c5ef250d58dbb19c11766ca0068bfc431f311ff24c196f0aa6eec6fae8` |

## Wiring checklist (order matters — see BUILD-PLAN §4.4)

- [x] Deployer funded: Sepolia ETH (0.15475) + lREACT (0.03 ETH → 3.15 lREACT via faucet contract above)
- [x] GoalVault + EscrowVault deployed on Sepolia
- [x] GoalReactive ×2 deployed on Lasna (constructor subscribes)
- [x] Reactive contracts funded via `SYSTEM.depositTo(reactive)` (1 lREACT each)
- [x] GoalCallback ×2 deployed on Sepolia with (proxy, reactive address, vault)
- [x] Callback contracts funded via proxy `depositTo(callback)` (0.03 Sepolia ETH each)
- [x] `reactive.setRecipient(callback)` ×2
- [x] `vault.setExecutor(callback)` ×2 (one-time!)
- [x] Registry: register both templates
- [x] Debt check: `debt()` == 0 on both sides — re-checked again after the live loops, still 0 ×4
- [x] Sources verified (Sourcify) — verification jobs submitted for all 7 contracts on both chains
- [x] Addresses pasted into `dashboard/config.js` (done by `deploy-all.sh`, proof hashes added after the trigger run)

## Post-deploy operations (audit upgrade — no deploy-order changes)

Constructor signatures and the wiring order above are unchanged by the
audit/upgrade pass (zero-address validation was added inside the existing
constructors). New owner operations available after deployment:

- **Pause a template's automation:** `cast send $REACTIVE "pause()"` on Lasna
  (unsubscribes at the system contract; resume with `"resume()"`).
- **Retry a lost callback:** `cast send $REACTIVE "retryCallback(uint256)" <goalId>`
  on Lasna — only for goals whose callback already fired (`callbackSent`).
- **Creator cancel:** goal creators call `cancelGoal(uint256)` /
  `cancelEscrow(uint256)` on the Sepolia vault; contributors then claim
  refunds with `withdraw()` on the same vault.
- `scripts/collect-proof.sh` also reports goal lifecycle (completed/cancelled)
  and the reactive contract's paused state.

## Proof trail (fill in after the live loop runs — see PROOF.md)

Full trail with both templates, explorer links and outcome checks: see
[PROOF.md](PROOF.md). Headline hashes (Template #1 — GoalVault):

| # | Tx | Hash |
|---|---|---|
| 1 | Origin deposit crossing the target (Sepolia) | `0x34237a26af37c319c7a8dbc24ee7ace2e7fcca237c8c5cc47afa112945152ef3` |
| 2 | Reactive tx on Lasna (`GoalTargetHit` + callback request) | `0x134498f8fde439857db7db8df0dfaff5105e1690f72526017a1b3b63340e30e0` |
| 3 | Callback delivery / payout (Sepolia) | `0xdb51a1193e9d33c74105b955852305e189f1019ef7abbbf64563a918047ca892` |
| + | Below-target deposit's reactive tx (ran, zero logs — correctly NOT firing) | `0x4db0e39524f39cb96b95d0ee1778e435cc377fad7a4ce82102857a7c20b89224` |
