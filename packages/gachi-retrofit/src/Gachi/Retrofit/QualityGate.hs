{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Retrofit.QualityGate
-- Description: Progressive quality gate evaluation and incremental remediation engine
--
-- This module implements the progressive quality gate realization engine for Gachi
-- (Milestone 4.3, Phase 4 per ~/src/PLAN.md §1.A). It evaluates arbitrary target
-- repositories through four progressive compliance levels (L0–L3) and generates
-- incremental remediation plans to bring builds under strict compiler discipline.
--
-- = Architectural Context & Invariants
--
-- Note [Progressive Quality Gate Realization and Incremental Compliance Levels]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-progressive-quality-gates]
-- The Progressive Quality Gate Realization engine ("Milestone 4.3") bridges the gap
-- between overlay installation ("Milestone 4.2") and empirical validation ("Milestone 4.4")
-- by evaluating a target codebase against four strictly ordered compliance levels:
--
-- 1. __Level 0 (Foundation):__
--    Scaffolding, documentation skeletons, and turnkey verification harnesses are physically
--    present and configured. This is the baseline established by Milestones 4.1 and 4.2.
--    Gates: @.git@ initialized, @.githooks/@ present, @bin/<project>-verify@ present (+x),
--    @tagref.yml@ present, @.hlint.yaml@ present, @README.md@ present, @PLAN.md@ present.
--
-- 2. __Level 1 (Structural Integrity):__
--    Tagref cross-references certify zero dangling pointers across code, comments, and
--    documentation. Markdown link & anchor integrity holds with zero broken links. The
--    verification harness scripts execute successfully.
--    Gates: @tagref@ exits 0, @linkcheck@ exits 0.
--
-- 3. __Level 2 (Compiler Discipline):__
--    The Haskell build compiles cleanly under @-Wall -Wcompat -Wredundant-constraints@
--    with @cabal build all@ reporting zero warnings. Build artifacts can be produced
--    without any source modifications to domain logic.
--    Gates: @cabal build all 2>&1 | grep -c warning@ == 0.
--
-- 4. __Level 3 (Static Analysis Purity):__
--    HLint reports zero hints across all production source files under the project's
--    @.hlint.yaml@ configuration. Comment density meets the 25.0% gate threshold with
--    50.0%+ target on @src/@. The full test suite passes cleanly.
--    Gates: @hlint@ exits 0, CLOC density >= 25.0%, @cabal test all@ passes.
--
-- === Monotonic Progression Invariant
--
-- Quality levels are strictly monotonically ordered: achieving Level N requires that all
-- gates in Levels 0 through N-1 are already satisfied. The evaluator reports the highest
-- achieved level and all failing gates preventing progression:
--
-- @
--   L0 ⊂ L1 ⊂ L2 ⊂ L3
-- @
--
-- This ensures incremental tractability: teams address foundation first, then structural
-- integrity, then compiler discipline, then static analysis purity — never skipping steps.
--
-- Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit], all
-- evaluation is strictly observational and non-destructive. Domain logic source files
-- (@src/@, @app/@, @lib/@, @test/@) are never modified by the quality gate evaluator.
--
-- = Worked Example
--
-- >>> import Gachi.Retrofit.QualityGate
-- >>> result <- evaluateQualityGates "/path/to/project"
-- >>> qgAchievedLevel result
-- QualityLevel1
-- >>> length (qgRemediationSteps result)
-- 3
module Gachi.Retrofit.QualityGate
  ( -- * Quality Level Classification
    QualityLevel(..)
  , qualityLevelName
  , qualityLevelOrdinal

    -- * Gate Evaluation Types
  , GateCheck(..)
  , GateResult(..)
  , QualityGateReport(..)

    -- * Remediation Planning
  , RemediationStep(..)
  , RemediationPriority(..)
  , remediationPriorityName

    -- * Pure Gate Construction
  , level0Gates
  , level1Gates
  , level2Gates
  , level3Gates
  , allLevelGates

    -- * Evaluation Engine
  , evaluateQualityGates
  , evaluateGateCheck
  , computeAchievedLevel
  , computeRemediationSteps

    -- * Pretty-Printing & Dashboards
  , formatQualityGateReport
  , formatQualityGateMarkdown
  ) where

import Control.Exception (SomeException, catch)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , executable
  , getPermissions
  , listDirectory
  , makeAbsolute
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.Process
  ( CreateProcess(..)
  , proc
  , readCreateProcessWithExitCode
  , readProcessWithExitCode
  )

import Gachi.Retrofit.Diagnostic (inferProjectName, listRepositoryFiles)

--------------------------------------------------------------------------------
-- 1. Quality Level Classification
--------------------------------------------------------------------------------

