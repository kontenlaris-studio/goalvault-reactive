# Deployments — GoalVault (Reactive Omni Buildathon)

Status: **NOT DEPLOYED YET.** This file is filled in during the deployment stage.
Toolchain used for the build: Foundry `forge 1.9.0`, solc `0.8.29`.

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
| GoalVault | Sepolia | _TBD_ | _TBD_ |
| EscrowVault | Sepolia | _TBD_ | _TBD_ |
| TemplateRegistry | Sepolia | _TBD_ | _TBD_ |
| GoalReactive (for GoalVault) | Lasna | _TBD_ | _TBD_ |
| GoalReactive (for EscrowVault) | Lasna | _TBD_ | _TBD_ |
| GoalCallback (for GoalVault) | Sepolia | _TBD_ | _TBD_ |
| GoalCallback (for EscrowVault) | Sepolia | _TBD_ | _TBD_ |

## Wiring checklist (order matters — see BUILD-PLAN §4.4)

- [ ] Deployer funded: Sepolia ETH + lREACT (faucet contract above)
- [ ] GoalVault + EscrowVault deployed on Sepolia
- [ ] GoalReactive ×2 deployed on Lasna (constructor subscribes)
- [ ] Reactive contracts funded via `SYSTEM.depositTo(reactive)` (~1 lREACT each)
- [ ] GoalCallback ×2 deployed on Sepolia with (proxy, reactive address, vault)
- [ ] Callback contracts funded via proxy `depositTo(callback)` (~0.1 Sepolia ETH each)
- [ ] `reactive.setRecipient(callback)` ×2
- [ ] `vault.setExecutor(callback)` ×2 (one-time!)
- [ ] Registry: register both templates
- [ ] Debt check: `cast call $SYSTEM "debt(address)" $REACTIVE` == 0 on both sides
- [ ] Sources verified (Sourcify) on both chains
- [ ] Addresses pasted into `dashboard/config.js`

## Proof trail (fill in after the live loop runs — see PROOF.md)

| # | Tx | Hash |
|---|---|---|
| 1 | Origin deposit crossing the target (Sepolia) | _TBD_ |
| 2 | Reactive tx on Lasna (`GoalTargetHit` + `CallbackRequest`) | _TBD_ |
| 3 | Callback delivery / payout (Sepolia) | _TBD_ |
| + | Below-target deposit's reactive tx (condition correctly NOT firing) | _TBD_ |
