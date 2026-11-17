#!/usr/bin/env bash
# Demo driver for the deployment stage (NOT run during the build stage).
# Creates a goal and funds it in two deposits: one below target (nothing should
# happen) and one crossing it (Reactive should release the payout on its own).
# Requires: .env filled (see .env.example) + deployments done (deployments.md).
set -euo pipefail
source "$(dirname "$0")/../.env"

: "${VAULT:?set VAULT in .env}"
: "${BENEFICIARY:?set BENEFICIARY in .env}"
TARGET_WEI="${TARGET_WEI:-30000000000000000}"   # 0.03 ETH
FIRST_WEI="${FIRST_WEI:-10000000000000000}"     # 0.01 ETH (below target)
SECOND_WEI="${SECOND_WEI:-20000000000000000}"   # 0.02 ETH (crosses target)

# Chain-id gate — endpoints rot; never skip this.
[ "$(cast chain-id --rpc-url "$SEPOLIA_RPC")" = "11155111" ] || { echo "Sepolia RPC wrong chain"; exit 1; }
[ "$(cast chain-id --rpc-url "$LASNA_RPC")" = "5318007" ] || { echo "Lasna RPC wrong chain"; exit 1; }

echo "== create goal (target $TARGET_WEI wei, beneficiary $BENEFICIARY)"
cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "createGoal(address,uint256)" "$BENEFICIARY" "$TARGET_WEI"
GOAL_ID="${GOAL_ID:-0}"

echo "== deposit 1: below target — expect NO callback"
cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "deposit(uint256)" "$GOAL_ID" --value "$FIRST_WEI"

echo "== deposit 2: crosses target — SAVE THIS TX HASH as proof #1"
cast send "$VAULT" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "deposit(uint256)" "$GOAL_ID" --value "$SECOND_WEI"

echo "Done. Wait a few minutes, then run scripts/collect-proof.sh"