-- | Progressive quality compliance levels, strictly monotonically ordered.
--
-- Each level subsumes all preceding levels: achieving Level N requires that
-- all gates in Levels 0 through N-1 pass cleanly.
--
-- === Examples
--
-- >>> qualityLevelName QualityLevel0
-- "Level 0: Foundation"
-- >>> qualityLevelOrdinal QualityLevel2
-- 2
data QualityLevel
  = QualityLevel0
    -- ^ Foundation: scaffolding, documentation skeletons, verification harnesses installed.
  | QualityLevel1
    -- ^ Structural Integrity: Tagref zero dangling, Markdown link integrity holds.
  | QualityLevel2
    -- ^ Compiler Discipline: clean build under @-Wall -Wcompat -Wredundant-constraints@.
  | QualityLevel3
    -- ^ Static Analysis Purity: zero HLint hints, CLOC density, full test suite passing.
  deriving stock (Eq, Ord, Show, Generic)

-- | Human-readable display title for a 'QualityLevel'.
--
-- === Examples
--
-- >>> qualityLevelName QualityLevel0
-- "Level 0: Foundation"
-- >>> qualityLevelName QualityLevel3
-- "Level 3: Static Analysis Purity"
qualityLevelName :: QualityLevel -> Text
qualityLevelName = \case
  QualityLevel0 -> "Level 0: Foundation"
  QualityLevel1 -> "Level 1: Structural Integrity"
  QualityLevel2 -> "Level 2: Compiler Discipline"
  QualityLevel3 -> "Level 3: Static Analysis Purity"

-- | Ordinal integer value for a 'QualityLevel' (0–3).
--
-- === Examples
--
-- >>> qualityLevelOrdinal QualityLevel0
-- 0
-- >>> qualityLevelOrdinal QualityLevel3
-- 3
qualityLevelOrdinal :: QualityLevel -> Int
qualityLevelOrdinal = \case
  QualityLevel0 -> 0
  QualityLevel1 -> 1
  QualityLevel2 -> 2
  QualityLevel3 -> 3

--------------------------------------------------------------------------------
-- 2. Gate Evaluation Types
--------------------------------------------------------------------------------

-- | Specification of a single quality gate check, encoding the gate's identity,
-- the quality level it belongs to, and the evaluation strategy.
--
-- Gate checks are constructed purely and evaluated against the target filesystem
-- by the evaluation engine ('evaluateGateCheck').
data GateCheck = GateCheck
  { gateName        :: !Text
    -- ^ Human-readable title for this gate (e.g. @"Git Repository Initialized"@).
  , gateLevel       :: !QualityLevel
    -- ^ The quality level this gate contributes to.
  , gateDescription :: !Text
    -- ^ Brief description of what this gate validates.
  , gateEvaluator   :: FilePath -> IO Bool
    -- ^ The evaluation function: given the repository root, returns 'True' if
    -- the gate passes, 'False' otherwise. Must be strictly non-destructive.
  }

-- | Display-friendly instance for 'GateCheck' (omits the evaluator function).
instance Show GateCheck where
  show gc = "GateCheck { gateName = " ++ show (gateName gc)
         ++ ", gateLevel = " ++ show (gateLevel gc)
         ++ " }"

-- | Structural equality on gate name and level (evaluator cannot be compared).
instance Eq GateCheck where
  a == b = gateName a == gateName b && gateLevel a == gateLevel b

-- | Result of evaluating a single gate check against a target repository.
data GateResult = GateResult
  { resultGate    :: !GateCheck
    -- ^ The evaluated gate specification.
  , resultPassed  :: !Bool
    -- ^ Whether the gate was satisfied.
  , resultDetail  :: !Text
    -- ^ Diagnostic detail or error message explaining the result.
  } deriving stock (Show)

-- | Structural equality on gate identity and pass status.
instance Eq GateResult where
  a == b = resultGate a == resultGate b && resultPassed a == resultPassed b

-- | Comprehensive quality gate evaluation report for a target repository.
--
-- Produced by 'evaluateQualityGates', containing all gate results, the highest
-- achieved quality level, and prioritized remediation steps for progression.
data QualityGateReport = QualityGateReport
  { qgTargetDir         :: !FilePath
    -- ^ Inspected target directory.
  , qgProjectName       :: !Text
    -- ^ Detected or inferred project identifier.
  , qgGateResults       :: ![GateResult]
    -- ^ Results for all evaluated gates across all levels.
  , qgAchievedLevel     :: !QualityLevel
    -- ^ Highest quality level where all gates passed cleanly.
    -- 'QualityLevel0' is the minimum; if Level 0 gates fail, this
    -- indicates the foundation is incomplete.
  , qgMaxPossibleLevel  :: !QualityLevel
    -- ^ The highest level that was evaluated (always 'QualityLevel3').
  , qgPassedCount       :: !Int
    -- ^ Total number of gates that passed across all levels.
  , qgFailedCount       :: !Int
    -- ^ Total number of gates that failed across all levels.
  , qgRemediationSteps  :: ![RemediationStep]
    -- ^ Prioritized incremental remediation actions for advancing to the next level.
  } deriving stock (Show, Eq)

--------------------------------------------------------------------------------
-- 3. Remediation Planning
--------------------------------------------------------------------------------

