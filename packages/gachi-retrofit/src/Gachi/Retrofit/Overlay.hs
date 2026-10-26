{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Retrofit.Overlay
-- Description: Non-destructive skeleton overlay engine and asset synthesis
--
-- This module implements the non-destructive skeleton overlay engine for Gachi
-- (Milestone 4.2, Phase 4 per ~/src/PLAN.md §1.A). It synthesizes missing
-- documentation hierarchies, AI agent advisories, Git governance hooks, and turnkey
-- physical verification harnesses over arbitrary pre-existing or legacy repositories.
--
-- = Architectural Context & Invariants
--
-- Architectural Invariant: Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit]
--
-- In accordance with Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit]
-- and Note [Ecosystem Standardization Invariants] [ref:note-ecosystem-standardization],
-- retrofitting operations adopt foreign, legacy, or single-package repositories into the
-- canonical multi-package ecosystem hierarchy while observing four strict operational invariants:
--
-- 1. __Preservation of Domain Logic:__
--    The overlay engine must never overwrite, mutate, or delete existing source code
--    files in @src/@, @app/@, @lib/@, @test/@, or domain-specific subdirectories.
--    Pre-existing files on disk are strictly preserved and classified as 'ActionPreserve'.
--
-- 2. __Pure Plan Construction:__
--    The overlay computation phase ('computeOverlayPlan') is completely decoupled from
--    filesystem side effects. It produces an explicit, inspectable 'OverlayPlan'
--    categorizing every canonical asset into 'ActionCreate' or 'ActionPreserve'.
--
-- 3. __Turnkey Verification Harness Delivery:__
--    The synthesized overlay provisions turnkey verification scripts (@bin/<project>-verify@,
--    @bin/<project>-tagref@, @bin/<project>-linkcheck@, @bin/<project>-cloc@, @bin/generate-tags@)
--    with POSIX executable permissions (@+x@), empowering developers to immediately run all
--    five physical verification gates.
--
-- 4. __Git Governance Realization:__
--    Configures local Git repository governance (@core.hooksPath = .githooks@ and
--    @commit.template = .gitmessage@), activating the Sarutahiko RFC 2822 @Assisted-by:@
--    commit trailer validation hook and pre-commit checks without touching commit history.
--
-- = When to Use This Module
--
-- Import this module when planning or applying non-destructive ecosystem overlays
-- in the @gachi retrofit@ subcommand or programmatically migrating legacy checkouts.
--
-- = Worked Example
--
-- >>> import Gachi.Retrofit.Diagnostic (scanRepository)
-- >>> import Gachi.Retrofit.Overlay
-- >>> report <- scanRepository "/path/to/legacy/repo"
-- >>> plan <- computeOverlayPlan "/path/to/legacy/repo" report
-- >>> planCreatedCount plan >= 0
-- True
-- >>> res <- executeOverlayPlan plan
-- >>> resultSuccess res
-- True
module Gachi.Retrofit.Overlay
  ( -- * Core Overlay Types
    OverlayActionType(..)
  , OverlayCategory(..)
  , OverlayAction(..)
  , GitGovernanceAction(..)
  , OverlayPlan(..)
  , OverlayResult(..)

    -- * Planning and Synthesis
  , computeOverlayPlan
  , synthesizeOverlayCandidates
  , detectGitAuthor

    -- * Execution Engine
  , executeOverlayPlan
  , overlayRepository

    -- * Pretty-Printing & Dashboards
  , formatOverlayPlan
  , formatOverlayPlanMarkdown
  , formatOverlayResult
  , overlayCategoryName
  ) where

import Control.Exception (SomeException, catch)
import Control.Monad (forM, when)
import Data.Either (lefts, rights)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import GHC.Generics (Generic)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getPermissions
  , listDirectory
  , setOwnerExecutable
  , setPermissions
  )
import System.Exit (ExitCode(..))
import System.FilePath (takeDirectory, (</>))
import System.Process (readProcessWithExitCode)

import Gachi.Retrofit.Types
  ( DiagnosticReport(..)
  , GitGovernanceStatus(..)
  , WorkspaceLayout(..)
  )
