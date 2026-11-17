#!/usr/bin/env bash
# Prints the evidence pack for PROOF.md after scripts/trigger.sh has run.
# Requires .env (see .env.example). REACTIVE_TX_HASH = the Lasna reactive tx
# (find it on Reactscan under the GoalReactive address, matching the origin tx).
set -euo pipefail
source "$(dirname "$0")/../.env"
SYSTEM=0x8888888888888888888888888888888888888888

echo "== goal state (Sepolia)"
cast call "$VAULT" --rpc-url "$SEPOLIA_RPC" "getGoal(uint256)(address,address,uint256,uint256,bool)" "${GOAL_ID:-0}"
echo "== beneficiary balance (Sepolia)"
cast balance "$BENEFICIARY" --rpc-url "$SEPOLIA_RPC"
echo "== reactive debt / reserves (Lasna) — debt MUST be 0"
cast call $SYSTEM --rpc-url "$LASNA_RPC" "debt(address)(uint256)" "$REACTIVE"
cast call $SYSTEM --rpc-url "$LASNA_RPC" "reserves(address)(uint256)" "$REACTIVE" || true
if [ -n "${REACTIVE_TX_HASH:-}" ]; then
  echo "== callbacks for the reactive tx (Lasna) — destination tx hash + err"
  cast call $SYSTEM --rpc-url "$LASNA_RPC" "getCallbacks(uint256)" "$REACTIVE_TX_HASH" || true
fi
echo "Explorers: https://sepolia.etherscan.io · https://lasna.reactscan.net"
