{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Module: Gachi.Sync.Types
-- Description: Core types, models, and data structures for repository standardization
--
-- This module defines the foundational types modeling the ecosystem-wide
-- Standardization Matrix (~/src/PLAN.md §1.A), asset categories across the
-- nine canonical dimensions, asset audit outcomes, and synchronization plans.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], all repositories across ~/src/*
-- adhere to shared structural conventions. This module formalizes those
-- conventions as strongly-typed Haskell records suitable for static analysis,
-- diagnostic reporting, and automated configuration propagation.
--
-- == The Nine Standardization Dimensions
--
-- In accordance with ~/src/PLAN.md §1.A, the ecosystem formalizes nine core
-- standardization dimensions to maintain ergonomic parity across all checkouts:
--
-- 1. __Dimension 1 (Workspace Layout):__
--    Multi-package hierarchy (@packages/*/src@, @packages/*/test@, @.cabal@),
--    central documentation corpus under @docs/@ (@docs/INDEX.md@, @docs/notes/@),
--    and the operational planning pair (@PLAN.md@ and @STATE.md@).
--
-- 2. __Dimension 2 (Code Formatters):__
--    Deterministic code formatting profiles across Haskell (@fourmolu.yaml@),
--    Rust (@rustfmt.toml@), and C/C++ (@.clang-format@). Eliminates whitespace
--    churn and enforces AST-preserving layout.
--
-- 3. __Dimension 3 (Linters & Guardrails):__
--    Static analysis rules enforcing zero-hint cleanliness (@.hlint.yaml@)
--    and modern GHC idioms such as @OverloadedRecordDot@.
--
-- 4. __Dimension 4 (Build Conventions):__
--    Hermetic toolchain pinning (@cabal.project@) targeting GHC 9.14.1 and
--    Cabal 3.18, with developer override templates (@cabal.project.local.example@).
--
-- 5. __Dimension 5 (Git Governance):__
--    Linux kernel RFC 2822 commit message trailers (@.gitmessage@), Tagref
--    cross-reference configuration (@tagref.yml@), and pre-commit hooks.
--
-- 6. __Dimension 6 (Remote Topology):__
--    Multi-forge distribution topology separating Radicle peer-to-peer from
--    commercial and community mirrors (@docs/MAINTAINER_GUIDE.md@).
--
-- 7. __Dimension 7 (Tiered CI Workflows):__
--    Asymmetric forge resource allocation: heavyweight physical verification on
--    GitHub Actions versus lightweight static checks on community GitLab runners.
--
-- 8. __Dimension 8 (Polyglot Invariants):__
--    ABI stability, FFI boundary pinning, and cross-language integration test runners.
--
-- 9. __Dimension 9 (Agent Advisory Layer):__
--    Context-budgeted agent instructions (@AGENTS.md@, ~4 KB limit), compatibility
--    symlinks (@CLAUDE.md@), and modular rules in @.agents/rules/@.
--
-- 10. __Physical Verification Harnesses:__
--     Turnkey shell scripts in @bin/@ enforcing the five physical gates across
--     every checkout (@verify@, @tagref@, @linkcheck@, @cloc@, @generate-tags@).
--
-- == Audit and Synchronization Lifecycle
--
-- The types defined here establish a two-phase verification and synchronization cycle:
--
-- * __Inspection Phase:__
--   The target workspace is audited without mutations ('Gachi.Sync.Audit.auditRepository').
--   Each asset is tested for presence, content equality against 'assetGenerator',
--   and executable bit validity, yielding an 'AssetAuditResult'.
--
-- * __Remediation Phase:__
--   Diagnostic reports ('AuditReport') guide interactive or automated synchronization
--   ('gachi sync') to resolve drift and install missing required infrastructure assets.
--
-- = When to Use This Module
--
-- Import this module when working with:
-- * The 9 standardization dimensions ('AssetCategory').
-- * Asset definitions and generators ('StandardAsset').
-- * The complete multi-dimension matrix ('StandardizationMatrix').
-- * Audit results and diagnostic reports ('AssetAuditStatus', 'AuditReport').
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Types
-- >>> let auth = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
-- >>> let proj = defaultProject "gongju" auth
-- >>> let asset = StandardAsset "bin/:name:-verify" CategoryVerification True True "Runner" (const "")
-- >>> resolveAssetPath proj asset
-- "bin/gongju-verify"
-- >>> categoryName CategoryFormatter
-- "Code Formatters"
module Gachi.Sync.Types
  ( -- * Standardization Dimensions & Categories
    AssetCategory(..)
  , categoryName
  , categoryDescription

    -- * Standard Asset Models
  , StandardAsset(..)
  , resolveAssetPath

    -- * Standardization Matrix
  , StandardizationMatrix(..)

    -- * Audit Results & Statuses
  , AssetAuditStatus(..)
  , AssetAuditResult(..)
  , isCompliant
  , isDrift
  , isMissing

    -- * Diagnostic Reporting
  , AuditReport(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Gachi.Schema.Project (Project, projectName)

--------------------------------------------------------------------------------
-- 1. Standardization Dimensions & Categories
--------------------------------------------------------------------------------

-- | The nine foundational standardization dimensions governing ecosystem repositories.
--
-- Defined in ~/src/PLAN.md §1.A to ensure uniform developer ergonomics,
-- reproducible builds, and automated AI pair programming context across all checkouts.
data AssetCategory
  = CategoryLayout
    -- ^ Dimension 1: Workspace and directory hierarchy (packages/, docs/, bin/, PLAN.md, STATE.md).
  | CategoryFormatter
    -- ^ Dimension 2: Code formatting profiles (fourmolu.yaml, rustfmt.toml, .clang-format).
  | CategoryLinter
    -- ^ Dimension 3: Static analysis guardrails (.hlint.yaml).
  | CategoryBuild
    -- ^ Dimension 4: Build system conventions (cabal.project, cabal.project.local.example).
  | CategoryGitGovernance
    -- ^ Dimension 5: Git governance, RFC 2822 commit templates, and hooks (.githooks/).
  | CategoryRemoteTopology
    -- ^ Dimension 6: Multi-forge replication remotes (rad, github, gitcode, framagit, disroot).
  | CategoryCIWorkflow
    -- ^ Dimension 7: Forge-tiered CI resource allocation (.github/workflows/, .gitlab-ci.yml).
  | CategoryPolyglot
    -- ^ Dimension 8: Multi-language FFI boundary invariants and cross-language tests.
  | CategoryAgentAdvisory
    -- ^ Dimension 9: Agent orientation pointers (AGENTS.md), symlinks, rules, and skills.
  | CategoryVerification
    -- ^ Physical verification harnesses and non-negotiable verification gates (bin/*-verify).
  deriving stock (Eq, Show, Ord, Enum, Bounded, Generic)

-- | Human-readable short name for an 'AssetCategory'.
--
-- Used in diagnostic audit tables and status report banners.
categoryName :: AssetCategory -> Text
categoryName CategoryLayout         = "Workspace Layout"
categoryName CategoryFormatter      = "Code Formatters"
categoryName CategoryLinter         = "Linters & Guardrails"
categoryName CategoryBuild          = "Build Conventions"
categoryName CategoryGitGovernance  = "Git Governance"
categoryName CategoryRemoteTopology = "Remote Topology"
categoryName CategoryCIWorkflow     = "Tiered CI Workflows"
categoryName CategoryPolyglot       = "Polyglot Invariants"
categoryName CategoryAgentAdvisory  = "Agent Advisory Layer"
categoryName CategoryVerification   = "Physical Verification"

-- | Detailed synopsis of what an 'AssetCategory' governs.
--
-- Explains the architectural responsibilities and scope of each dimension.
categoryDescription :: AssetCategory -> Text
categoryDescription CategoryLayout =
  "Multi-package directory hierarchy, central docs/ corpus, and two-file planning loop."
categoryDescription CategoryFormatter =
  "Deterministic code formatting profiles across Haskell (Fourmolu), Rust, and C/C++."
categoryDescription CategoryLinter =
  "Static analysis rules enforcing zero-hint clean compiler and linter policies."
categoryDescription CategoryBuild =
  "Hermetic toolchain pinning (GHC 9.14.1 / Cabal 3.18) and local override patterns."
categoryDescription CategoryGitGovernance =
  "RFC 2822 commit message trailers (Assisted-by:) and pre-commit gate hooks."
categoryDescription CategoryRemoteTopology =
  "Multi-forge mirroring separating Radicle p2p from commercial and community forges."
categoryDescription CategoryCIWorkflow =
  "Asymmetric forge resource allocation: heavy GitHub Actions vs lightweight community CI."
categoryDescription CategoryPolyglot =
  "ABI stability, FFI boundary pinning, and cross-language integration test runners."
categoryDescription CategoryAgentAdvisory =
  "Context-budgeted AGENTS.md (~4 KB pointer), compatibility symlinks, and modular rules."
categoryDescription CategoryVerification =
  "Turnkey verification scripts enforcing the 5 physical gates across every repository."

--------------------------------------------------------------------------------
-- 2. Standard Asset Models
--------------------------------------------------------------------------------

-- | Declarative specification for an individual standardized asset in the ecosystem.
--
-- Each asset defines its relative file path, category dimension, permission requirements,
-- and a pure generator synthesizing its canonical content from a 'Project' specification.
data StandardAsset = StandardAsset
  { assetPath        :: !FilePath
    -- ^ Relative file path within the workspace root (e.g. @".hlint.yaml"@ or @"bin/:name:-verify"@).
  , assetCategory    :: !AssetCategory
    -- ^ Standardization dimension governing this asset.
  , assetRequired    :: !Bool
    -- ^ Whether absence of this file constitutes an audit violation.
  , assetExecutable  :: !Bool
    -- ^ Whether POSIX executable permissions (@+x@) must be applied.
  , assetDescription :: !Text
    -- ^ Human-readable explanation of asset purpose and architectural role.
  , assetGenerator   :: !(Project -> Text)
    -- ^ Pure generator synthesizing canonical file content for the given project.
  } deriving stock (Generic)

instance Show StandardAsset where
  showsPrec d a = showParen (d > 10) $
    showString "StandardAsset { assetPath = " . shows (assetPath a)
    . showString ", assetCategory = " . shows (assetCategory a)
    . showString ", assetRequired = " . shows (assetRequired a)
    . showString ", assetExecutable = " . shows (assetExecutable a)
    . showString ", assetDescription = " . shows (assetDescription a)
    . showString " }"

instance Eq StandardAsset where
  a == b = assetPath a == assetPath b
        && assetCategory a == assetCategory b
        && assetRequired a == assetRequired b
        && assetExecutable a == assetExecutable b

-- | Resolves the concrete filesystem relative path of an asset for a target project.
--
-- Replaces template tokens such as @":name:"@ and @":project:"@ with the project's
-- declared 'projectName'. For static paths (e.g. @".hlint.yaml"@), returns the
-- path unmodified.
--
-- === Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> let proj = defaultProject "gongju" (Author "Nadia" "nadia@example.com")
-- >>> let asset = StandardAsset "bin/:name:-verify" CategoryVerification True True "Verify script" (const "")
-- >>> resolveAssetPath proj asset
-- "bin/gongju-verify"
resolveAssetPath :: Project -> StandardAsset -> FilePath
resolveAssetPath proj asset =
  let pName = T.unpack (projectName proj)
      raw = assetPath asset
      subst [] = []
      subst str@(c:cs)
        | take 6 str == ":name:"    = pName ++ subst (drop 6 str)
        | take 9 str == ":project:" = pName ++ subst (drop 9 str)
        | otherwise                 = c : subst cs
  in subst raw

--------------------------------------------------------------------------------
-- 3. Standardization Matrix
--------------------------------------------------------------------------------

-- | Composite Standardization Matrix aggregating all registered standard assets.
--
-- Encapsulates the entire ecosystem contract: which dimensions are active,
-- which assets belong to each dimension, and how their contents are generated.
data StandardizationMatrix = StandardizationMatrix
  { matrixAssets     :: ![StandardAsset]
    -- ^ Complete list of registered standard asset specifications.
  , matrixDimensions :: ![AssetCategory]
    -- ^ Active dimensions enforced by this matrix instance.
  } deriving stock (Generic)

--------------------------------------------------------------------------------
-- 4. Audit Results & Statuses
--------------------------------------------------------------------------------

-- | Outcome of auditing an individual asset against the physical filesystem.
--
-- The audit engine classifies every asset into exactly one of these five statuses:
--
-- 1. 'StatusCompliant':
--    File exists on disk, content matches expected generator output, and executable
--    bits conform to 'assetExecutable'.
--
-- 2. 'StatusMissing':
--    File is completely absent from the target directory on disk.
--
-- 3. 'StatusContentDrift':
--    File exists, but its text diverges from canonical generator output.
--    Contains actual character count and expected character count.
--
-- 4. 'StatusPermissionDrift':
--    File exists and content matches, but its executable bit differs from
--    expected (e.g. executable script lacking @+x@ permissions).
--
-- 5. 'StatusIOError':
--    Filesystem I/O exception occurred while attempting to inspect the file.
data AssetAuditStatus
  = StatusCompliant
    -- ^ File exists, textual content matches canonical generator, and permissions are valid.
  | StatusMissing
    -- ^ File is missing on disk.
  | StatusContentDrift !Int !Int
    -- ^ File exists but content diverges (actual character length vs expected length).
  | StatusPermissionDrift !Bool !Bool
    -- ^ File exists and matches content, but executable bits differ (actual vs expected).
  | StatusIOError !Text
    -- ^ Filesystem I/O exception occurred while attempting to inspect the file.
  deriving stock (Eq, Show, Generic)

-- | Helper checking if an audit status represents full compliance.
--
-- Returns 'True' exclusively for 'StatusCompliant'.
isCompliant :: AssetAuditStatus -> Bool
isCompliant StatusCompliant = True
isCompliant _               = False

-- | Helper checking if an audit status represents content or permission drift.
--
-- Returns 'True' for 'StatusContentDrift' and 'StatusPermissionDrift'.
isDrift :: AssetAuditStatus -> Bool
isDrift (StatusContentDrift _ _)    = True
isDrift (StatusPermissionDrift _ _) = True
isDrift _                           = False

-- | Helper checking if an audit status represents a missing file.
--
-- Returns 'True' exclusively for 'StatusMissing'.
isMissing :: AssetAuditStatus -> Bool
isMissing StatusMissing = True
isMissing _             = False

-- | Paired audit result combining an asset specification with its observed status.
--
-- Represents the atomic finding for a single asset evaluated by the audit engine.
-- Pairs the structural contract ('resultAsset') with the empirical status observed
-- on disk ('resultStatus').
--
-- === Worked Example
--
-- >>> import Gachi.Sync.Types
-- >>> let asset = StandardAsset ".hlint.yaml" CategoryLinter True False "HLint" (const "")
-- >>> let res = AssetAuditResult asset StatusCompliant
-- >>> isCompliant (resultStatus res)
-- True
data AssetAuditResult = AssetAuditResult
  { resultAsset  :: !StandardAsset
    -- ^ The standardized asset specification audited.
  , resultStatus :: !AssetAuditStatus
    -- ^ Observed compliance or discrepancy status on disk.
  } deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- 5. Diagnostic Reporting
--------------------------------------------------------------------------------

-- | Comprehensive diagnostic summary of a repository audit across the matrix.
--
-- Summarizes aggregate compliance statistics, lists all individual asset audit
-- outcomes, and computes the overall compliance percentage.
data AuditReport = AuditReport
  { reportTargetDir      :: !FilePath
    -- ^ Target repository filesystem path audited.
  , reportProjectName    :: !Text
    -- ^ Name of the audited project specification.
  , reportResults        :: ![AssetAuditResult]
    -- ^ Detailed per-asset audit outcomes.
  , reportTotalAssets    :: !Int
    -- ^ Total number of matrix assets evaluated.
  , reportCompliantCount :: !Int
    -- ^ Number of assets achieving full compliance.
  , reportDriftCount     :: !Int
    -- ^ Number of existing assets with content or permission drift.
  , reportMissingCount   :: !Int
    -- ^ Number of required assets missing from the filesystem.
  , reportCompliancePct  :: !Double
    -- ^ Overall compliance percentage (0.0% to 100.0%).
  } deriving stock (Eq, Show, Generic)