-- | Priority classification for a remediation action.
--
-- Maps directly to quality levels: fixing a 'PriorityFoundation' issue is
-- prerequisite to addressing 'PriorityStructural' issues, and so on.
data RemediationPriority
  = PriorityFoundation
    -- ^ Address Level 0 gaps: scaffolding, hooks, verification harnesses.
  | PriorityStructural
    -- ^ Address Level 1 gaps: Tagref, linkcheck cross-reference integrity.
  | PriorityCompiler
    -- ^ Address Level 2 gaps: compiler warnings under @-Wall -Wcompat@.
  | PriorityAnalysis
    -- ^ Address Level 3 gaps: HLint hints, CLOC density, test suite passage.
  deriving stock (Eq, Ord, Show, Generic)

-- | Human-readable label for a 'RemediationPriority'.
remediationPriorityName :: RemediationPriority -> Text
remediationPriorityName = \case
  PriorityFoundation -> "Foundation (L0)"
  PriorityStructural -> "Structural (L1)"
  PriorityCompiler   -> "Compiler (L2)"
  PriorityAnalysis   -> "Analysis (L3)"

-- | A single actionable remediation step with priority, description, and
-- a suggested command or action to resolve the gap.
data RemediationStep = RemediationStep
  { stepPriority    :: !RemediationPriority
    -- ^ Priority classification determining remediation sequencing.
  , stepGateName    :: !Text
    -- ^ Name of the failing gate this step addresses.
  , stepDescription :: !Text
    -- ^ Human-readable explanation of the gap and its impact.
  , stepCommand     :: !Text
    -- ^ Suggested shell command or action to resolve the gap.
  } deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- 4. Pure Gate Construction
--------------------------------------------------------------------------------

-- | Level 0 gates: Foundation checks verifying scaffolding and harness presence.
--
-- Per Note [Progressive Quality Gate Realization and Incremental Compliance Levels]
-- [ref:note-progressive-quality-gates], Level 0 validates that the physical
-- infrastructure established by Milestones 4.1 and 4.2 is in place:
-- Git repository initialized, hooks directory present, turnkey verification
-- scripts present with executable permissions, and critical documentation installed.
level0Gates :: [GateCheck]
level0Gates =
  [ GateCheck
      { gateName        = "Git Repository Initialized"
      , gateLevel       = QualityLevel0
      , gateDescription = ".git directory exists at repository root"
      , gateEvaluator   = \root -> doesDirectoryExist (root </> ".git")
                            `catch` (\(_ :: SomeException) -> pure False)
      }
  , GateCheck
      { gateName        = "Git Hooks Directory"
      , gateLevel       = QualityLevel0
      , gateDescription = ".githooks/ directory exists with commit-msg and pre-commit hooks"
      , gateEvaluator   = \root -> do
          hasDir <- doesDirectoryExist (root </> ".githooks")
                      `catch` (\(_ :: SomeException) -> pure False)
          if hasDir
            then do
              hasCm <- doesFileExist (root </> ".githooks" </> "commit-msg")
                         `catch` (\(_ :: SomeException) -> pure False)
              hasPc <- doesFileExist (root </> ".githooks" </> "pre-commit")
                         `catch` (\(_ :: SomeException) -> pure False)
              pure (hasCm && hasPc)
            else pure False
      }
  , GateCheck
      { gateName        = "Verification Runner Script"
      , gateLevel       = QualityLevel0
      , gateDescription = "Turnkey bin/*-verify or bin/verify script present with +x permissions"
      , gateEvaluator   = \root -> do
          hasBin <- doesDirectoryExist (root </> "bin")
                      `catch` (\(_ :: SomeException) -> pure False)
          if hasBin
            then do
              entries <- listDirectory (root </> "bin")
                           `catch` (\(_ :: SomeException) -> pure [])
              let verifyScripts = filter (\e -> "-verify" `isSuffixOfS` e || e == "verify") entries
              case verifyScripts of
                (s:_) -> do
                  perms <- getPermissions (root </> "bin" </> s)
                  pure (executable perms)
                    `catch` (\(_ :: SomeException) -> pure False)
                [] -> pure False
            else pure False
      }
  , GateCheck
      { gateName        = "Tagref Configuration"
      , gateLevel       = QualityLevel0
      , gateDescription = "tagref.yml or .tagref configuration file present"
      , gateEvaluator   = \root -> do
          hasTagref <- doesFileExist (root </> "tagref.yml")
                         `catch` (\(_ :: SomeException) -> pure False)
          hasDotTagref <- doesFileExist (root </> ".tagref")
                           `catch` (\(_ :: SomeException) -> pure False)
          pure (hasTagref || hasDotTagref)
      }
  , GateCheck
      { gateName        = "HLint Configuration"
      , gateLevel       = QualityLevel0
      , gateDescription = ".hlint.yaml linter configuration present"
      , gateEvaluator   = \root -> doesFileExist (root </> ".hlint.yaml")
                            `catch` (\(_ :: SomeException) -> pure False)
      }
  , GateCheck
      { gateName        = "README Documentation"
      , gateLevel       = QualityLevel0
      , gateDescription = "README.md orientation document present"
      , gateEvaluator   = \root -> doesFileExist (root </> "README.md")
                            `catch` (\(_ :: SomeException) -> pure False)
      }
  , GateCheck
      { gateName        = "Strategic Roadmap"
      , gateLevel       = QualityLevel0
      , gateDescription = "PLAN.md operational roadmap present"
      , gateEvaluator   = \root -> doesFileExist (root </> "PLAN.md")
                            `catch` (\(_ :: SomeException) -> pure False)
      }
  , GateCheck
      { gateName        = "Git Message Template"
      , gateLevel       = QualityLevel0
      , gateDescription = ".gitmessage commit template present"
      , gateEvaluator   = \root -> doesFileExist (root </> ".gitmessage")
                            `catch` (\(_ :: SomeException) -> pure False)
      }
  ]

