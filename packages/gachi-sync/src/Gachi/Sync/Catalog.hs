{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Sync.Catalog
-- Description: Canonical shared asset catalog for cross-repository synchronization
--
-- This module implements pure, deterministic template generators for shared
-- ecosystem assets conforming to the Standardization Matrix (~/src/PLAN.md §1.A).
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], all checkouts in ~/src/* maintain
-- bit-identical formatting profiles, zero-hint linter policies, Git hooks,
-- forge-tiered CI configurations, and AI agent advisory context.
--
-- == Invariant: Deterministic Configuration Synthesis
--
-- Configuration drift is the primary vector for friction in multi-package and
-- multi-repository ecosystems. When different repositories maintain slightly
-- divergent formatting configurations or compiler warning levels:
--
-- 1. __Diff Noise:__ Cross-cutting refactors touching multiple repositories
--    produce massive cosmetic diffs caused by differing indentation, import
--    sorting rules, or column limits.
-- 2. __Toolchain Inconsistencies:__ A code pattern accepted by one repository's
--    linter or compiler invocation triggers fatal warnings in another.
-- 3. __Agent Cognitive Overhead:__ AI assistants waste context tokens discovering
--    local quirks rather than focusing on domain-specific logic.
--
-- This catalog resolves configuration drift by providing an authoritative,
-- single-source-of-truth implementation for all shared configuration assets.
-- All functions in this module are referentially transparent, total, and free of
-- ambient I/O side effects: they evaluate strictly from a 'Project' specification
-- to 'Text' (or are constant 'Text' stanzas).
--
-- = When to Use This Module
--
-- * Inspecting canonical configuration stanzas during repository audits ('Gachi.Sync.Audit').
-- * Synchronizing shared infrastructure files across ecosystem checkouts ('gachi sync').
-- * Initializing new repositories with turnkey toolchain stanzas ('gachi init').
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Catalog
-- >>> let proj = defaultProject "gongju" (Author "Nadia" "nadia@example.com")
-- >>> "indentation: 2" `Data.Text.isInfixOf` fourmoluTemplate
-- True
-- >>> "./bin/gongju-verify" `Data.Text.isInfixOf` githubCiTemplate proj
-- True
module Gachi.Sync.Catalog
  ( -- * Code Formatting Profiles (Dimension 2)
    fourmoluTemplate
  , rustfmtTemplate
  , clangFormatTemplate

    -- * Static Analysis & Linters (Dimension 3)
  , hlintTemplate

    -- * Build System Conventions (Dimension 4)
  , cabalProjectTemplate
  , cabalProjectLocalTemplate

    -- * Git Governance & Hooks (Dimension 5)
  , gitmessageTemplate
  , tagrefConfigTemplate
  , commitMsgHookTemplate
  , preCommitHookTemplate

    -- * Forge-Tiered CI Workflows (Dimension 7)
  , githubCiTemplate
  , gitlabCiTemplate

    -- * Agent Advisory & Rules (Dimension 9)
  , agentsTemplate
  , claudeTemplate
  , commitAttributionRuleTemplate
  , codeNavigationRuleTemplate
  , compilerVerificationRuleTemplate
  , documentationPrecedenceRuleTemplate

    -- * Physical Verification Harnesses
  , verifyScriptTemplate
  , tagrefScriptTemplate
  , linkcheckScriptTemplate
  , clocScriptTemplate
  , generateTagsTemplate
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Gachi.Schema.Project (Project, projectName)
import Gachi.Scaffold.Templates
  ( agentsTemplate
  , cabalProjectLocalTemplate
  , cabalProjectTemplate
  , claudeTemplate
  , clocScriptTemplate
  , commitMsgHookTemplate
  , generateTagsTemplate
  , gitmessageTemplate
  , hlintTemplate
  , linkcheckScriptTemplate
  , preCommitHookTemplate
  , tagrefConfigTemplate
  , tagrefScriptTemplate
  , verifyScriptTemplate
  )

--------------------------------------------------------------------------------
-- 1. Code Formatting Profiles (Dimension 2)
--------------------------------------------------------------------------------

-- | Canonical Fourmolu configuration enforcing deterministic, AST-preserving Haskell layout.
--
-- == Formatting Invariants & Design Decisions
--
-- * __Indentation:__ Fixed 2-space indentation depth across all syntactic forms.
-- * __Column Limit:__ Pinned to 100 characters, striking a balance between wide-screen
--   readability and side-by-side terminal diffing.
-- * __Function Arrows:__ Trailing arrows (@->@ at the end of lines) preserving
--   visual alignment in multi-argument type signatures.
-- * __Comma Style:__ Leading commas in multi-line export lists, record updates,
--   and tuple literals to minimize git diff noise during item additions.
-- * __Record Style:__ Aligned record field declarations ensuring vertical alignment
--   of field names, colons, and types.
-- * __Custom Infix Fixities:__ Registers custom row-polymorphism operator fixities
--   (@:=@, @.==@, @.#@) used throughout the polytropos engine to prevent Fourmolu
--   from breaking natural mathematical expression grouping.
fourmoluTemplate :: Text
fourmoluTemplate = T.unlines
  [ "# Fourmolu configuration for standardized ecosystem Haskell repositories"
  , "# Enforces AST-preserving layout for open row lists, record syntax, and operator fixities."
  , ""
  , "indentation: 2"
  , "column-limit: 100"
  , "function-arrows: trailing"
  , "comma-style: leading"
  , "record-style: aligned"
  , "import-export-style: diff-friendly"
  , "import-grouping: legacy"
  , "indent-wheres: true"
  , "record-brace-space: true"
  , "newlines-between-decls: 1"
  , "haddock-style: multi-line"
  , "let-style: auto"
  , "in-style: right-align"
  , "if-style: indented"
  , "single-constraint-parens: never"
  , "single-deriving-parens: always"
  , "sort-constraints: false"
  , "sort-derived-classes: false"
  , "sort-deriving-clauses: false"
  , "trailing-section-operators: true"
  , "unicode: never"
  , "respectful: true"
  , ""
  , "fixities:"
  , "  - \"infixr 5 :=\""
  , "  - \"infixr 5 .==\""
  , "  - \"infixl 8 .#\""
  ]

-- | Canonical rustfmt configuration for polyglot Rust components (e.g. asterinas, surd).
--
-- == Polyglot Formatting Invariants
--
-- * __Line Width:__ Pinned to 100 characters to match Haskell and C/C++ limits.
-- * __Tab Spaces:__ 4-space tab indentation conforming to standard Rust idioms.
-- * __Edition:__ Edition 2021/2024 idioms with modern closure and macro formatting.
-- * __Import Sorting:__ Deterministic lexicographical reordering of @use@ stanzas.
-- * __Module Reordering:__ Canonical module declaration ordering.
rustfmtTemplate :: Text
rustfmtTemplate = T.unlines
  [ "# rustfmt.toml — Ecosystem formatting conventions for Rust components"
  , "max_width = 100"
  , "tab_spaces = 4"
  , "edition = \"2021\""
  , "newline_style = \"Unix\""
  , "use_small_heuristics = \"Default\""
  , "reorder_imports = true"
  , "reorder_modules = true"
  ]

-- | Canonical .clang-format configuration based on Linux kernel and LLVM style.
--
-- == Low-Level Systems Code Formatting
--
-- Applied to C, C++, and CUDA components across low-level operating system trees:
-- * __Style Base:__ Derived from LLVM standard style.
-- * __Indentation:__ 4 spaces with tabs strictly forbidden.
-- * __Brace Placement:__ Attached braces preserving vertical density.
-- * __Include Sorting:__ Deterministic alphabetical sorting of header @#include@ directives.
clangFormatTemplate :: Text
clangFormatTemplate = T.unlines
  [ "# .clang-format — Ecosystem formatting conventions for C/C++ components"
  , "BasedOnStyle: LLVM"
  , "IndentWidth: 4"
  , "ColumnLimit: 100"
  , "UseTab: Never"
  , "BreakBeforeBraces: Attach"
  , "AllowShortFunctionsOnASingleLine: Inline"
  , "SortIncludes: true"
  ]

--------------------------------------------------------------------------------
-- 2. Forge-Tiered CI Workflows (Dimension 7)
--------------------------------------------------------------------------------

-- | GitHub Actions CI workflow for high-resource runners.
--
-- == Asymmetric CI Resource Strategy
--
-- Commercial forges like GitHub provide high-capacity container runners with ample
-- RAM, multi-core virtual CPUs, and generous monthly minutes. This workflow
-- exploits those resources to execute the full heavyweight physical verification suite:
--
-- 1. __Static Cross-Reference Gate:__ Downloads and executes Tagref to validate 100%
--    of in-code tags and reference pointers across the repository.
-- 2. __Markdown Link Gate:__ Verifies all intra-corpus relative links and section anchors.
-- 3. __Hermetic Environment:__ Installs system libraries (bubblewrap, sqlite3, z3).
-- 4. __Compiler Toolchain:__ Configures GHC 9.14.1 and Cabal 3.18.1.0 with store caching.
-- 5. __Static Linter Gate:__ Installs and executes HLint under zero-hint cleanliness.
-- 6. __Test Suite Gate:__ Compiles all packages and executes the complete Hspec test suite.
-- 7. __Turnkey Verification:__ Invokes @./bin/<project>-verify@ to ensure all gates pass.
githubCiTemplate :: Project -> Text
githubCiTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "name: CI Verification Harness"
    , ""
    , "on:"
    , "  push:"
    , "    branches: [ master ]"
    , "  pull_request:"
    , "    branches: [ master ]"
    , ""
    , "jobs:"
    , "  verify:"
    , "    name: Tagref & Verification Gates"
    , "    runs-on: ubuntu-latest"
    , "    steps:"
    , "      - name: Check out repository"
    , "        uses: actions/checkout@v4"
    , ""
    , "      - name: Install Tagref"
    , "        run: |"
    , "          mkdir -p \"${HOME}/.local/bin\""
    , "          PREFIX=\"${HOME}/.local/bin\" curl https://raw.githubusercontent.com/stepchowfun/tagref/main/install.sh -LSfs | sh"
    , "          echo \"${HOME}/.local/bin\" >> $GITHUB_PATH"
    , ""
    , "      - name: Verify Tagref Cross-References"
    , "        run: ./bin/" <> pName <> "-tagref"
    , ""
    , "      - name: Verify Markdown Links & Anchors"
    , "        run: ./bin/" <> pName <> "-linkcheck"
    , ""
    , "      - name: Install System Dependencies"
    , "        run: |"
    , "          sudo apt-get update"
    , "          sudo apt-get install -y bubblewrap sqlite3 z3"
    , ""
    , "      - name: Set up Haskell Toolchain"
    , "        uses: haskell-actions/setup@v2"
    , "        with:"
    , "          ghc-version: '9.14.1'"
    , "          cabal-version: '3.18.1.0'"
    , ""
    , "      - name: Install HLint"
    , "        run: ghcup install hlint recommended --set || true"
    , ""
    , "      - name: Cache Cabal artifacts"
    , "        uses: actions/cache@v4"
    , "        with:"
    , "          path: |"
    , "            ~/.cabal/store"
    , "            dist-newstyle"
    , "          key: ${{ runner.os }}-cabal-${{ hashFiles('cabal.project', '**/*.cabal') }}"
    , "          restore-keys: |"
    , "            ${{ runner.os }}-cabal-"
    , ""
    , "      - name: Build All Packages"
    , "        run: cabal build all --enable-tests"
    , ""
    , "      - name: Run Complete Verification Suite"
    , "        run: ./bin/" <> pName <> "-verify"
    ]

