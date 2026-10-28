#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
# Verification script for phase6-02-multi-agent-traversal
set -euo pipefail

echo "=== [Verification Gate] Auditing Milestone 6.2: Multi-Agent Concurrent Traversal ==="

# 1. Verify gachi-core builds cleanly
echo "  -> Running cabal build gachi-core..."
cabal build gachi-core

# 2. Run test suite
echo "  -> Running cabal test gachi-core:test:tests..."
cabal test gachi-core:test:tests

# 3. Check for Note [Concurrent Skeletal Graph Traversal]
echo "  -> Auditing for Note [Concurrent Skeletal Graph Traversal]..."
grep -rn "\[tag:note-concurrent-traversal\]" packages/gachi-core/src/

# 4. Audit for zero partial functions
echo "  -> Auditing gachi-core for zero partial functions..."
if grep -rn -E "(\bhead\b|\btail\b|\bfromJust\b|!!)" packages/gachi-core/src/; then
  echo "ERROR: Found forbidden partial functions in packages/gachi-core/src/!"
  exit 1
fi
echo "  [PASS] Zero partial functions verified."

echo "=== [Verification Gate] Milestone 6.2 verification checks passed successfully! ==="