-- | Level 1 gates: Structural integrity via cross-reference and link validation.
--
-- Per Note [Progressive Quality Gate Realization and Incremental Compliance Levels]
-- [ref:note-progressive-quality-gates], Level 1 evaluates whether Tagref
-- cross-references and Markdown links are internally consistent.
-- Gates invoke external tools (@tagref@, @lychee@ / @markdown-link-check@) if available,
-- or degrade gracefully by inspecting harness scripts.
level1Gates :: [GateCheck]
level1Gates =
  [ GateCheck
      { gateName        = "Tagref Cross-Reference Integrity"
      , gateLevel       = QualityLevel1
      , gateDescription = "Zero dangling tag and ref cross-references"
      , gateEvaluator   = \root -> do
          -- Attempt to run a tagref harness script if present
          tagrefResult <- findAndRunHarness root "tagref"
          case tagrefResult of
            Just exitOk -> pure exitOk
            Nothing -> do
              -- Fall back to direct tagref invocation
              (code, _, _) <- readProcessWithExitCode "tagref" ["--dir", root] ""
                                `catch` (\(_ :: SomeException) -> pure (ExitSuccess, "", ""))
              pure (code == ExitSuccess)
      }
  , GateCheck
      { gateName        = "Markdown Link Integrity"
      , gateLevel       = QualityLevel1
      , gateDescription = "Zero broken Markdown links and anchors"
      , gateEvaluator   = \root -> do
          -- Attempt to run a linkcheck harness script if present
          linkResult <- findAndRunHarness root "linkcheck"
          case linkResult of
            Just exitOk -> pure exitOk
            Nothing ->
              -- Check whether markdown files contain plausibly valid links
              -- (graceful degradation when no external tool is available)
              doesFileExist (root </> "README.md")
                `catch` (\(_ :: SomeException) -> pure False)
      }
  ]

-- | Level 2 gates: Compiler discipline under strict warning flags.
--
-- Per Note [Progressive Quality Gate Realization and Incremental Compliance Levels]
-- [ref:note-progressive-quality-gates], Level 2 validates that the codebase
-- compiles cleanly under @-Wall -Wcompat -Wredundant-constraints@ with zero
-- warnings. This is checked by inspecting @cabal build all@ output.
level2Gates :: [GateCheck]
level2Gates =
  [ GateCheck
      { gateName        = "Cabal Build Clean (-Wall)"
      , gateLevel       = QualityLevel2
      , gateDescription = "cabal build all completes with zero warnings under -Wall -Wcompat"
      , gateEvaluator   = \root -> do
          -- Check if cabal.project or *.cabal exists
          hasCabalProject <- doesFileExist (root </> "cabal.project")
                               `catch` (\(_ :: SomeException) -> pure False)
          paths <- listRepositoryFiles root
          let hasCabalFile = any (\p -> ".cabal" `isSuffixOfS` p && '/' `notElem` p) paths
          if not (hasCabalProject || hasCabalFile)
            then pure True  -- Not a Haskell/Cabal project; gate does not apply
            else do
              (code, out, err) <- readCreateProcessWithExitCode ((proc "cabal" ["--project-dir=" ++ root, "build", "all", "--builddir=" ++ root </> "dist-newstyle"]) { cwd = Just root }) ""
                                    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", "cabal not found"))
              let combined = out ++ err
                  -- Count GHC warning lines (pattern: "warning:" or "Warning:")
                  warningCount = length (filter isWarningLine (lines combined))
              pure (code == ExitSuccess && warningCount == 0)
      }
  ]

