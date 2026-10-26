{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Retrofit.Report
-- Description: Diagnostic report formatting and pretty-printing
--
-- This module renders 'DiagnosticReport' data structures into aligned ASCII terminal
-- dashboards, GitHub-Flavored Markdown documents, and compact single-line summaries.
--
-- = Architectural Context & Invariants
--
-- Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit],
-- diagnostic reports provide complete observability into legacy or external repositories
-- without altering any target files.
--
-- == Pretty-Printing Philosophy & Formats
--
-- The reporting layer provides three distinct output modalities:
--
-- 1. __Aligned ASCII Terminal Dashboard ('formatDiagnosticReport'):__
--    Optimized for high-information-density terminal display. Features 80-column boxed
--    headers, Unicode progress indicators ('renderScoreBar'), aligned tabular breakdowns
--    for programming languages and documentation gaps, and status checklists for Git hooks
--    and verification gates.
--
-- 2. __GitHub-Flavored Markdown ('formatDiagnosticMarkdown'):__
--    Structured markdown document suitable for piping into @RETROFIT_PLAN.md@, generating
--    pull request descriptions, or saving as CI workflow artifacts.
--
-- 3. __Single-Line Summary ('formatDiagnosticSummaryLine'):__
--    Concise one-line status string intended for log streaming, batch audits, or CI step summaries.
--
-- = Worked Example
--
-- >>> import Gachi.Retrofit.Diagnostic (scanRepository)
-- >>> report <- scanRepository "."
-- >>> let textReport = formatDiagnosticReport report
-- >>> T.null textReport
-- False
-- >>> let summary = formatDiagnosticSummaryLine report
-- >>> "gachi retrofit inspect" `T.isInfixOf` summary
-- True
module Gachi.Retrofit.Report
  ( -- * Report Formatters
    formatDiagnosticReport
  , formatDiagnosticMarkdown
  , formatDiagnosticSummaryLine

    -- * Helper Rendering Primitives
  , renderScoreBar
  , scoreClassification
  , padRight
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Gachi.Retrofit.Types

--------------------------------------------------------------------------------
-- 1. ASCII Terminal Dashboard Formatting
--------------------------------------------------------------------------------

-- | Formats a 'DiagnosticReport' as an aligned ASCII terminal dashboard.
--
-- Renders an 80-column summary dashboard presenting:
-- * Workspace identity, primary language, layout classification, and build tools.
-- * 20-character Unicode progress bar representing the overall retrofit readiness score.
-- * Section [1]: Detailed programming language distribution table.
-- * Section [2]: Test infrastructure status, directories, and declared suites.
-- * Section [3]: Complete @DOC_STRATEGY.md@ documentation checklist.
-- * Section [4]: Git governance, hook permissions, and RFC 2822 trailer status.
-- * Section [5]: 5-gate physical verification harness status.
-- * Section [6]: Prioritized, numbered remediation action plan for Phase 4.
formatDiagnosticReport :: DiagnosticReport -> Text
formatDiagnosticReport r =
  T.unlines
    [ banner
    , " Gachi Diagnostic Repository Inspector (~/src/PLAN.md §1.A, Milestone 4.1)"
    , banner
    , " Target Directory:    " <> T.pack (diagTargetDir r)
    , " Project Identifier:  " <> diagProjectName r
    , " Primary Language:    " <> maybe "Unknown" languageName (diagPrimaryLanguage r)
    , " Workspace Layout:    " <> layoutName (diagLayout r)
    , " Build Systems:       " <> formatBuildList (diagBuildSystems r)
    , " Packages Detected:   " <> formatPackages (diagDiscoveredPackages r)
    , divider
    , " Ecosystem Retrofit Score: " <> renderScoreBar (diagRetrofitScore r) <> " " <> T.pack (show (diagRetrofitScore r)) <> "% (" <> scoreClassification (diagRetrofitScore r) <> ")"
    , banner
    , ""
    , " [1] Programming Language Breakdown"
    , divider
    , formatLanguageTable (diagLanguages r)
    , ""
    , " [2] Test Infrastructure"
    , divider
    , formatTestSection (diagTestInfra r)
    , ""
    , " [3] Documentation Inventory (DOC_STRATEGY.md Compliance: " <> T.pack (show (diagDocCompliancePct r)) <> "%)"
    , divider
    , formatDocTable (diagDocGaps r)
    , ""
    , " [4] Git Governance & Commit Attribution"
    , divider
    , formatGitSection (diagGitGovernance r)
    , ""
    , " [5] Physical Verification Harnesses & Quality Gates"
    , divider
    , formatVerificationSection (diagVerificationHarness r)
    , ""
    , " [6] Prioritized Phase 4 Remediation Plan"
    , divider
    , formatRemediationPlan (diagRemediationPlan r)
    , banner
    ]
  where
    banner  = T.replicate 80 "="
    divider = T.replicate 80 "-"

    formatBuildList [] = "None detected (Unstructured)"
    formatBuildList bs = T.intercalate ", " (map buildSystemName bs)

    formatPackages [] = "None (Single root package or non-Cabal layout)"
    formatPackages ps = "[" <> T.intercalate ", " ps <> "]"

--------------------------------------------------------------------------------
-- 2. Section Formatters
--------------------------------------------------------------------------------

-- | Formats the language distribution table.
--
-- Renders columns: Language, Files, Share (%), and Extensions.
formatLanguageTable :: [LanguageStats] -> Text
formatLanguageTable [] = "  No recognized source code files discovered."
formatLanguageTable stats =
  let hdr = "  Language         | Files      | Share (%)  | Extensions"
      sep = "  -----------------+------------+------------+---------------------------"
      rows = map renderRow stats
  in T.unlines (hdr : sep : rows)
  where
    renderRow s =
      let lang = padRight 16 (languageName (langType s))
          files = padRight 10 (T.pack (show (langFiles s)))
          share = padRight 10 (T.pack (show (langPercentage s)) <> "%")
          exts = T.intercalate ", " (langExtensions s)
      in "  " <> lang <> " | " <> files <> " | " <> share <> " | " <> exts

-- | Formats the test infrastructure section.
--
-- Renders test directories, test file counts, and declared test suites with frameworks.
formatTestSection :: TestInfrastructure -> Text
formatTestSection t
  | not (hasTests t) =
      T.unlines
        [ "  Status:           [-] NO TESTS DETECTED"
        , "  Recommendation:   Establish baseline test suite in test/ or packages/*/test."
        ]
  | otherwise =
      let dirList = if null (testDirectories t) then "None" else T.intercalate ", " (map T.pack (testDirectories t))
          suiteSummary = if null (testSuites t) then "None declared" else T.intercalate "; " (map formatSuite (testSuites t))
      in T.unlines
        [ "  Status:           [+] TEST INFRASTRUCTURE DETECTED"
        , "  Test Files Found: " <> T.pack (show (testFileCount t)) <> " files"
        , "  Directories:      " <> dirList
        , "  Declared Suites:  " <> suiteSummary
        ]
  where
    formatSuite s =
      testSuiteName s <> " (" <> T.intercalate ", " (map testFrameworkName (testFrameworks s)) <> ")"

-- | Formats the @DOC_STRATEGY.md@ documentation checklist.
--
-- Renders columns: Status ([+] / [-]), Severity, Path, and Category.
formatDocTable :: [DocGap] -> Text
formatDocTable [] = "  No documentation items evaluated."
formatDocTable docs =
  let hdr = "  Status | Severity    | Path                         | Category"
      sep = "  -------+-------------+------------------------------+--------------------------"
      rows = map renderRow docs
  in T.unlines (hdr : sep : rows)
  where
    renderRow d =
      let st  = if docPresent d then "[+] OK " else "[-] MISS"
          sev = padRight 11 (docSeverityName (docSeverity d))
          pth = padRight 28 (T.pack (docPath d))
          cat = docCategoryName (docCategory d)
      in "  " <> st <> " | " <> sev <> " | " <> pth <> " | " <> cat

-- | Formats Git governance status.
--
-- Reports status of @.git@, @.githooks@, @core.hooksPath@, @commit-msg@, @pre-commit@,
-- Sarutahiko attribution checks, and @.gitmessage@.
formatGitSection :: GitGovernanceStatus -> Text
formatGitSection g =
  T.unlines
    [ "  Git Repository:    " <> check (hasGitRepo g) "Initialized (.git exists)" "NOT INITIALIZED"
    , "  Hooks Directory:   " <> check (hasHooksDir g) "Standard (.githooks exists)" "Missing (.githooks not found)"
    , "  core.hooksPath:    " <> maybe "[-] Unconfigured (defaults to .git/hooks)" ("[+] Configured: " <>) (hooksPathConfig g)
    , "  commit-msg Hook:   " <> check (hasCommitMsgHook g) (if isCommitMsgExecutable g then "Executable (+x)" else "Present but NOT executable") "Missing"
    , "  AI Trailer Check:  " <> check (hasCommitMsgAttributionCheck g) "Enforcing RFC 2822 Assisted-by: trailers" "Attribution validation missing"
    , "  pre-commit Hook:   " <> check (hasPreCommitHook g) (if isPreCommitExecutable g then "Executable (+x)" else "Present but NOT executable") "Missing"
    , "  Commit Template:   " <> check (hasGitMessageTemplate g) ".gitmessage present" "Missing .gitmessage"
    , "  commit.template:   " <> maybe "[-] Unconfigured in git config" ("[+] Configured: " <>) (gitMessageConfig g)
    ]
  where
    check True ok _ = "[+] " <> ok
    check False _ miss = "[-] " <> miss

-- | Formats verification harness status.
--
-- Reports presence and status of turnkey verify script, Tagref, linkcheck, CLOC,
-- and linters.
formatVerificationSection :: VerificationHarnessStatus -> Text
formatVerificationSection v =
  T.unlines
    [ "  Turnkey Runner:    " <> maybe "[-] Missing (bin/*-verify)" (\p -> "[+] " <> T.pack p) (verifyScriptPath v)
    , "  Tagref Harness:    " <> check (hasTagrefHarness v || hasTagrefConfig v) "Active (tagref.yml / bin/*-tagref)" "Missing"
    , "  Linkcheck Harness: " <> check (hasLinkcheckHarness v) "Active (bin/*-linkcheck)" "Missing"
    , "  CLOC Harness:      " <> check (hasClocHarness v) "Active (bin/*-cloc)" "Missing"
    , "  HLint Config:      " <> check (hasHlintConfig v) "Active (.hlint.yaml)" "Missing"
    , "  Fourmolu Config:   " <> check (hasFourmoluConfig v) "Active (fourmolu.yaml)" "Missing"
    ]
  where
    check True ok _ = "[+] " <> ok
    check False _ miss = "[-] " <> miss

-- | Formats prioritized remediation actions.
--
-- Displays numbered steps guiding the developer on required Phase 4 actions.
formatRemediationPlan :: [Text] -> Text
formatRemediationPlan [] = "  [+] Total ecosystem compliance: 0 remediation actions required!"
formatRemediationPlan plan =
  let numbered = zipWith (\(n :: Int) item -> "  " <> T.pack (show n) <> ". " <> item) [1..] plan
  in T.unlines numbered

--------------------------------------------------------------------------------
-- 3. Markdown Output Formatting
--------------------------------------------------------------------------------

-- | Formats the diagnostic report as structured GitHub-Flavored Markdown.
--
-- Suitable for generating @RETROFIT_PLAN.md@, pull request descriptions, or CI summary
-- artifacts. Includes formatted Markdown tables for languages and documentation items.
formatDiagnosticMarkdown :: DiagnosticReport -> Text
formatDiagnosticMarkdown r =
  T.unlines
    [ "# Diagnostic Repository Inspection Report: `" <> diagProjectName r <> "`"
    , ""
    , "**Status:** EVALUATED · Milestone 4.1 Diagnostic Inspector  "
    , "**Target Directory:** `" <> T.pack (diagTargetDir r) <> "`  "
    , "**Retrofit Readiness Score:** **" <> T.pack (show (diagRetrofitScore r)) <> "%** (" <> scoreClassification (diagRetrofitScore r) <> ")  "
    , "**DOC_STRATEGY.md Compliance:** **" <> T.pack (show (diagDocCompliancePct r)) <> "%**"
    , ""
    , "---"
    , ""
    , "## 1. Programming Languages"
    , ""
    , "| Language | Files | Share | Extensions |"
    , "|---|---|---|---|"
    , T.unlines (map renderMdLang (diagLanguages r))
    , "## 2. Build Systems & Architecture"
    , ""
    , "- **Workspace Layout:** " <> layoutName (diagLayout r)
    , "- **Build Toolchains:** " <> T.intercalate ", " (map buildSystemName (diagBuildSystems r))
    , "- **Packages:** " <> if null (diagDiscoveredPackages r) then "None" else T.intercalate ", " (diagDiscoveredPackages r)
    , ""
    , "## 3. Documentation Gaps"
    , ""
    , "| Status | Document | Severity | Category |"
    , "|---|---|---|---|"
    , T.unlines (map renderMdDoc (diagDocGaps r))
    , "## 4. Prioritized Phase 4 Remediation Plan"
    , ""
    , formatMdRemediation (diagRemediationPlan r)
    ]
  where
    renderMdLang s =
      "| " <> languageName (langType s) <> " | " <> T.pack (show (langFiles s)) <> " | " <> T.pack (show (langPercentage s)) <> "% | `" <> T.intercalate ", " (langExtensions s) <> "` |"

    renderMdDoc d =
      let st = if docPresent d then "✅ Present" else "❌ Missing"
      in "| " <> st <> " | `" <> T.pack (docPath d) <> "` | **" <> docSeverityName (docSeverity d) <> "** | " <> docCategoryName (docCategory d) <> " |"

    formatMdRemediation [] = "*No remediation actions required; codebase is in harmonic ecosystem equilibrium.*"
    formatMdRemediation items =
      T.unlines (map ("- [ ] " <>) items)

--------------------------------------------------------------------------------
-- 4. Compact Summary Line
--------------------------------------------------------------------------------

-- | Formats a single-line summary string suitable for logs or streaming output.
--
-- === Examples
--
-- >>> let r = DiagnosticReport "." "gachi" (Just LangHaskell) [] [] LayoutMultiPackage [] (TestInfrastructure True [] [] 0) [] 100.0 (GitGovernanceStatus True True Nothing True True True True True True Nothing) (VerificationHarnessStatus True Nothing True True True True True True) 95.0 []
-- >>> formatDiagnosticSummaryLine r
-- "gachi retrofit inspect [gachi]: Haskell, Multi-Package Workspace Layout (packages/*), Score: 95.0%, 0 critical doc gaps"
formatDiagnosticSummaryLine :: DiagnosticReport -> Text
formatDiagnosticSummaryLine r =
  let langStr = maybe "Unknown" languageName (diagPrimaryLanguage r)
      critGaps = length (filter (\d -> not (docPresent d) && docSeverity d == SeverityCritical) (diagDocGaps r))
  in "gachi retrofit inspect [" <> diagProjectName r <> "]: "
     <> langStr <> ", "
     <> layoutName (diagLayout r) <> ", "
     <> "Score: " <> T.pack (show (diagRetrofitScore r)) <> "%, "
     <> T.pack (show critGaps) <> " critical doc gaps"

--------------------------------------------------------------------------------
-- 5. Progress Bars & Helpers
--------------------------------------------------------------------------------

-- | Renders a 20-character Unicode block progress bar.
--
-- Clamps score between 0.0 and 100.0, rendering filled blocks (@█@) and empty blocks (@░@).
--
-- === Examples
--
-- >>> renderScoreBar 50.0
-- "[██████████░░░░░░░░░░]"
-- >>> renderScoreBar 100.0
-- "[████████████████████]"
renderScoreBar :: Double -> Text
renderScoreBar score =
  let clamped = max 0.0 (min 100.0 score)
      filledCount = round ((clamped / 100.0) * 20.0) :: Int
      emptyCount = max 0 (20 - filledCount)
  in "[" <> T.replicate filledCount "█" <> T.replicate emptyCount "░" <> "]"

-- | Qualitative classification of a numerical retrofit score.
--
-- Categorizes readiness into four actionable tiers:
-- * >= 90.0: High Conformance
-- * >= 70.0: Moderate Adaptation Needed
-- * >= 40.0: Substantial Retrofit Required
-- * < 40.0:  Unstandardized / Raw Codebase
scoreClassification :: Double -> Text
scoreClassification s
  | s >= 90.0 = "HIGH CONFORMANCE"
  | s >= 70.0 = "MODERATE ADAPTATION NEEDED"
  | s >= 40.0 = "SUBSTANTIAL RETROFIT REQUIRED"
  | otherwise = "UNSTANDARDIZED / RAW CODEBASE"

-- | Right-pads a 'Text' value with spaces to achieve the specified minimum column width.
padRight :: Int -> Text -> Text
padRight width txt =
  let len = T.length txt
  in if len >= width then txt else txt <> T.replicate (width - len) " "