-- | GitLab CI configuration tailored for resource-constrained community runners.
--
-- == Community Forge Resource Preservation
--
-- Community forges (Framagit, Disroot, etc.) operate on shared infrastructure with
-- limited shared runner compute time and strict memory quotas. Running full GHC
-- compilation on every push would deplete shared runner quotas.
--
-- This configuration establishes an asymmetric, lightweight verification pipeline:
-- * Executes fast static verification gates (Tagref cross-references and Markdown link check).
-- * Runs the lightweight CLOC comment density audit.
-- * Completely bypasses heavy GHC compilation and link stages, finishing in < 15 seconds.
gitlabCiTemplate :: Project -> Text
gitlabCiTemplate proj =
  let pName = projectName proj
  in T.unlines
    [ "# SPDX-License-Identifier: EUPL-1.2"
    , "# GitLab CI configuration for " <> pName <> " (Framagit, Disroot)"
    , ""
    , "stages:"
    , "  - verify"
    , ""
    , "tagref-check:"
    , "  stage: verify"
    , "  image: debian:bookworm-slim"
    , "  before_script:"
    , "    - apt-get update && apt-get install -y curl git python3"
    , "    - mkdir -p /usr/local/bin"
    , "    - PREFIX=/usr/local/bin curl https://raw.githubusercontent.com/stepchowfun/tagref/main/install.sh -LSfs | sh"
    , "  script:"
    , "    - ./bin/" <> pName <> "-tagref"
    , "    - ./bin/" <> pName <> "-linkcheck"
    , "    - ./bin/" <> pName <> "-cloc --check"
    ]