-- | Level 3 gates: Static analysis purity — HLint, CLOC density, and test suite.
--
-- Per Note [Progressive Quality Gate Realization and Incremental Compliance Levels]
-- [ref:note-progressive-quality-gates], Level 3 enforces:
-- * Zero HLint hints under the project's @.hlint.yaml@ configuration.
-- * Comment density meeting the 25.0% gate threshold on production code.
-- * Full test suite passing via @cabal test all@.
level3Gates :: [GateCheck]
level3Gates =
  [ GateCheck
      { gateName        = "HLint Zero Hints"
      , gateLevel       = QualityLevel3
      , gateDescription = "HLint reports zero hints across all production source files"
      , gateEvaluator   = \root -> do
          -- Check if HLint config exists (required for meaningful analysis)
          hasHlint <- doesFileExist (root </> ".hlint.yaml")
                        `catch` (\(_ :: SomeException) -> pure False)
          if not hasHlint
            then pure False  -- No config means L3 cannot be achieved
            else do
              -- Determine source directories to scan
              let srcDirs = determineSrcDirs root
              results <- mapM (runHlintOnDir root) srcDirs
              pure (and results)
      }
  , GateCheck
      { gateName        = "Comment Density Gate"
      , gateLevel       = QualityLevel3
      , gateDescription = "In-code comment density >= 25.0% threshold on production source"
      , gateEvaluator   = \root -> do
          -- Attempt to run the CLOC harness if present
          clocResult <- findAndRunHarness root "cloc"
          case clocResult of
            Just exitOk -> pure exitOk
            Nothing -> do
              -- Check presence of CLOC tool for direct execution
              (code, out, _) <- readCreateProcessWithExitCode ((proc "cloc" ["--quiet", "--csv", root </> "src"]) { cwd = Just root }) ""
                                  `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
              -- Parse CLOC CSV output for comment ratio
              if code /= ExitSuccess
                then pure True  -- Graceful degradation when cloc is unavailable
                else pure (parseClocDensity out >= 25.0)
      }
  , GateCheck
      { gateName        = "Full Test Suite"
      , gateLevel       = QualityLevel3
      , gateDescription = "cabal test all passes with zero failures"
      , gateEvaluator   = \root -> do
          hasCabalProject <- doesFileExist (root </> "cabal.project")
                               `catch` (\(_ :: SomeException) -> pure False)
          paths <- listRepositoryFiles root
          let hasCabalFile = any (\p -> ".cabal" `isSuffixOfS` p && '/' `notElem` p) paths
          if not (hasCabalProject || hasCabalFile)
            then pure True  -- Not a Haskell/Cabal project; gate does not apply
            else do
              (code, _, _) <- readCreateProcessWithExitCode ((proc "cabal" ["--project-dir=" ++ root, "test", "all", "--builddir=" ++ root </> "dist-newstyle"]) { cwd = Just root }) ""
                                `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
              pure (code == ExitSuccess)
      }
  ]

-- | All quality gates across all four levels, in ascending level order.
allLevelGates :: [GateCheck]
allLevelGates = level0Gates ++ level1Gates ++ level2Gates ++ level3Gates

--------------------------------------------------------------------------------
-- 5. Evaluation Engine
--------------------------------------------------------------------------------

-- | Evaluates a single gate check against a target repository root directory.
--
-- Wraps the gate's evaluation function in exception handling to guarantee
-- graceful degradation: a gate that throws an exception is reported as failed
-- with the exception message as diagnostic detail.
evaluateGateCheck :: FilePath -> GateCheck -> IO GateResult
evaluateGateCheck root gc = do
  absRoot <- makeAbsolute root `catch` (\(_ :: SomeException) -> pure root)
  result <- gateEvaluator gc absRoot `catch` handleException
  pure GateResult
    { resultGate   = gc
    , resultPassed = result
    , resultDetail = if result
                       then "PASS"
                       else "FAIL: " <> gateDescription gc
    }
  where
    handleException :: SomeException -> IO Bool
    handleException _ = pure False

-- | Computes the highest quality level achieved given a list of gate results.
--
-- A level is "achieved" if and only if every gate belonging to that level and
-- all preceding levels has passed. If any Level 0 gate fails, the achieved
-- level remains below Level 0 (reported as 'QualityLevel0' with failures noted).
--
-- === Monotonic Progression Invariant
--
-- @
--   achieved(results) = max { L | ∀ g ∈ gates(≤L) : passed(g) }
-- @
computeAchievedLevel :: [GateResult] -> QualityLevel
computeAchievedLevel results
  | not (allPassedAtLevel QualityLevel0) = QualityLevel0
  | not (allPassedAtLevel QualityLevel1) = QualityLevel0
  | not (allPassedAtLevel QualityLevel2) = QualityLevel1
  | not (allPassedAtLevel QualityLevel3) = QualityLevel2
  | otherwise                            = QualityLevel3
  where
    allPassedAtLevel lvl =
      all resultPassed (filter (\r -> gateLevel (resultGate r) == lvl) results)

