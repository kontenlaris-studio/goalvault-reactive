#!/usr/bin/env bash
# Prints the evidence pack for PROOF.md after scripts/trigger.sh has run.
# Env: project .env if present, else ../deploy.env (same convention as
# deploy-all.sh). REACTIVE_TX_HASH = the Lasna reactive tx (find it on
# Reactscan under the GoalReactive address, matching the origin tx).
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

: "${VAULT:?set VAULT in env}"
: "${BENEFICIARY:?set BENEFICIARY in env}"
: "${REACTIVE:?set REACTIVE in env (the GoalReactive address on Lasna)}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SYSTEM=0x8888888888888888888888888888888888888888

echo "== goal state (Sepolia)"
cast call "$VAULT" --rpc-url "$SEPOLIA_RPC" "getGoal(uint256)(address,address,uint256,uint256,bool)" "${GOAL_ID:-0}"
echo "== goal lifecycle (completed, cancelled)"
cast call "$VAULT" --rpc-url "$SEPOLIA_RPC" "getGoalState(uint256)(bool,bool)" "${GOAL_ID:-0}"
echo "== beneficiary balance (Sepolia)"
cast balance "$BENEFICIARY" --rpc-url "$SEPOLIA_RPC"
echo "== reactive debt / reserves (Lasna) — debt MUST be 0"
cast call "$SYSTEM" --rpc-url "$LASNA_RPC" "debt(address)(uint256)" "$REACTIVE"
cast call "$SYSTEM" --rpc-url "$LASNA_RPC" "reserves(address)(uint256)" "$REACTIVE" || true
echo "== reactive paused? (Lasna)"
cast call "$REACTIVE" --rpc-url "$LASNA_RPC" "paused()(bool)" || true
if [ -n "${REACTIVE_TX_HASH:-}" ]; then
  echo "== callbacks for the reactive tx (Lasna) — destination tx hash + err"
  cast call "$SYSTEM" --rpc-url "$LASNA_RPC" "getCallbacks(uint256)" "$REACTIVE_TX_HASH" || true
fi
echo "Explorers: https://sepolia.etherscan.io · https://lasna.reactscan.net"
