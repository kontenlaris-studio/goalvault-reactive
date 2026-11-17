#!/usr/bin/env bash
# =============================================================================
# GoalVault — ONE-COMMAND deployment (Reactive Omni Buildathon)
# -----------------------------------------------------------------------------
# Follows deployments.md / BUILD-PLAN.md §4.4 order EXACTLY:
#   0.  Env + chain-id gates + funding preflight (+ lREACT faucet conversion)
#   1.  GoalVault + EscrowVault + TemplateRegistry        -> Sepolia
#   2.  GoalReactive x2 (constructor subscribes)          -> Lasna
#   3.  Fund reactives:  SYSTEM.depositTo(reactive)       (Lasna, ~1 lREACT ea)
#   4.  GoalCallback x2 (proxy, reactive, vault)          -> Sepolia
#   5.  Fund callbacks:  proxy.depositTo(callback)        (Sepolia ETH ea)
#   6.  Wire: reactive.setRecipient(callback) x2
#             vault.setExecutor(callback) x2        (one-time!)
#   7.  TemplateRegistry: register both templates
#   8.  Verify: debt() == 0 on BOTH sides (SYSTEM + callback proxy), or ABORT
#   9.  Fill dashboard/config.js + write deployed-addresses.txt (+ Sourcify
#       verify attempts, non-fatal)
#
# Keys are read from ../deploy.env RELATIVE TO THE PROJECT ROOT
# (i.e. ~/workspace/reactive-omni/deploy.env — OUTSIDE this git repo,
# chmod 600, testnet-only). This script NEVER prints the private key.
#
# DO NOT RUN until the deployer is funded. Funding target (Sepolia ETH):
#   lean ~0.15 ETH total  |  comfortable ~0.30 ETH if you use the docs'
#   0.1 ETH-per-callback depositTo example verbatim (CALLBACK_FUND_WEI below).
#
# Overridable amounts (wei):
#   FAUCET_CONVERT_WEI  Sepolia ETH -> lREACT (1 ETH = 100 lREACT) [0.03 ETH]
#   REACTIVE_FUND_WEI   depositTo per reactive contract           [1 lREACT]
#   CALLBACK_FUND_WEI   depositTo per callback contract           [0.03 ETH]
# =============================================================================
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/../deploy.env"
cd "$PROJECT_ROOT"

[ -f "$ENV_FILE" ] || { echo "ABORT: $ENV_FILE not found"; exit 1; }
# shellcheck disable=SC1091
set -a; source "$ENV_FILE"; set +a
: "${PRIVATE_KEY:?PRIVATE_KEY missing in deploy.env}"
DEPLOYER="${DEPLOYER:-${DEPLOYER_ADDRESS:?DEPLOYER missing in deploy.env}}"

# --- Constants (deployments.md) ---------------------------------------------
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SYSTEM=0x8888888888888888888888888888888888888888
SEPOLIA_CALLBACK_PROXY=0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4
LREACT_FAUCET=0x9b9BB25f1A81078C544C829c5EB7822d747Cf434
TOPIC0_EXPECTED=0x893e8a14c42d0303c66e296f4c3e4ed772edf8097f8d41ab8d08099654172ec0

FAUCET_CONVERT_WEI="${FAUCET_CONVERT_WEI:-30000000000000000}"   # 0.03 ETH -> 3 lREACT
REACTIVE_FUND_WEI="${REACTIVE_FUND_WEI:-1000000000000000000}"   # 1 lREACT each (deployments.md)
CALLBACK_FUND_WEI="${CALLBACK_FUND_WEI:-30000000000000000}"     # 0.03 ETH each (docs example: 0.1)

LOG_FILE="$PROJECT_ROOT/deploy-$(date +%Y%m%d-%H%M%S).log"      # *.log is gitignored
echo "== GoalVault deploy-all — tip: re-run as  ./scripts/deploy-all.sh 2>&1 | tee $LOG_FILE  to keep a log"
echo "== Deployer: $DEPLOYER (key never printed)"