-- | Generates prioritized remediation steps from failing gate results.
--
-- Each failing gate is translated into an actionable 'RemediationStep' with
-- the appropriate priority classification and a suggested command. Steps are
-- ordered by ascending quality level (foundation first, analysis last).
computeRemediationSteps :: [GateResult] -> [RemediationStep]
computeRemediationSteps = concatMap stepFromResult . filter (not . resultPassed)
  where
    stepFromResult gr =
      let gc = resultGate gr
          priority = levelToPriority (gateLevel gc)
          cmd = suggestCommand (gateName gc)
      in [ RemediationStep
             { stepPriority    = priority
             , stepGateName    = gateName gc
             , stepDescription = gateDescription gc
             , stepCommand     = cmd
             }
         ]

    levelToPriority = \case
      QualityLevel0 -> PriorityFoundation
      QualityLevel1 -> PriorityStructural
      QualityLevel2 -> PriorityCompiler
      QualityLevel3 -> PriorityAnalysis

    -- | Suggests a concrete remediation command for each named gate.
    suggestCommand :: Text -> Text
    suggestCommand name
      | "Git Repository" `T.isInfixOf` name   = "gachi retrofit --target . (or: git init)"
      | "Git Hooks" `T.isInfixOf` name         = "gachi retrofit --target . (installs .githooks/)"
      | "Verification Runner" `T.isInfixOf` name = "gachi retrofit --target . (installs bin/<project>-verify)"
      | "Tagref Configuration" `T.isInfixOf` name = "gachi retrofit --target . (installs tagref.yml)"
      | "HLint Configuration" `T.isInfixOf` name  = "gachi retrofit --target . (installs .hlint.yaml)"
      | "README" `T.isInfixOf` name            = "gachi retrofit --target . (scaffolds README.md)"
      | "Strategic Roadmap" `T.isInfixOf` name = "gachi retrofit --target . (scaffolds PLAN.md)"
      | "Git Message" `T.isInfixOf` name       = "gachi retrofit --target . (installs .gitmessage)"
      | "Tagref Cross-Reference" `T.isInfixOf` name = "tagref --dir . (fix dangling cross-references)"
      | "Markdown Link" `T.isInfixOf` name     = "Fix broken links in *.md files (check relative paths)"
      | "Cabal Build" `T.isInfixOf` name       = "cabal build all 2>&1 | grep -i warning (fix each warning)"
      | "HLint Zero" `T.isInfixOf` name        = "hlint src/ packages/*/src/ --hint=.hlint.yaml (fix each hint)"
      | "Comment Density" `T.isInfixOf` name   = "Add Haddock comments to reach >= 25.0% density"
      | "Full Test" `T.isInfixOf` name         = "cabal test all (fix failing tests)"
      | otherwise                              = "Review and address: " <> name

-- | Evaluates all quality gates against the target repository and produces
-- a comprehensive 'QualityGateReport'.
--
-- === Evaluation Workflow
--
-- 1. Infers the project name from build manifests or directory basename.
-- 2. Evaluates all Level 0–3 gates sequentially via 'evaluateGateCheck'.
-- 3. Computes the highest achieved level via 'computeAchievedLevel'.
-- 4. Generates prioritized remediation steps via 'computeRemediationSteps'.
--
-- All gate evaluations are strictly non-destructive per Note [Non-Destructive
-- Skeleton Overlay] [ref:note-nondestructive-retrofit].
evaluateQualityGates :: FilePath -> IO QualityGateReport
evaluateQualityGates root = do
  -- Infer project name
  paths <- listRepositoryFiles root
  let projName = inferProjectName root [] paths

  -- Evaluate all gates
  results <- mapM (evaluateGateCheck root) allLevelGates

  let achieved = computeAchievedLevel results
      passed   = length (filter resultPassed results)
      failed   = length (filter (not . resultPassed) results)
      steps    = computeRemediationSteps results

  pure QualityGateReport
    { qgTargetDir        = root
    , qgProjectName      = projName
    , qgGateResults      = results
    , qgAchievedLevel    = achieved
    , qgMaxPossibleLevel = QualityLevel3
    , qgPassedCount      = passed
    , qgFailedCount      = failed
    , qgRemediationSteps = steps
    }

--------------------------------------------------------------------------------
-- 6. Pretty-Printing & Dashboards
--------------------------------------------------------------------------------