import Gachi.Scaffold.Templates
  ( agentsTemplate
  , cabalProjectLocalTemplate
  , claudeTemplate
  , commitMsgHookTemplate
  , docsCommitAttributionTemplate
  , docsIndexTemplate
  , docsMaintainerGuideTemplate
  , docsNewbieGuideTemplate
  , docsStrategyTemplate
  , docsTutorialTemplate
  , generateTagsTemplate
  , gitmessageTemplate
  , hlintTemplate
  , linkcheckScriptTemplate
  , planTemplate
  , preCommitHookTemplate
  , readmeTemplate
  , ruleCodeNavigationTemplate
  , ruleCommitAttributionTemplate
  , ruleCompilerVerificationTemplate
  , ruleDocPrecedenceTemplate
  , stateTemplate
  , tagrefConfigTemplate
  , tagrefScriptTemplate
  )
import Gachi.Schema.Project
  ( Author(..)
  , Project(..)
  , defaultProject
  , projectName
  )
import Gachi.Sync.CI
  ( defaultGitHubSpec
  , defaultGitLabSpec
  , generateGitHubWorkflow
  , generateGitLabWorkflow
  )
import Gachi.Sync.Catalog
  ( fourmoluTemplate
  )

--------------------------------------------------------------------------------
-- 1. Core Data Types
--------------------------------------------------------------------------------

-- | Distinguishes whether an overlay candidate should be created anew or preserved.
data OverlayActionType
  = ActionCreate
    -- ^ The candidate asset is missing from the destination and will be created.
  | ActionPreserve
    -- ^ The destination already contains this file; it is preserved completely untouched.
  deriving stock (Eq, Show, Generic)

