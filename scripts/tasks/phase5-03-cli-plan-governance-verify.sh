#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
# Verification script for phase5-03-cli-plan-governance
set -euo pipefail

echo "=== [Verification Gate] Auditing Milestone 5.3: CLI Plan Governance Subcommands ==="

# 1. Verify gachi-plan and gachi-cli build cleanly
echo "  -> Running cabal build gachi-plan gachi-cli..."
cabal build gachi-plan gachi-cli

# 2. Run test suites
echo "  -> Running cabal test gachi-plan:test:tests gachi-cli:test:tests..."
cabal test gachi-plan:test:tests gachi-cli:test:tests

# 3. Verify CLI help output includes plan subcommand
echo "  -> Verifying gachi plan CLI command help..."
cabal exec -- gachi plan --help | grep -i "checkpoint"
cabal exec -- gachi plan --help | grep -i "rollback"

# 4. Check for Note [Deterministic Plan Rollback Invariants]
echo "  -> Auditing for Note [Deterministic Plan Rollback Invariants]..."
grep -rn "\[tag:note-plan-rollback-invariants\]" packages/gachi-plan/src/

# 5. Audit for zero partial functions
echo "  -> Auditing gachi-plan and gachi-cli for zero partial functions..."
if grep -rn -E "(\bhead\b|\btail\b|\bfromJust\b|!!)" packages/gachi-plan/src/ packages/gachi-cli/src/Gachi/CLI/Plan.hs; then
  echo "ERROR: Found forbidden partial functions in plan source!"
  exit 1
fi
echo "  [PASS] Zero partial functions verified."

echo "=== [Verification Gate] Milestone 5.3 verification checks passed successfully! ==="