# --- Helpers ------------------------------------------------------------------
wei_to_eth() { cast from-wei "$1" ether 2>/dev/null || echo "$1 wei"; }
bal_sepolia() { cast balance "$DEPLOYER" --rpc-url "$SEPOLIA_RPC"; }
bal_lasna()   { cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC"; }

# forge create -> ONLY the deployed address goes to stdout (so callers can
# capture it with $(...)); all informational output goes to stderr.
deploy() { # $1=rpc  $2=contract(path:Name)  $3..=constructor args
  local rpc="$1" contract="$2"; shift 2
  local out addr attempt
  # Retry on "nonce too low": load-balanced public RPCs (publicnode) can hand
  # forge a stale nonce from a lagging node while the chain head has moved on
  # (hit live 2026-11-17: GoalVault landed, EscrowVault deploy got nonce 1
  # when next nonce was already 2). A nonce-too-low tx never landed, so
  # retrying after a pause is safe.
  for attempt in 1 2 3 4 5 6; do
    if out="$(forge create "$contract" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" --broadcast "$@" 2>&1)"; then
      break
    fi
    if printf '%s' "$out" | grep -qi 'nonce too low' && [ "$attempt" -lt 6 ]; then
      echo "   (nonce sync lag on $contract — retry $attempt/6 in 8s)" >&2; sleep 8; out=""; continue
    fi
    echo "$out" >&2; echo "ABORT: deploy failed for $contract" >&2; exit 1
  done
  echo "$out" | grep -vE '^(Compiler run|Compiling|No files changed)' >&2 || true
  addr="$(printf '%s\n' "$out" | sed -n 's/.*Deployed to:[[:space:]]*\(0x[0-9a-fA-F]\{40\}\).*/\1/p' | head -1)"
  if [ -z "$addr" ]; then
    addr="$(printf '%s\n' "$out" | python3 -c 'import sys,re,json
s=sys.stdin.read()
try:
    d=json.loads(s[s.index("{"):s.rindex("}")+1])
    print(d.get("deployedTo") or d.get("contractAddress") or d.get("address") or "")
except Exception:
    m=re.search(r"0x[0-9a-fA-F]{40}", s); print(m.group(0) if m else "")' 2>/dev/null || true)"
  fi
  [ -n "$addr" ] || { echo "ABORT: could not parse deployed address for $contract" >&2; exit 1; }
  printf '%s' "$addr"
}

send() { # $1=rpc $2=target $3=signature $4..=args (may include --value via $SEND_VALUE)
  local rpc="$1" target="$2" sig="$3"; shift 3
  local attempt out
  # Same nonce-lag retry as deploy(): a "nonce too low" rejection means the
  # tx never landed, so re-sending after a pause cannot double-execute.
  for attempt in 1 2 3 4 5 6; do
    if [ -n "${SEND_VALUE:-}" ]; then
      out="$(cast send "$target" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" "$sig" "$@" --value "$SEND_VALUE" 2>&1)" && break
    else
      out="$(cast send "$target" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" "$sig" "$@" 2>&1)" && break
    fi
    if printf '%s' "$out" | grep -qi 'nonce too low' && [ "$attempt" -lt 6 ]; then
      echo "   (nonce sync lag on $sig — retry $attempt/6 in 8s)"; sleep 8; out=""; continue
    fi
    echo "$out" >&2; echo "ABORT: send failed for $sig -> $target" >&2; exit 1
  done
  SEND_VALUE=""
  echo "   ok: $sig -> $target"
}

# --- 0. Gates + preflight -------------------------------------------------------
echo "== 0. Chain-id gates"
[ "$(cast chain-id --rpc-url "$SEPOLIA_RPC")" = "11155111" ] || { echo "ABORT: Sepolia RPC wrong chain"; exit 1; }
[ "$(cast chain-id --rpc-url "$LASNA_RPC")"   = "5318007"  ] || { echo "ABORT: Lasna RPC wrong chain"; exit 1; }
TOPIC0="$(cast keccak "Deposited(uint256,address,uint256,uint256,uint256)")"
[ "$TOPIC0" = "$TOPIC0_EXPECTED" ] || { echo "ABORT: topic0 mismatch: $TOPIC0 != $TOPIC0_EXPECTED"; exit 1; }
echo "   chains OK, topic0 OK: $TOPIC0"

echo "== 0b. Funding preflight"
SEPOLIA_BAL="$(bal_sepolia)"; LASNA_BAL="$(bal_lasna)"
echo "   Sepolia: $(wei_to_eth "$SEPOLIA_BAL") ETH | Lasna: $(wei_to_eth "$LASNA_BAL") lREACT"
# Minimum Sepolia spend inside this script: faucet conversion + 2 callback
# funds + ~0.01 ETH deploy-gas buffer (at today's ~16 wei base fee the real
# gas is dust; the buffer covers a gas-price spike).
MIN_SEPOLIA=$(( FAUCET_CONVERT_WEI + 2 * CALLBACK_FUND_WEI + 10000000000000000 ))
python3 - "$SEPOLIA_BAL" "$MIN_SEPOLIA" <<'PY' || { echo "ABORT: Sepolia balance below script minimum — fund the deployer first (target ~0.15 ETH lean / ~0.30 ETH comfortable)"; exit 1; }
import sys
sys.exit(0 if int(sys.argv[1]) >= int(sys.argv[2]) else 1)
PY