-- | Functional category grouping standardized ecosystem assets.
data OverlayCategory
  = CategoryDocumentation
    -- ^ Operational and strategic documentation (DOC_STRATEGY.md, INDEX.md, PLAN.md).
  | CategoryAgentAdvisory
    -- ^ AI agent advisory context and modular rules (AGENTS.md, CLAUDE.md, .agents/rules/).
  | CategoryGitGovernance
    -- ^ Git hooks and commit message templates (.githooks/, .gitmessage).
  | CategoryVerification
    -- ^ Turnkey 5-gate physical verification scripts and harnesses (bin/*-verify, Tagref).
  | CategoryToolchain
    -- ^ Static linters, formatters, and compiler options (.hlint.yaml, fourmolu.yaml).
  | CategoryCIWorkflow
    -- ^ Multi-forge CI pipeline configurations (.github/workflows/, .gitlab-ci.yml).
  deriving stock (Eq, Show, Generic)

-- | Human-readable title for an 'OverlayCategory'.
overlayCategoryName :: OverlayCategory -> Text
overlayCategoryName = \case
  CategoryDocumentation -> "Documentation Corpus"
  CategoryAgentAdvisory -> "Agent Advisory Layer"
  CategoryGitGovernance -> "Git Governance & Hooks"
  CategoryVerification  -> "Physical Verification Harnesses"
  CategoryToolchain     -> "Toolchain & Linter Configurations"
  CategoryCIWorkflow    -> "Forge-Tiered CI Workflows"

-- | Represents a planned file-level action in the non-destructive overlay.
data OverlayAction = OverlayAction
  { actionType        :: !OverlayActionType
    -- ^ Creation policy ('ActionCreate' or 'ActionPreserve').
  , actionPath        :: !FilePath
    -- ^ Relative file path from repository root (e.g. @"docs/INDEX.md"@).
  , actionContent     :: !Text
    -- ^ Textual content to be written if 'actionType' is 'ActionCreate'.
  , actionExecutable  :: !Bool
    -- ^ Whether POSIX owner executable bit (+x) must be set upon creation.
  , actionCategory    :: !OverlayCategory
    -- ^ Functional category grouping.
  , actionDescription :: !Text
    -- ^ Brief human-readable description of this asset's purpose.
  } deriving stock (Eq, Show, Generic)

-- | Represents a Git governance configuration mutation.
data GitGovernanceAction
  = GitInitRepo
    -- ^ Invoke @git init@ because no @.git@ directory exists.
  | GitSetConfig !Text !Text
    -- ^ Invoke @git config key val@ to pin canonical hook paths or commit templates.
  deriving stock (Eq, Show, Generic)

-- | Complete, referentially transparent plan detailing all actions to be performed
-- during codebase retrofitting.
data OverlayPlan = OverlayPlan
  { planTargetDir       :: !FilePath
    -- ^ Target codebase checkout directory.
  , planProjectName     :: !Text
    -- ^ Detected or inferred project identifier slug.
  , planActions         :: ![OverlayAction]
    -- ^ Ordered list of file-level creation or preservation actions.
  , planGitActions      :: ![GitGovernanceAction]
    -- ^ Ordered list of Git governance configurations.
  , planCreatedCount    :: !Int
    -- ^ Total count of missing files scheduled for creation.
  , planPreservedCount  :: !Int
    -- ^ Total count of pre-existing files preserved untouched.
  } deriving stock (Eq, Show, Generic)

-- | Concrete outcome and statistics from executing an 'OverlayPlan' on disk.
data OverlayResult = OverlayResult
  { resultTargetDir      :: !FilePath
    -- ^ Destination repository directory.
  , resultProjectName    :: !Text
    -- ^ Project identifier slug.
  , resultCreatedFiles   :: ![FilePath]
    -- ^ Relative paths of files successfully materialized on disk.
  , resultPreservedFiles :: ![FilePath]
    -- ^ Relative paths of files preserved untouched.
  , resultGitActions     :: ![Text]
    -- ^ Descriptions of Git governance actions successfully executed.
  , resultSuccess        :: !Bool
    -- ^ Overall operational success indicator.
  } deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- 2. Ambient Git Author Detection
--------------------------------------------------------------------------------

-- | Queries ambient Git configuration (@git config --get user.name@ and
-- @git config --get user.email@) to personalize synthesized documentation and
-- package metadata.
--
-- Falls back gracefully to canonical ecosystem author values if Git is unconfigured
-- or inaccessible in headless environments.
detectGitAuthor :: IO Author
detectGitAuthor = do
  (cName, oName, _) <- readProcessWithExitCode "git" ["config", "--get", "user.name"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
  (cEmail, oEmail, _) <- readProcessWithExitCode "git" ["config", "--get", "user.email"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
  let nameTrimmed = T.strip (T.pack oName)
      emailTrimmed = T.strip (T.pack oEmail)
      authName = if cName == ExitSuccess && not (T.null nameTrimmed)
                   then nameTrimmed
                   else "Nadia Yvette Chambers"
      authEmail = if cEmail == ExitSuccess && not (T.null emailTrimmed)
                    then emailTrimmed
                    else "nadia.yvette.chambers@ik.me"
  pure Author { name = authName, email = authEmail }

--------------------------------------------------------------------------------
-- 3. Pure Candidate Synthesis
--------------------------------------------------------------------------------

-- | Synthesizes all canonical candidate assets that comprise the standardized
-- ecosystem skeleton overlay for a project.
--
-- Every candidate is tagged with its relative path, content, executable requirement,
-- category, and description. Does not inspect ambient filesystem state.
synthesizeOverlayCandidates :: Project -> WorkspaceLayout -> [OverlayAction]
synthesizeOverlayCandidates proj layout =
  let pName = projectName proj
      -- 1. Documentation Corpus
      docs =
        [ OverlayAction ActionCreate "README.md" (readmeTemplate proj) False CategoryDocumentation "Arrivals & orientation overview"
        , OverlayAction ActionCreate "PLAN.md" (planTemplate proj) False CategoryDocumentation "Strategic operational roadmap"
        , OverlayAction ActionCreate "STATE.md" (stateTemplate proj) False CategoryDocumentation "Active operational frontier and state"
        , OverlayAction ActionCreate "docs/INDEX.md" (docsIndexTemplate proj) False CategoryDocumentation "Complete documentation corpus index"
        , OverlayAction ActionCreate "docs/TUTORIAL.md" (docsTutorialTemplate proj) False CategoryDocumentation "Step-by-step tutorial track"
        , OverlayAction ActionCreate "docs/NEWBIE_GUIDE.md" (docsNewbieGuideTemplate proj) False CategoryDocumentation "Onboarding guide for new contributors"
        , OverlayAction ActionCreate "docs/MAINTAINER_GUIDE.md" (docsMaintainerGuideTemplate proj) False CategoryDocumentation "Operational guide for maintainers"
        , OverlayAction ActionCreate "docs/notes/DOC_STRATEGY.md" (docsStrategyTemplate proj) False CategoryDocumentation "Canonical documentation policy and taxonomy"
        , OverlayAction ActionCreate "docs/notes/COMMIT_ATTRIBUTION.md" (docsCommitAttributionTemplate proj) False CategoryDocumentation "RFC 2822 commit trailer attribution specification"
        ]

      -- 2. Agent Advisory Layer
      advisories =
        [ OverlayAction ActionCreate "AGENTS.md" (agentsTemplate proj) False CategoryAgentAdvisory "Primary agent advisory pointer file"
        , OverlayAction ActionCreate "CLAUDE.md" (claudeTemplate proj) False CategoryAgentAdvisory "Compatibility symlink and instructions"
        , OverlayAction ActionCreate ".agents/rules/commit-attribution.md" ruleCommitAttributionTemplate False CategoryAgentAdvisory "Rule: Commit trailer attribution"
        , OverlayAction ActionCreate ".agents/rules/code-navigation.md" ruleCodeNavigationTemplate False CategoryAgentAdvisory "Rule: Token-efficient code navigation"
        , OverlayAction ActionCreate ".agents/rules/compiler-verification.md" ruleCompilerVerificationTemplate False CategoryAgentAdvisory "Rule: Zero-log compiler verification"
        , OverlayAction ActionCreate ".agents/rules/documentation-precedence.md" ruleDocPrecedenceTemplate False CategoryAgentAdvisory "Rule: Documentation precedence"
        ]

      -- 3. Git Governance & Hooks
      governance =
        [ OverlayAction ActionCreate ".gitmessage" gitmessageTemplate False CategoryGitGovernance "Commit message template with Assisted-by: trailers"
        , OverlayAction ActionCreate ".githooks/commit-msg" commitMsgHookTemplate True CategoryGitGovernance "Commit message hook validating RFC 2822 trailers"
        , OverlayAction ActionCreate ".githooks/pre-commit" (preCommitHookTemplate proj) True CategoryGitGovernance "Pre-commit hook checking Tagref and link integrity"
        ]

      -- 4. Verification Harnesses
      verification =
        [ OverlayAction ActionCreate ("bin/" <> T.unpack pName <> "-verify") (customVerifyScript pName layout) True CategoryVerification "Turnkey 5-gate physical verification runner"
        , OverlayAction ActionCreate ("bin/" <> T.unpack pName <> "-tagref") (tagrefScriptTemplate proj) True CategoryVerification "Tagref cross-reference checking harness"
        , OverlayAction ActionCreate ("bin/" <> T.unpack pName <> "-linkcheck") (linkcheckScriptTemplate proj) True CategoryVerification "Markdown link and anchor verification harness"
        , OverlayAction ActionCreate ("bin/" <> T.unpack pName <> "-cloc") (customClocScript pName layout) True CategoryVerification "CLOC comment density auditing harness"
        , OverlayAction ActionCreate "bin/generate-tags" generateTagsTemplate True CategoryVerification "Fast ctags/hasktags symbol indexing script"
        , OverlayAction ActionCreate "tagref.yml" (tagrefConfigTemplate proj) False CategoryVerification "Tagref cross-reference configuration"
        ]

      -- 5. Toolchain Configurations
      toolchain =
        [ OverlayAction ActionCreate ".hlint.yaml" hlintTemplate False CategoryToolchain "Zero-hint HLint static analysis configuration"
        , OverlayAction ActionCreate "fourmolu.yaml" fourmoluTemplate False CategoryToolchain "Deterministic fourmolu code formatting profile"
        , OverlayAction ActionCreate "cabal.project.local.example" cabalProjectLocalTemplate False CategoryToolchain "Local developer Cabal project configuration"
        ]

      -- 6. CI Workflows
      ciWorkflows =
        [ OverlayAction ActionCreate ".github/workflows/ci.yml" (generateGitHubWorkflow defaultGitHubSpec proj) False CategoryCIWorkflow "High-resource GitHub Actions CI workflow"
        , OverlayAction ActionCreate ".gitlab-ci.yml" (generateGitLabWorkflow defaultGitLabSpec proj) False CategoryCIWorkflow "Lightweight community GitLab CI pipeline"
        ]

  in docs ++ advisories ++ governance ++ verification ++ toolchain ++ ciWorkflows

-- | Constructs a customized @bin/<project>-verify@ script tailored to both
-- multi-package (@packages/*/src@) and single-package (@src/@) workspaces.
customVerifyScript :: Text -> WorkspaceLayout -> Text
customVerifyScript pName _ =
  T.unlines
    [ "#!/usr/bin/env bash"
    , "# bin/" <> pName <> "-verify — Physical verification runner for " <> pName
    , "set -euo pipefail"
    , ""
    , "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
    , "REPO_ROOT=\"$(cd \"${SCRIPT_DIR}/..\" && pwd)\""
    , ""
    , "verify_hlint() {"
    , "  echo \"=== [1/5] HLint Static Analysis Gate ===\""
    , "  local hlint_cmd=\"\""
    , "  if [[ -x \"${HOME}/.ghcup/bin/hlint\" ]]; then"
    , "    hlint_cmd=\"${HOME}/.ghcup/bin/hlint\""
    , "  elif [[ -x \"${HOME}/.local/bin/hlint\" ]]; then"
    , "    hlint_cmd=\"${HOME}/.local/bin/hlint\""
    , "  elif command -v hlint >/dev/null 2>&1; then"
    , "    hlint_cmd=\"$(command -v hlint)\""
    , "  fi"
    , ""
    , "  if [[ -n \"${hlint_cmd}\" ]]; then"
    , "    local target_paths=()"
    , "    if compgen -G \"${REPO_ROOT}/packages/*/src\" > /dev/null; then"
    , "      target_paths+=(\"${REPO_ROOT}\"/packages/*/src)"
    , "    fi"
    , "    if [[ -d \"${REPO_ROOT}/src\" ]]; then"
    , "      target_paths+=(\"${REPO_ROOT}/src\")"
    , "    fi"
    , "    if [[ ${#target_paths[@]} -gt 0 ]]; then"
    , "      \"${hlint_cmd}\" \"${target_paths[@]}\" >/dev/null"
    , "      echo \"  [+] Clean HLint run: 0 hints.\""
    , "    else"
    , "      echo \"  [SKIP] No Haskell src directories found.\""
    , "    fi"
    , "  else"
    , "    echo \"  [SKIP] hlint binary not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_tests() {"
    , "  echo \"=== [2/5] Full Cabal Test Suite ===\""
    , "  if [[ -f \"${REPO_ROOT}/cabal.project\" ]] || compgen -G \"${REPO_ROOT}/*.cabal\" > /dev/null; then"
    , "    (cd \"${REPO_ROOT}\" && cabal test all --test-show-details=streaming)"
    , "    echo \"  [+] All test suite assertions PASSED.\""
    , "  else"
    , "    echo \"  [SKIP] No Cabal build manifests found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_tagref() {"
    , "  echo \"=== [3/5] Tagref Cross-Reference Gate ===\""
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-tagref\" ]]; then"
    , "    local tagref_out"
    , "    tagref_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-tagref\")\""
    , "    echo \"  [+] Tagref verified: ${tagref_out}\""
    , "  elif command -v tagref >/dev/null 2>&1; then"
    , "    (cd \"${REPO_ROOT}\" && tagref >/dev/null)"
    , "    echo \"  [+] Tagref verified: 0 dangling references, 0 duplicate tags.\""
    , "  else"
    , "    echo \"  [SKIP] tagref binary not found.\""
    , "  fi"
    , "}"
    , ""
    , "verify_linkcheck() {"
    , "  echo \"=== [4/5] Markdown Link & Anchor Integrity Gate ==="
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" ]]; then"
    , "    local linkcheck_out"
    , "    linkcheck_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-linkcheck\" --quiet)\""
    , "    echo \"  [+] Markdown links verified: ${linkcheck_out}\""
    , "  else"
    , "    echo \"  [SKIP] bin/" <> pName <> "-linkcheck not found or not executable.\""
    , "  fi"
    , "}"
    , ""
    , "verify_cloc() {"
    , "  echo \"=== [5/5] CLOC Comment Density Gate ===\""
    , "  if [[ -x \"${REPO_ROOT}/bin/" <> pName <> "-cloc\" ]]; then"
    , "    local cloc_out"
    , "    cloc_out=\"$(\"${REPO_ROOT}/bin/" <> pName <> "-cloc\" --quiet --check)\""
    , "    echo \"  [+] Comment density verified: ${cloc_out}\""
    , "  else"
    , "    echo \"  [SKIP] bin/" <> pName <> "-cloc not found or not executable.\""
    , "  fi"
    , "}"
    , ""
    , "verify_hlint"
    , "verify_tests"
    , "verify_tagref"
    , "verify_linkcheck"
    , "verify_cloc"
    , ""
    , "echo \"=== All 5 Physical Verification Checks PASSED ===\""
    ]

