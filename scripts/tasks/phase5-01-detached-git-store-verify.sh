#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
# Verification script for phase5-01-detached-git-store
set -euo pipefail

echo "=== [Verification Gate] Auditing Milestone 5.1: Detached Git Store Architecture ==="

# 1. Verify gachi-plan package builds cleanly
echo "  -> Running cabal build gachi-plan..."
cabal build gachi-plan

# 2. Run test suite
echo "  -> Running cabal test gachi-plan:test:tests..."
cabal test gachi-plan:test:tests

# 3. Check for Note [Plan Governance and Rollback Mechanics]
echo "  -> Auditing for Note [Plan Governance and Rollback Mechanics]..."
grep -rn "\[tag:note-plan-governance-rollback\]" packages/gachi-plan/src/

# 4. Audit for zero partial functions
echo "  -> Auditing gachi-plan for zero partial functions..."
if grep -rn -E "(\bhead\b|\btail\b|\bfromJust\b|!!)" packages/gachi-plan/src/; then
  echo "ERROR: Found forbidden partial functions in packages/gachi-plan/src/!"
  exit 1
fi
echo "  [PASS] Zero partial functions verified."

echo "=== [Verification Gate] Milestone 5.1 verification checks passed successfully! ==="