--------------------------------------------------------------------------------
-- 3. Modular Agent Advisory Rules (Dimension 9)
--------------------------------------------------------------------------------

-- | Rule: Linux kernel RFC 2822 trailer format ('Assisted-by:') and DCO boundaries.
--
-- Establishes the non-negotiable legal and provenance boundary for AI contributions:
-- * __Attribution Format:__ Uses @Assisted-by: Tool (Provider / Model)@ git trailers.
-- * __DCO Invariant:__ AI agents NEVER sign off on Developer Certificate of Origin (@Signed-off-by:@)
--   or claim legal co-authorship (@Co-authored-by:@).
commitAttributionRuleTemplate :: Text
commitAttributionRuleTemplate = T.unlines
  [ "<!--"
  , "SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0"
  , "-->"
  , "# Commit Authoring & AI Attribution Rules"
  , ""
  , "**Status:** ACTIVE RULE · Bounded Context Extension"
  , "**Enforcement:** `.githooks/commit-msg` · `.gitmessage`"
  , ""
  , "## 1. Linux Kernel RFC 2822 Trailer Schema"
  , ""
  , "AI coding assistant attribution must strictly use RFC 2822 trailer format:"
  , ""
  , "1. `Assisted-by:` (Required when AI assisted):"
  , "   - Format: `Assisted-by: <Tool> (<Provider> / <Model>)` or bare `Assisted-by: <Tool>`"
  , "2. `Orchestrated-by:` (Optional when an orchestration framework directed the task):"
  , "   - Format: `Orchestrated-by: <Engine>`"
  , ""
  , "## 2. Legal Boundary: The Developer Certificate of Origin"
  , ""
  , "- NEVER use `Co-authored-by:` or `Co-developed-by:` for AI assistants."
  , "- NEVER add `Signed-off-by:` on an AI's behalf."
  ]