echo "== 0c. lREACT via faucet contract (only if Lasna balance < 2.5 lREACT)"
if python3 -c "import sys; sys.exit(0 if int('$LASNA_BAL') < 2500000000000000000 else 1)"; then
  SEND_VALUE="$FAUCET_CONVERT_WEI" send "$SEPOLIA_RPC" "$LREACT_FAUCET" "request(address)" "$DEPLOYER"
  echo "   waiting for lREACT to land on Lasna (poll 12 x 5s)..."
  for _ in $(seq 1 12); do
    sleep 5; LASNA_BAL="$(bal_lasna)"
    # if-form (not `cmd && break`) so a negative check can never trip `set -e`.
    if python3 -c "import sys; sys.exit(0 if int('$LASNA_BAL') >= 2200000000000000000 else 1)"; then break; fi
  done
  echo "   Lasna balance now: $(wei_to_eth "$LASNA_BAL") lREACT"
  python3 -c "import sys; sys.exit(0 if int('$LASNA_BAL') >= 2200000000000000000 else 1)" \
    || { echo "ABORT: lREACT did not arrive (>=2.2 needed for 2x depositTo + deploy gas). Wait and re-run — re-running before step 1 is safe."; exit 1; }
else
  echo "   sufficient lREACT already, skipping conversion"
fi

# --- 1. Vaults + Registry on Sepolia -------------------------------------------
echo "== 1. Deploy vaults + registry (Sepolia)"
# PRESET_* env vars (resume support): set one to reuse an already-deployed
# contract from an aborted earlier run instead of double-deploying it.
# Verify any preset on-chain yourself before re-running (code + wiring state).
if [ -n "${PRESET_GOAL_VAULT:-}" ]; then GOAL_VAULT="$PRESET_GOAL_VAULT"; echo "   GoalVault:        $GOAL_VAULT (reused via PRESET)"; else GOAL_VAULT="$(deploy "$SEPOLIA_RPC" src/sepolia/GoalVault.sol:GoalVault)";          echo "   GoalVault:        $GOAL_VAULT"; fi
if [ -n "${PRESET_ESCROW_VAULT:-}" ]; then ESCROW_VAULT="$PRESET_ESCROW_VAULT"; echo "   EscrowVault:      $ESCROW_VAULT (reused via PRESET)"; else ESCROW_VAULT="$(deploy "$SEPOLIA_RPC" src/sepolia/EscrowVault.sol:EscrowVault)";    echo "   EscrowVault:      $ESCROW_VAULT"; fi
if [ -n "${PRESET_REGISTRY:-}" ]; then REGISTRY="$PRESET_REGISTRY"; echo "   TemplateRegistry: $REGISTRY (reused via PRESET)"; else REGISTRY="$(deploy "$SEPOLIA_RPC" src/sepolia/TemplateRegistry.sol:TemplateRegistry)"; echo "   TemplateRegistry: $REGISTRY"; fi

# --- 2. Reactive x2 on Lasna (constructor subscribes) ---------------------------
echo "== 2. Deploy GoalReactive x2 (Lasna)"
if [ -n "${PRESET_REACTIVE_GOAL:-}" ]; then REACTIVE_GOAL="$PRESET_REACTIVE_GOAL"; else REACTIVE_GOAL="$(deploy "$LASNA_RPC" src/reactive/GoalReactive.sol:GoalReactive --constructor-args 11155111 "$GOAL_VAULT" "$TOPIC0")"; fi
echo "   GoalReactive (GoalVault):   $REACTIVE_GOAL"
if [ -n "${PRESET_REACTIVE_ESCROW:-}" ]; then REACTIVE_ESCROW="$PRESET_REACTIVE_ESCROW"; else REACTIVE_ESCROW="$(deploy "$LASNA_RPC" src/reactive/GoalReactive.sol:GoalReactive --constructor-args 11155111 "$ESCROW_VAULT" "$TOPIC0")"; fi
echo "   GoalReactive (EscrowVault): $REACTIVE_ESCROW"

