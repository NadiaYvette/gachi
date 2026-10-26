-- | Module: Gachi.Scaffold
-- Description: Declarative multi-package workspace scaffolding engine for Gachi
--
-- This is the front-door module for the @gachi-scaffold@ package. It exposes
-- the complete workspace synthesis pipeline, configuration models, template
-- generators, and filesystem materialization operations.
--
-- = Architectural Context & Invariants
--
-- Gachi serves as the ecosystem's foundational project skeleton generator and
-- configuration propagation engine (@~/src/PLAN.md@ §1).
--
-- Rather than generating ad-hoc or incomplete project skeletons that require
-- hours of manual bootstrapping, Gachi generates turn-key repositories that satisfy
-- all five physical verification gates immediately upon initialization.
--
-- == Invariant: Note [Ecosystem Standardization Invariants]
--
-- {-
-- Note [Ecosystem Standardization Invariants]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-ecosystem-standardization]
--
-- The ecosystem standardization matrix enforces universal mechanical invariants
-- across all repositories in ~/src/* (per ~/src/PLAN.md §1.A). Every workspace
-- generated or retrofitted by Gachi must satisfy these invariants immediately
-- upon creation, guaranteeing that no repository is a second-class citizen:
--
-- 1. Canonical Directory Hierarchy:
--    - Root multi-package workspace containing packages/*/
--    - Central documentation corpus under docs/ (including docs/INDEX.md,
--      docs/TUTORIAL.md, docs/NEWBIE_GUIDE.md, docs/MAINTAINER_GUIDE.md, and
--      docs/notes/)
--    - Dedicated verification harnesses under bin/ (verify, tagref, linkcheck,
--      cloc, generate-tags)
--    - Operational planning pair (PLAN.md and STATE.md)
--    - AI agent advisory layer (AGENTS.md, CLAUDE.md, .agents/rules/, .agents/skills/)
--
-- 2. Five-Gate Physical Verification:
--    Every repository provides a turnkey `./bin/<project>-verify` script that
--    executes five non-negotiable verification gates:
--    - Gate 1: Zero HLint hints (-Wall -Wcompat -Wredundant-constraints)
--    - Gate 2: Full Cabal test suite execution (cabal test all)
--    - Gate 3: Tagref cross-reference integrity (0 dangling references, 0 duplicate tags)
--    - Gate 4: Markdown link & anchor validation (0 broken relative links or invalid anchors)
--    - Gate 5: CLOC comment density audit (>= 50% comment density in production code)
--
-- 3. Git Governance & Attribution:
--    - Commit message template (.gitmessage) and validation hook (.githooks/commit-msg)
--      enforcing Sarutahiko RFC 2822 commit trailers (Assisted-by:)
--    - Pre-commit hook (.githooks/pre-commit) preventing broken tagref references or
--      broken markdown links from being committed.
--
-- 4. Hermetic Toolchain Pinning:
--    - cabal.project pinning GHC (9.14.1) and Cabal (3.18) versions
--    - EUPL-1.2 / Apache-2.0 open source licensing discipline.
-- -}
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project
-- >>> import Gachi.Scaffold
-- >>> let author = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
-- >>> let proj = defaultProject "gongju" author
-- >>> let entries = generateProjectScaffold proj
-- >>> length entries > 20
-- True
-- >>> any (\e -> entryPath e == "bin/gongju-verify" && entryExecutable e) entries
-- True
module Gachi.Scaffold
  ( -- * High-Level Scaffolding API
    generateAndWriteScaffold
  , generateProjectScaffold
  , writeScaffold

    -- * Core Types & Modes
  , FileEntry(..)
  , ScaffoldMode(..)
  , ScaffoldResult(..)
  , ScaffoldError(..)

    -- * Template Generators
  , allProjectEntries
  , cabalProjectTemplate
  , cabalProjectLocalTemplate
  , hlintTemplate
  , gitmessageTemplate
  , tagrefConfigTemplate
  , commitMsgHookTemplate
  , preCommitHookTemplate
  , verifyScriptTemplate
  , tagrefScriptTemplate
  , linkcheckScriptTemplate
  , clocScriptTemplate
  , generateTagsTemplate
  , readmeTemplate
  , agentsTemplate
  , claudeTemplate
  , planTemplate
  , stateTemplate
  , docsIndexTemplate
  , docsTutorialTemplate
  , docsNewbieGuideTemplate
  , docsMaintainerGuideTemplate
  , docsDesignTemplate
  , docsStrategyTemplate
  , docsCommitAttributionTemplate
  , packageCabalTemplate
  , packageReadmeTemplate
  , packageModuleTemplate
  , packageTestTemplate

    -- * Markdown AST & Pretty-Printing
  , Block(..)
  , Inline(..)
  , renderMarkdown
  , renderBlock
  , renderInline
  , h1
  , h2
  , h3
  , h4
  , para
  , paraInlines
  , codeBlock
  , plainCodeBlock
  , bulletList
  , orderedList
  , table
  , hr
  , rawBlock
  , plain
  , bold
  , italic
  , code
  , link
  , linkInline
  , tagRef
  , tagDef
  , inlines

    -- * String Utilities
  , defaultModuleName
  , moduleToFilePath
  , toUpperSlug
  ) where

import Gachi.Scaffold.Engine
  ( generateAndWriteScaffold
  , generateProjectScaffold
  , writeScaffold
  )
import Gachi.Scaffold.Markdown
  ( Block(..)
  , Inline(..)
  , bold
  , bulletList
  , code
  , codeBlock
  , h1
  , h2
  , h3
  , h4
  , hr
  , inlines
  , italic
  , link
  , linkInline
  , orderedList
  , para
  , paraInlines
  , plain
  , plainCodeBlock
  , rawBlock
  , renderBlock
  , renderInline
  , renderMarkdown
  , table
  , tagDef
  , tagRef
  )
import Gachi.Scaffold.Templates
  ( allProjectEntries
  , cabalProjectLocalTemplate
  , cabalProjectTemplate
  , clocScriptTemplate
  , commitMsgHookTemplate
  , defaultModuleName
  , docsCommitAttributionTemplate
  , docsDesignTemplate
  , docsIndexTemplate
  , docsMaintainerGuideTemplate
  , docsNewbieGuideTemplate
  , docsStrategyTemplate
  , docsTutorialTemplate
  , generateTagsTemplate
  , gitmessageTemplate
  , hlintTemplate
  , linkcheckScriptTemplate
  , moduleToFilePath
  , packageCabalTemplate
  , packageModuleTemplate
  , packageReadmeTemplate
  , packageTestTemplate
  , planTemplate
  , preCommitHookTemplate
  , readmeTemplate
  , stateTemplate
  , agentsTemplate
  , claudeTemplate
  , tagrefConfigTemplate
  , tagrefScriptTemplate
  , toUpperSlug
  , verifyScriptTemplate
  )
import Gachi.Scaffold.Types
  ( FileEntry(..)
  , ScaffoldError(..)
  , ScaffoldMode(..)
  , ScaffoldResult(..)
  )
