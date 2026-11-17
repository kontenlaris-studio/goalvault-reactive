#!/usr/bin/env bash
# Demo driver for the deployment stage (NOT run during the build stage).
# Creates a goal and funds it in two deposits: one below target (nothing should
# happen) and one crossing it (Reactive should release the payout on its own).
# Env: reads project .env if present, else ../deploy.env (the deploy wallet
# file outside the repo) — same convention as deploy-all.sh.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$PROJECT_ROOT/.env" ]; then
  ENV_FILE="$PROJECT_ROOT/.env"
else
  ENV_FILE="$PROJECT_ROOT/../deploy.env"
fi
[ -f "$ENV_FILE" ] || { echo "ABORT: no .env or ../deploy.env found"; exit 1; }
# shellcheck disable=SC1091
set -a; source "$ENV_FILE"; set +a

: "${PRIVATE_KEY:?PRIVATE_KEY missing in env}"
: "${VAULT:?set VAULT in env (the deployed GoalVault address)}"
: "${BENEFICIARY:?set BENEFICIARY in env}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
TARGET_WEI="${TARGET_WEI:-30000000000000000}"   # 0.03 ETH
FIRST_WEI="${FIRST_WEI:-10000000000000000}"     # 0.01 ETH (below target)
SECOND_WEI="${SECOND_WEI:-20000000000000000}"   # 0.02 ETH (crosses target)

# Chain-id gate — endpoints rot; never skip this.
[ "$(cast chain-id --rpc-url "$SEPOLIA_RPC")" = "11155111" ] || { echo "Sepolia RPC wrong chain"; exit 1; }
[ "$(cast chain-id --rpc-url "$LASNA_RPC")" = "5318007" ] || { echo "Lasna RPC wrong chain"; exit 1; }

echo "== create goal (target $TARGET_WEI wei, beneficiary $BENEFICIARY)"
CREATE_JSON="$(cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "createGoal(address,uint256)" "$BENEFICIARY" "$TARGET_WEI" --json)"
# Parse the new goal id from the GoalCreated log (topic1) instead of assuming
# id 0 — the old version silently drove goal 0 whenever the vault already had
# goals. Falls back to $GOAL_ID / 0 with a loud warning if parsing fails.
GOAL_CREATED_TOPIC0="$(cast keccak "GoalCreated(uint256,address,address,uint256)")"
PARSED_ID="$(printf '%s' "$CREATE_JSON" | GOAL_CREATED_TOPIC0="$GOAL_CREATED_TOPIC0" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
    for log in d.get("logs", []):
        topics = log.get("topics", [])
        if len(topics) >= 2 and topics[0].lower() == os.environ["GOAL_CREATED_TOPIC0"].lower():
            print(int(topics[1], 16)); break
    else:
        print("")
except Exception:
    print("")
' 2>/dev/null || true)"
if [ -n "$PARSED_ID" ]; then
  GOAL_ID="$PARSED_ID"
else
  GOAL_ID="${GOAL_ID:-0}"
  echo "WARNING: could not parse goal id from the create receipt — using GOAL_ID=$GOAL_ID"
fi
echo "   goal id: $GOAL_ID"

echo "== deposit 1: below target — expect NO callback"
cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "deposit(uint256)" "$GOAL_ID" --value "$FIRST_WEI"

echo "== deposit 2: crosses target — SAVE THIS TX HASH as proof #1"
cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "deposit(uint256)" "$GOAL_ID" --value "$SECOND_WEI"

echo "Done. Wait a few minutes, then run scripts/collect-proof.sh"