# --- 3. Fund reactives via SYSTEM.depositTo (both sides' first funding) ---------
echo "== 3. Fund reactives via SYSTEM.depositTo (Lasna)"
SEND_VALUE="$REACTIVE_FUND_WEI" send "$LASNA_RPC" "$SYSTEM" "depositTo(address)" "$REACTIVE_GOAL"
SEND_VALUE="$REACTIVE_FUND_WEI" send "$LASNA_RPC" "$SYSTEM" "depositTo(address)" "$REACTIVE_ESCROW"

# --- 4. Callbacks x2 on Sepolia (proxy, reactive, vault) -------------------------
echo "== 4. Deploy GoalCallback x2 (Sepolia) — reactive address is IMMUTABLE here, double-check the log lines above"
if [ -n "${PRESET_CALLBACK_GOAL:-}" ]; then CALLBACK_GOAL="$PRESET_CALLBACK_GOAL"; else CALLBACK_GOAL="$(deploy "$SEPOLIA_RPC" src/sepolia/GoalCallback.sol:GoalCallback --constructor-args "$SEPOLIA_CALLBACK_PROXY" "$REACTIVE_GOAL" "$GOAL_VAULT")"; fi
echo "   GoalCallback (GoalVault):   $CALLBACK_GOAL"
if [ -n "${PRESET_CALLBACK_ESCROW:-}" ]; then CALLBACK_ESCROW="$PRESET_CALLBACK_ESCROW"; else CALLBACK_ESCROW="$(deploy "$SEPOLIA_RPC" src/sepolia/GoalCallback.sol:GoalCallback --constructor-args "$SEPOLIA_CALLBACK_PROXY" "$REACTIVE_ESCROW" "$ESCROW_VAULT")"; fi
echo "   GoalCallback (EscrowVault): $CALLBACK_ESCROW"

# --- 5. Fund callbacks via proxy depositTo ---------------------------------------
echo "== 5. Fund callbacks via proxy depositTo (Sepolia)"
SEND_VALUE="$CALLBACK_FUND_WEI" send "$SEPOLIA_RPC" "$SEPOLIA_CALLBACK_PROXY" "depositTo(address)" "$CALLBACK_GOAL"
SEND_VALUE="$CALLBACK_FUND_WEI" send "$SEPOLIA_RPC" "$SEPOLIA_CALLBACK_PROXY" "depositTo(address)" "$CALLBACK_ESCROW"

# --- 6. Wire the cycle ------------------------------------------------------------
echo "== 6. Wire: setRecipient (Lasna) + setExecutor (Sepolia, one-time)"
send "$LASNA_RPC"   "$REACTIVE_GOAL"   "setRecipient(address)" "$CALLBACK_GOAL"
send "$LASNA_RPC"   "$REACTIVE_ESCROW" "setRecipient(address)" "$CALLBACK_ESCROW"
send "$SEPOLIA_RPC" "$GOAL_VAULT"      "setExecutor(address)"  "$CALLBACK_GOAL"
send "$SEPOLIA_RPC" "$ESCROW_VAULT"    "setExecutor(address)"  "$CALLBACK_ESCROW"

# --- 7. Register templates ----------------------------------------------------------
echo "== 7. Register templates in TemplateRegistry"
send "$SEPOLIA_RPC" "$REGISTRY" "registerTemplate(string,string,address,address)" "Savings Goal"    "goalvault" "$GOAL_VAULT"   "$CALLBACK_GOAL"
send "$SEPOLIA_RPC" "$REGISTRY" "registerTemplate(string,string,address,address)" "Pay When Funded" "escrow"    "$ESCROW_VAULT" "$CALLBACK_ESCROW"

# --- 8. Debt verification (MUST be 0 on both sides) ----------------------------------
echo "== 8. Debt check — all four must be 0"
FAIL=0
check_debt() { # $1=rpc $2=payer-contract $3=subject $4=label
  local d
  d="$(cast call "$2" --rpc-url "$1" "debt(address)(uint256)" "$3")"
  echo "   debt($4) = $d"
  [ "$d" = "0" ] || FAIL=1
}
check_debt "$LASNA_RPC"   "$SYSTEM"                "$REACTIVE_GOAL"   "reactive-goal"
check_debt "$LASNA_RPC"   "$SYSTEM"                "$REACTIVE_ESCROW" "reactive-escrow"
check_debt "$SEPOLIA_RPC" "$SEPOLIA_CALLBACK_PROXY" "$CALLBACK_GOAL"   "callback-goal"
check_debt "$SEPOLIA_RPC" "$SEPOLIA_CALLBACK_PROXY" "$CALLBACK_ESCROW" "callback-escrow"
[ "$FAIL" = "0" ] || { echo "ABORT: debt != 0 somewhere — top up via depositTo and re-check before triggering"; exit 1; }
echo "   all debt == 0 OK"