-- | Rule: Token-saving code navigation funnel (tags, ripgrep, ast-grep, slicing).
--
-- Guides AI agents to conserve context window tokens through hierarchical exploration:
-- 1. Symbol jump via generated @./tags@ (cheapest token cost).
-- 2. Precision line slicing via @view_file@ with @StartLine@ and @EndLine@.
-- 3. Avoid indiscriminate full-file views that exhaust context budgets.
codeNavigationRuleTemplate :: Text
codeNavigationRuleTemplate = T.unlines
  [ "<!--"
  , "SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0"
  , "-->"
  , "# Token-Saving Code Navigation Funnel"
  , ""
  , "**Status:** ACTIVE RULE · Bounded Context Extension"
  , ""
  , "Always follow the token-conservation funnel when exploring code:"
  , "1. `./tags` symbol jump via ripgrep/grep (cheapest token cost)."
  , "2. Targeted file slice viewing (view_file with StartLine/EndLine)."
  , "3. Avoid full-file reading when symbol lookups suffice."
  ]

-- | Rule: Zero-log compiler verification and zero-contamination policy.
--
-- Mandates complete mechanical verification before every commit:
-- * Zero warnings tolerated under @-Wall -Wcompat -Wredundant-constraints@.
-- * All five physical verification gates (@./bin/<project>-verify@) must pass cleanly.
-- * Strict prohibition against unverified code commits or broken tests.
compilerVerificationRuleTemplate :: Text
compilerVerificationRuleTemplate = T.unlines
  [ "<!--"
  , "SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0"
  , "-->"
  , "# Compiler Verification & Zero-Contamination Rules"
  , ""
  , "**Status:** ACTIVE RULE · Bounded Context Extension"
  , ""
  , "- Zero warnings tolerated under `-Wall -Wcompat -Wredundant-constraints`."
  , "- All 5 physical verification gates (`./bin/<project>-verify`) must pass."
  , "- Never commit broken builds, failing tests, or unverified changes."
  ]

-- | Rule: Precedence rule and the two-file operational loop.
--
-- Specifies the relationship between code, documentation, and session state:
-- * __Precedence:__ Code wins at runtime; notes corrected regardless.
-- * __Two-File Loop:__ Always update @PLAN.md@ and @STATE.md@ before concluding sessions.
-- * __Design Canonicity:__ Design documents are load-bearing engineering artifacts.
documentationPrecedenceRuleTemplate :: Text
documentationPrecedenceRuleTemplate = T.unlines
  [ "<!--"
  , "SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0"
  , "-->"
  , "# Documentation Precedence & Operational Loop"
  , ""
  , "**Status:** ACTIVE RULE · Bounded Context Extension"
  , ""
  , "1. Precedence rule: Code wins at runtime; notes corrected regardless."
  , "2. Two-file loop: Always update `PLAN.md` and `STATE.md` before concluding sessions."
  , "3. Design documents are load-bearing; keep anchors and references synchronized."
  ]