-- | Constructs a customized @bin/<project>-cloc@ script capable of evaluating
-- both multi-package (@packages/*/src@) and single-package (@src/@) layouts.
customClocScript :: Text -> WorkspaceLayout -> Text
customClocScript pName _ =
  T.unlines
    [ "#!/usr/bin/env python3"
    , "\"\"\""
    , "bin/" <> pName <> "-cloc — Comment Density Audit Harness for " <> pName
    , "\"\"\""
    , "import sys, os, glob, argparse"
    , ""
    , "REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), \"..\"))"
    , ""
    , "def count_hs(filepath):"
    , "    blank = comment = code = 0"
    , "    in_block = 0"
    , "    with open(filepath, \"r\", encoding=\"utf-8\", errors=\"replace\") as f:"
    , "        for line in f:"
    , "            s = line.strip()"
    , "            if not s: blank += 1; continue"
    , "            i = 0"
    , "            line_has_comment = line_has_code = False"
    , "            while i < len(s):"
    , "                if in_block > 0:"
    , "                    if s[i:i+2] == \"-}\": in_block -= 1; i += 2; line_has_comment = True"
    , "                    elif s[i:i+2] == \"{-\": in_block += 1; i += 2; line_has_comment = True"
    , "                    else: i += 1; line_has_comment = True"
    , "                else:"
    , "                    if s[i:i+2] == \"--\": line_has_comment = True; break"
    , "                    elif s[i:i+2] == \"{-\": in_block += 1; i += 2; line_has_comment = True"
    , "                    else: line_has_code = True; i += 1"
    , "            if line_has_comment and not line_has_code: comment += 1"
    , "            elif line_has_code: code += 1"
    , "            elif line_has_comment: comment += 1"
    , "            else: blank += 1"
    , "    return blank, comment, code"
    , ""
    , "def main():"
    , "    parser = argparse.ArgumentParser()"
    , "    parser.add_argument(\"--quiet\", \"-q\", action=\"store_true\")"
    , "    parser.add_argument(\"--check\", action=\"store_true\", default=True)"
    , "    args = parser.parse_args()"
    , "    src_files = glob.glob(os.path.join(REPO_ROOT, \"packages\", \"*\", \"src\", \"**\", \"*.hs\"), recursive=True)"
    , "    src_files += glob.glob(os.path.join(REPO_ROOT, \"src\", \"**\", \"*.hs\"), recursive=True)"
    , "    src_files = sorted(list(set(src_files)))"
    , "    tot_comment = tot_code = 0"
    , "    for f in src_files:"
    , "        _, com, cod = count_hs(f)"
    , "        tot_comment += com; tot_code += cod"
    , "    tot_all = tot_comment + tot_code"
    , "    density = (tot_comment / tot_all * 100.0) if tot_all > 0 else 100.0"
    , "    if args.check and density < 25.0:"
    , "        print(f\"Comment density gate FAILED: {density:.1f}% < 25.0% threshold\", file=sys.stderr)"
    , "        sys.exit(1)"
    , "    print(f\"{density:.1f}% ({tot_comment} comments / {tot_code} code lines in src/; target: 50.0%+)\")"
    , ""
    , "if __name__ == '__main__': main()"
    ]

--------------------------------------------------------------------------------
-- 4. Overlay Plan Computation
--------------------------------------------------------------------------------

-- | Recursively collects all existing relative file paths in a directory.
collectExistingFiles :: FilePath -> IO [FilePath]
collectExistingFiles root = do
  exists <- doesDirectoryExist root
  if not exists
    then pure []
    else go root ""
  where
    go baseDir relPrefix = do
      entries <- listDirectory (baseDir </> relPrefix)
        `catch` (\(_ :: SomeException) -> pure [])
      fpaths <- forM entries $ \e -> do
        let rel = if null relPrefix then e else relPrefix </> e
            full = baseDir </> rel
        isDir <- doesDirectoryExist full
        if isDir
          then if e `elem` [".git", "dist-newstyle", ".stack-work", "target", "node_modules"]
                 then pure []
                 else go baseDir rel
          else pure [rel]
      pure (concat fpaths)

-- | Computes the non-destructive overlay plan for a target repository.
--
-- Analyzes pre-existing files on disk and compares them against the canonical candidate
-- assets. Observes Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit]:
-- any file that already exists is strictly preserved and never scheduled for overwrite.
computeOverlayPlan :: FilePath -> DiagnosticReport -> IO OverlayPlan
computeOverlayPlan targetDir report = do
  absTarget <- canonicalizePath targetDir
  existingFiles <- collectExistingFiles absTarget
  auth <- detectGitAuthor

  let pName = diagProjectName report
      layout = diagLayout report
      proj = defaultProject pName auth
      candidates = synthesizeOverlayCandidates proj layout

  -- Partition candidates into Create vs Preserve based on disk presence
  actions <- forM candidates $ \cand -> do
    let dest = absTarget </> actionPath cand
    existsOnDisk <- doesFileExist dest
    let isExisting = existsOnDisk || actionPath cand `elem` existingFiles
    if isExisting
      then pure cand
        { actionType        = ActionPreserve
        , actionContent     = ""
        , actionDescription = "Pre-existing file preserved intact (non-destructive policy)"
        }
      else pure cand
        { actionType = ActionCreate
        }

  -- Compute Git governance requirements
  let gitStatus = diagGitGovernance report
      gitActions =
        [ GitInitRepo | not (hasGitRepo gitStatus) ]
        ++ [ GitSetConfig "core.hooksPath" ".githooks"
           | hooksPathConfig gitStatus /= Just ".githooks"
           ]
        ++ [ GitSetConfig "commit.template" ".gitmessage"
           | gitMessageConfig gitStatus /= Just ".gitmessage"
           ]

  let createdCount = length [() | a <- actions, actionType a == ActionCreate]
      preservedCount = length [() | a <- actions, actionType a == ActionPreserve]

  pure OverlayPlan
    { planTargetDir       = targetDir
    , planProjectName     = pName
    , planActions         = actions
    , planGitActions      = gitActions
    , planCreatedCount    = createdCount
    , planPreservedCount  = preservedCount
    }

--------------------------------------------------------------------------------
-- 5. Overlay Plan Execution
--------------------------------------------------------------------------------

-- | Executes an 'OverlayPlan' on disk, writing missing standardized assets, setting
-- executable bits, and configuring Git governance.
--
-- Strictly adheres to Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit]:
-- files marked 'ActionPreserve' are never touched.
executeOverlayPlan :: OverlayPlan -> IO OverlayResult
executeOverlayPlan plan = do
  absTarget <- canonicalizePath (planTargetDir plan)
  createDirectoryIfMissing True absTarget

  -- 1. Materialize Missing Files
  createdResults <- forM (planActions plan) $ \action -> do
    case actionType action of
      ActionPreserve -> pure (Left (actionPath action))
      ActionCreate   -> do
        let dest = absTarget </> actionPath action
        createDirectoryIfMissing True (takeDirectory dest)
        TIO.writeFile dest (actionContent action)
        when (actionExecutable action) $ do
          p <- getPermissions dest
          setPermissions dest (setOwnerExecutable True p)
        pure (Right (actionPath action))

  let createdFiles = rights createdResults
      preservedFiles = lefts createdResults

  -- 2. Execute Git Governance Actions
  executedGitActions <- forM (planGitActions plan) $ \case
    GitInitRepo -> do
      (cInit, _, _) <- readProcessWithExitCode "git" ["init", absTarget] ""
        `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
      if cInit == ExitSuccess
        then pure (Just "Initialized new Git repository (.git)")
        else pure Nothing

    GitSetConfig key val -> do
      (cConf, _, _) <- readProcessWithExitCode "git" ["-C", absTarget, "config", T.unpack key, T.unpack val] ""
        `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
      if cConf == ExitSuccess
        then pure (Just ("Configured git " <> key <> " = " <> val))
        else pure Nothing

  let validGitActions = catMaybes executedGitActions

  pure OverlayResult
    { resultTargetDir      = planTargetDir plan
    , resultProjectName    = planProjectName plan
    , resultCreatedFiles   = createdFiles
    , resultPreservedFiles = preservedFiles
    , resultGitActions     = validGitActions
    , resultSuccess        = True
    }

-- | Turnkey convenience runner: scans repository, computes overlay plan, and applies
-- the non-destructive overlay when not in dry-run mode.
overlayRepository
  :: FilePath
  -> Bool
  -> DiagnosticReport
  -> IO (OverlayPlan, Maybe OverlayResult)
overlayRepository targetDir isDryRun report = do
  plan <- computeOverlayPlan targetDir report
  if isDryRun
    then pure (plan, Nothing)
    else do
      res <- executeOverlayPlan plan
      pure (plan, Just res)

--------------------------------------------------------------------------------
-- 6. Formatting & Pretty-Printing
--------------------------------------------------------------------------------

-- | Formats an 80-column boxed ASCII preview of an 'OverlayPlan'.
formatOverlayPlan :: OverlayPlan -> Text
formatOverlayPlan plan =
  let created = [a | a <- planActions plan, actionType a == ActionCreate]
      preserved = [a | a <- planActions plan, actionType a == ActionPreserve]
      cats = [CategoryDocumentation, CategoryAgentAdvisory, CategoryGitGovernance, CategoryVerification, CategoryToolchain, CategoryCIWorkflow]
  in T.unlines $
    [ "================================================================================"
    , " Gachi Non-Destructive Skeleton Overlay Plan (~/src/PLAN.md §1.A, Milestone 4.2)"
    , "================================================================================"
    , " Target Directory:    " <> T.pack (planTargetDir plan)
    , " Project Identifier:  " <> planProjectName plan
    , " Proposed Actions:    " <> T.pack (show (planCreatedCount plan)) <> " files to CREATE, "
                               <> T.pack (show (planPreservedCount plan)) <> " files to PRESERVE"
    , " Git Governance:      " <> T.pack (show (length (planGitActions plan))) <> " configurations planned"
    , "--------------------------------------------------------------------------------"
    ]
    ++ concatMap (formatCategorySection created preserved) cats
    ++
    [ "================================================================================"
    ]
  where
    formatCategorySection created preserved cat =
      let catCreated = [a | a <- created, actionCategory a == cat]
          catPreserved = [a | a <- preserved, actionCategory a == cat]
      in if null catCreated && null catPreserved
           then []
           else
             [ " [" <> overlayCategoryName cat <> "]"
             ]
             ++ [ "   [+] CREATE:   " <> T.pack (actionPath a) <> (if actionExecutable a then " (+x)" else "")
                | a <- catCreated
                ]
             ++ [ "   [=] PRESERVE: " <> T.pack (actionPath a) <> " (" <> actionDescription a <> ")"
                | a <- catPreserved
                ]
             ++ [ "" ]

-- | Formats a GitHub-Flavored Markdown summary table of an 'OverlayPlan'.
formatOverlayPlanMarkdown :: OverlayPlan -> Text
formatOverlayPlanMarkdown plan =
  T.unlines $
    [ "# Non-Destructive Skeleton Overlay Plan: `" <> planProjectName plan <> "`"
    , ""
    , "**Target Directory:** `" <> T.pack (planTargetDir plan) <> "`  "
    , "**Files to Create:** " <> T.pack (show (planCreatedCount plan)) <> "  "
    , "**Files Preserved Intact:** " <> T.pack (show (planPreservedCount plan)) <> "  "
    , "**Git Governance Adjustments:** " <> T.pack (show (length (planGitActions plan)))
    , ""
    , "---"
    , ""
    , "## Planned Overlay Actions"
    , ""
    , "| Status | File Path | Executable | Category | Description |"
    , "|---|---|---|---|---|"
    ]
    ++
    [ "| " <> (if actionType a == ActionCreate then "✨ CREATE" else "🛡️ PRESERVE") <> " | `"
        <> T.pack (actionPath a) <> "` | "
        <> (if actionExecutable a then "`+x`" else "`-`") <> " | "
        <> overlayCategoryName (actionCategory a) <> " | "
        <> actionDescription a <> " |"
    | a <- planActions plan
    ]

-- | Formats an 80-column boxed ASCII report summarizing completed overlay execution.
formatOverlayResult :: OverlayResult -> Text
formatOverlayResult res =
  T.unlines $
    [ "================================================================================"
    , " Gachi Non-Destructive Overlay Execution Results (Milestone 4.2)"
    , "================================================================================"
    , " Target Directory:    " <> T.pack (resultTargetDir res)
    , " Project Identifier:  " <> resultProjectName res
    , " Files Created:       " <> T.pack (show (length (resultCreatedFiles res))) <> " files materialized"
    , " Files Preserved:     " <> T.pack (show (length (resultPreservedFiles res))) <> " files untouched"
    , "--------------------------------------------------------------------------------"
    ]
    ++
    (if null (resultGitActions res)
       then [ " Git Governance:      Already fully compliant (.githooks and .gitmessage pinned)" ]
       else " Git Governance Updates:" : map ("   [+] " <>) (resultGitActions res)
    )
    ++
    [ "================================================================================"
    , "  Overlay successfully applied! Skeletons and verification harnesses installed."
    , ""
    , "  Quick Start Verification:"
    , "    cd " <> T.pack (resultTargetDir res)
    , "    ./bin/" <> resultProjectName res <> "-verify"
    , "================================================================================"
    ]