# --- 9. Record addresses ---------------------------------------------------------------
echo "== 9. Record addresses"
cat > "$PROJECT_ROOT/deployed-addresses.txt" <<EOF
# GoalVault deployed addresses — $(date -u +%Y-%m-%dT%H:%M:%SZ) — deployer $DEPLOYER
GOAL_VAULT=$GOAL_VAULT
ESCROW_VAULT=$ESCROW_VAULT
TEMPLATE_REGISTRY=$REGISTRY
REACTIVE_GOAL_VAULT=$REACTIVE_GOAL
REACTIVE_ESCROW_VAULT=$REACTIVE_ESCROW
CALLBACK_GOAL_VAULT=$CALLBACK_GOAL
CALLBACK_ESCROW_VAULT=$CALLBACK_ESCROW
SYSTEM=$SYSTEM
SEPOLIA_CALLBACK_PROXY=$SEPOLIA_CALLBACK_PROXY
LREACT_FAUCET=$LREACT_FAUCET
TOPIC0=$TOPIC0
EOF
# Fill dashboard/config.js contract fields (unique keys, empty-string values)
sed -i \
  -e "s|goalVault: \"\"|goalVault: \"$GOAL_VAULT\"|" \
  -e "s|escrowVault: \"\"|escrowVault: \"$ESCROW_VAULT\"|" \
  -e "s|templateRegistry: \"\"|templateRegistry: \"$REGISTRY\"|" \
  -e "s|goalReactiveGoalVault: \"\"|goalReactiveGoalVault: \"$REACTIVE_GOAL\"|" \
  -e "s|goalReactiveEscrowVault: \"\"|goalReactiveEscrowVault: \"$REACTIVE_ESCROW\"|" \
  -e "s|goalCallbackGoalVault: \"\"|goalCallbackGoalVault: \"$CALLBACK_GOAL\"|" \
  -e "s|goalCallbackEscrowVault: \"\"|goalCallbackEscrowVault: \"$CALLBACK_ESCROW\"|" \
  "$PROJECT_ROOT/dashboard/config.js"
echo "   wrote deployed-addresses.txt and filled dashboard/config.js"
echo "   NEXT (manual): paste these addresses + deploy tx hashes (in $LOG_FILE)"
echo "   into deployments.md, then run scripts/trigger.sh for the proof loop."

# --- 10. Sourcify verification (best-effort, non-fatal) ----------------------------------
echo "== 10. Sourcify verification (best-effort)"
forge verify-contract --verifier sourcify --chain-id 11155111 "$GOAL_VAULT"   src/sepolia/GoalVault.sol:GoalVault           || echo "   (verify GoalVault failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 11155111 "$ESCROW_VAULT" src/sepolia/EscrowVault.sol:EscrowVault       || echo "   (verify EscrowVault failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 11155111 "$REGISTRY"     src/sepolia/TemplateRegistry.sol:TemplateRegistry || echo "   (verify Registry failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 5318007  "$REACTIVE_GOAL" src/reactive/GoalReactive.sol:GoalReactive \
  --constructor-args "$(cast abi-encode 'f(uint256,address,uint256)' 11155111 "$GOAL_VAULT" "$TOPIC0")"                      || echo "   (verify ReactiveGoal failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 5318007  "$REACTIVE_ESCROW" src/reactive/GoalReactive.sol:GoalReactive \
  --constructor-args "$(cast abi-encode 'f(uint256,address,uint256)' 11155111 "$ESCROW_VAULT" "$TOPIC0")"                    || echo "   (verify ReactiveEscrow failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 11155111 "$CALLBACK_GOAL" src/sepolia/GoalCallback.sol:GoalCallback \
  --constructor-args "$(cast abi-encode 'f(address,address,address)' "$SEPOLIA_CALLBACK_PROXY" "$REACTIVE_GOAL" "$GOAL_VAULT")"     || echo "   (verify CallbackGoal failed — retry manually)"
forge verify-contract --verifier sourcify --chain-id 11155111 "$CALLBACK_ESCROW" src/sepolia/GoalCallback.sol:GoalCallback \
  --constructor-args "$(cast abi-encode 'f(address,address,address)' "$SEPOLIA_CALLBACK_PROXY" "$REACTIVE_ESCROW" "$ESCROW_VAULT")" || echo "   (verify CallbackEscrow failed — retry manually)"

echo "== DONE. Debt == 0 on both sides. Run scripts/trigger.sh for the proof loop."