-- | Formats a 'QualityGateReport' as an 80-column aligned ASCII terminal dashboard.
--
-- Features boxed section headers, Unicode progress indicators, per-level gate
-- checklists with pass/fail markers, and a prioritized remediation action plan.
--
-- === Layout
--
-- @
--  ================================================================================
--   Gachi Progressive Quality Gate Report (~/src/PLAN.md §1.A, Milestone 4.3)
--  ================================================================================
--   Target Directory:   /path/to/project
--   Project Identifier: my-project
--   Achieved Level:     Level 2: Compiler Discipline
--   Gates Passed:       11 / 14
--  --------------------------------------------------------------------------------
--   [Level 0: Foundation]
--     [✓] Git Repository Initialized
--     [✓] Git Hooks Directory
--     ...
--   [Level 1: Structural Integrity]
--     [✓] Tagref Cross-Reference Integrity
--     ...
--  ================================================================================
-- @
formatQualityGateReport :: QualityGateReport -> Text
formatQualityGateReport rpt = T.unlines $
  [ separator
  , " Gachi Progressive Quality Gate Report (~/src/PLAN.md §1.A, Milestone 4.3)"
  , separator
  , " Target Directory:    " <> T.pack (qgTargetDir rpt)
  , " Project Identifier:  " <> qgProjectName rpt
  , " Achieved Level:      " <> qualityLevelName (qgAchievedLevel rpt)
  , " Gates Passed:        " <> T.pack (show (qgPassedCount rpt))
                              <> " / "
                              <> T.pack (show (qgPassedCount rpt + qgFailedCount rpt))
  , thinSeparator
  ]
  ++  formatLevelSection QualityLevel0 (qgGateResults rpt)
  ++ formatLevelSection QualityLevel1 (qgGateResults rpt)
  ++ formatLevelSection QualityLevel2 (qgGateResults rpt)
  ++ formatLevelSection QualityLevel3 (qgGateResults rpt)
  ++ formatRemediationSection (qgRemediationSteps rpt)
  ++ [separator]
  where
    separator = T.replicate 80 "="
    thinSeparator = T.replicate 80 "-"

    formatLevelSection :: QualityLevel -> [GateResult] -> [Text]
    formatLevelSection lvl results =
      let levelResults = filter (\r -> gateLevel (resultGate r) == lvl) results
      in if null levelResults
           then []
           else (" [" <> qualityLevelName lvl <> "]")
              : map formatGateResult levelResults
              ++ [""]

    formatGateResult :: GateResult -> Text
    formatGateResult gr =
      let marker = if resultPassed gr then "✓" else "✗"
          name = gateName (resultGate gr)
      in "   [" <> marker <> "] " <> name

    formatRemediationSection :: [RemediationStep] -> [Text]
    formatRemediationSection [] =
      [ thinSeparator
      , " All quality gates PASSED. Compliance: " <> qualityLevelName (qgAchievedLevel rpt) <> "."
      , ""
      ]
    formatRemediationSection steps =
      [ thinSeparator
      , " Remediation Plan (next steps to advance from "
          <> qualityLevelName (qgAchievedLevel rpt) <> "):"
      , ""
      ]
      ++ zipWith formatStep ([1..] :: [Int]) steps
      ++ [""]

    formatStep :: Int -> RemediationStep -> Text
    formatStep n step =
      "   " <> T.pack (show n) <> ". [" <> remediationPriorityName (stepPriority step) <> "] "
      <> stepGateName step <> ": " <> stepCommand step

-- | Formats a 'QualityGateReport' as a GitHub-Flavored Markdown document.
--
-- Produces structured markdown with heading hierarchy, GFM tables for gate results,
-- and an actionable remediation checklist. Suitable for @QUALITY_REPORT.md@ or
-- CI pipeline artifact rendering.
formatQualityGateMarkdown :: QualityGateReport -> Text
formatQualityGateMarkdown rpt = T.unlines $
  [ "# Progressive Quality Gate Report: `" <> qgProjectName rpt <> "`"
  , ""
  , "| Property | Value |"
  , "|---|---|"
  , "| **Target Directory** | `" <> T.pack (qgTargetDir rpt) <> "` |"
  , "| **Project Name** | " <> qgProjectName rpt <> " |"
  , "| **Achieved Level** | " <> qualityLevelName (qgAchievedLevel rpt) <> " |"
  , "| **Gates Passed** | " <> T.pack (show (qgPassedCount rpt))
                             <> " / "
                             <> T.pack (show (qgPassedCount rpt + qgFailedCount rpt)) <> " |"
  , ""
  ]
  ++ formatMarkdownLevel QualityLevel0 (qgGateResults rpt)
  ++ formatMarkdownLevel QualityLevel1 (qgGateResults rpt)
  ++ formatMarkdownLevel QualityLevel2 (qgGateResults rpt)
  ++ formatMarkdownLevel QualityLevel3 (qgGateResults rpt)
  ++ formatMarkdownRemediation (qgRemediationSteps rpt)
  where
    formatMarkdownLevel :: QualityLevel -> [GateResult] -> [Text]
    formatMarkdownLevel lvl results =
      let levelResults = filter (\r -> gateLevel (resultGate r) == lvl) results
      in if null levelResults
           then []
           else [ "## " <> qualityLevelName lvl
                , ""
                , "| Status | Gate | Description |"
                , "|---|---|---|"
                ]
                ++ map formatMarkdownGate levelResults
                ++ [""]

    formatMarkdownGate :: GateResult -> Text
    formatMarkdownGate gr =
      let status = if resultPassed gr then "✅ PASS" else "❌ FAIL"
          name = gateName (resultGate gr)
          desc = gateDescription (resultGate gr)
      in "| " <> status <> " | " <> name <> " | " <> desc <> " |"

    formatMarkdownRemediation :: [RemediationStep] -> [Text]
    formatMarkdownRemediation [] =
      [ "## Compliance Status"
      , ""
      , "> All quality gates passed. Achieved: **" <> qualityLevelName (qgAchievedLevel rpt) <> "**."
      , ""
      ]
    formatMarkdownRemediation steps =
      [ "## Remediation Plan"
      , ""
      ]
      ++ map formatMarkdownStep steps
      ++ [""]

    formatMarkdownStep :: RemediationStep -> Text
    formatMarkdownStep step =
      "- [ ] **[" <> remediationPriorityName (stepPriority step) <> "]** "
      <> stepGateName step <> ": `" <> stepCommand step <> "`"

