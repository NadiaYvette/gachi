#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
# Verification script for phase6-04-polytropos-coercions
set -euo pipefail

echo "=== [Verification Gate] Auditing Milestone 6.4: Polytropos Zero-Cost Coercions ==="

# 1. Verify gachi-core builds cleanly
echo "  -> Running cabal build gachi-core..."
cabal build gachi-core

# 2. Run test suite
echo "  -> Running cabal test gachi-core:test:tests..."
cabal test gachi-core:test:tests

# 3. Check for Note [Zero-Cost Polytropos Rep Coercions]
echo "  -> Auditing for Note [Zero-Cost Polytropos Rep Coercions]..."
grep -rn "\[tag:note-osteo-polytropos-coercion\]" packages/gachi-core/src/

# 4. Audit for zero partial functions
echo "  -> Auditing gachi-core for zero partial functions..."
if grep -rn -E "(\bhead\b|\btail\b|\bfromJust\b|!!)" packages/gachi-core/src/; then
  echo "ERROR: Found forbidden partial functions in packages/gachi-core/src/!"
  exit 1
fi
echo "  [PASS] Zero partial functions verified."

echo "=== [Verification Gate] Milestone 6.4 verification checks passed successfully! ==="
