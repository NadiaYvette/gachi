#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
# Verification script for phase5-02-snapshot-ledger
set -euo pipefail

echo "=== [Verification Gate] Auditing Milestone 5.2: Append-Only Snapshot Ledger ==="

# 1. Verify gachi-plan package builds cleanly
echo "  -> Running cabal build gachi-plan..."
cabal build gachi-plan

# 2. Run test suite
echo "  -> Running cabal test gachi-plan:test:tests..."
cabal test gachi-plan:test:tests

# 3. Check for Note [Append-Only Plan Snapshot Invariants]
echo "  -> Auditing for Note [Append-Only Plan Snapshot Invariants]..."
grep -rn "\[tag:note-plan-snapshots\]" packages/gachi-plan/src/

# 4. Audit for zero partial functions
echo "  -> Auditing gachi-plan for zero partial functions..."
if grep -rn -E "(\bhead\b|\btail\b|\bfromJust\b|!!)" packages/gachi-plan/src/; then
  echo "ERROR: Found forbidden partial functions in packages/gachi-plan/src/!"
  exit 1
fi
echo "  [PASS] Zero partial functions verified."

echo "=== [Verification Gate] Milestone 5.2 verification checks passed successfully! ==="