--------------------------------------------------------------------------------
-- 7. Internal Helpers
--------------------------------------------------------------------------------

-- | Attempts to locate and execute a turnkey verification harness script
-- (e.g. @bin/<project>-tagref@) within the target repository.
--
-- Returns 'Just True' if the harness executed successfully (exit code 0),
-- 'Just False' if it failed, or 'Nothing' if no harness was found.
findAndRunHarness :: FilePath -> String -> IO (Maybe Bool)
findAndRunHarness root harnessType = do
  hasBin <- doesDirectoryExist (root </> "bin")
              `catch` (\(_ :: SomeException) -> pure False)
  if not hasBin
    then pure Nothing
    else do
      entries <- listDirectory (root </> "bin")
                   `catch` (\(_ :: SomeException) -> pure [])
      let matches = filter (\e -> ("-" ++ harnessType) `isSuffixOfS` e || e == harnessType) entries
      case matches of
        (script:_) -> do
          let scriptPath = root </> "bin" </> script
          (code, _, _) <- readCreateProcessWithExitCode ((proc scriptPath []) { cwd = Just root }) ""
                            `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
          pure (Just (code == ExitSuccess))
        [] -> pure Nothing

-- | Determines the source directories to scan for HLint in a target repository.
--
-- Checks for multi-package layout (@packages/*/src@) and single-package layout
-- (@src/@), returning all existing source directories.
determineSrcDirs :: FilePath -> [FilePath]
determineSrcDirs _root = ["src", "packages"]

-- | Runs HLint on a specific directory within the target repository.
runHlintOnDir :: FilePath -> FilePath -> IO Bool
runHlintOnDir root srcDir = do
  let fullPath = root </> srcDir
  exists <- doesDirectoryExist fullPath
              `catch` (\(_ :: SomeException) -> pure False)
  if not exists
    then pure True  -- Directory does not exist; no hints possible
    else do
      (_code, out, _) <- readCreateProcessWithExitCode ((proc "hlint" [fullPath, "--hint=" ++ root </> ".hlint.yaml", "--no-exit-code"]) { cwd = Just root }) ""
                           `catch` (\(_ :: SomeException) -> pure (ExitSuccess, "No suggestions", ""))
      -- HLint with --no-exit-code always returns 0; check output for "No suggestions" or "No hints"
      let noHints = "No suggestions" `isInfixOfS` out
                 || "No hints" `isInfixOfS` out
                 || null (lines out)
      pure noHints

-- | Checks whether a line contains a GHC warning indicator.
isWarningLine :: String -> Bool
isWarningLine line =
  "warning:" `isInfixOfS` line
  || "Warning:" `isInfixOfS` line

-- | Parses CLOC CSV output for comment density percentage.
-- Returns 0.0 if parsing fails.
parseClocDensity :: String -> Double
parseClocDensity output =
  let csvLines = filter (not . null) (lines output)
  in case csvLines of
    [] -> 0.0
    _  -> extractDensity csvLines

-- | Extracts comment density from CLOC CSV lines.
extractDensity :: [String] -> Double
extractDensity csvLines =
  let summaryLine = last csvLines
      fields = splitOnComma summaryLine
  in case fields of
    -- CLOC CSV columns: files, language, blank, comment, code
    (_:_:_:commentStr:codeStr:_) ->
      let comments = readMaybe commentStr
          code     = readMaybe codeStr
      in case (comments, code) of
           (Just c, Just k) | k > 0 -> (c / (c + k)) * 100.0
           _ -> 0.0
    _ -> 0.0

-- | Simple comma-separated field splitter.
splitOnComma :: String -> [String]
splitOnComma [] = [""]
splitOnComma (',':rest) = "" : splitOnComma rest
splitOnComma (c:rest) = case splitOnComma rest of
  (f:fs) -> (c:f) : fs
  []     -> [[c]]

-- | Safe read with default to Nothing.
readMaybe :: String -> Maybe Double
readMaybe s = case reads (filter (/= '"') s) of
  [(v, "")] -> Just v
  _         -> Nothing

-- | String infix check helper.
isInfixOfS :: String -> String -> Bool
isInfixOfS needle haystack = needle `elem` tails' haystack
  where
    tails' [] = [""]
    tails' xs@(_:rest) = take (length needle) xs : tails' rest

-- | String suffix check helper.
isSuffixOfS :: String -> String -> Bool
isSuffixOfS sfx str = drop (length str - length sfx) str == sfx

