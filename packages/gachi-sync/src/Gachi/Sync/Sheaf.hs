{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Sync.Sheaf
-- Description: 1-D cellular sheaf cohomology and cross-repository coherence auditor
--
-- This module implements the 1-dimensional cellular sheaf model over the ecosystem
-- repositories (~/src/PLAN.md §1.A, Milestone 3.5).
--
-- = Architectural Context & Homological Foundations
--
-- In applied algebraic topology (Curry 2014, Ghrist 2014) and distributed systems
-- governance, consistency across heterogeneous multi-package repositories is formalized
-- as a 1-dimensional cellular sheaf \(\mathcal{F}\) over a cell complex \(G = (V, E)\).
--
-- == The 1-Dimensional Cellular Sheaf Model
--
-- 1. __0-Cells (Vertices \(v \in V\)):__
--    Represent individual repository checkouts across @~/src/*@ (e.g. @polytropos@,
--    @gargamelle@, @sarutahiko@, @gachi@, @gongju@), augmented by an authoritative
--    canonical reference vertex (@"canonical"@) defined by the Standardization Matrix.
--
-- 2. __1-Cells (Edges \(e = (u, v) \in E\)):__
--    Represent shared contract obligations between repositories along ten standard
--    dimensions: compiler pinning (GHC 9.14.1), Cabal specification (3.0/3.18),
--    licensing (EUPL-1.2), Git commit trailers, pre-commit verification hooks,
--    HLint rules, CI workflows, and agent advisory context.
--
-- 3. __Stalk Assignments:__
--    * Vertex Stalk \(\mathcal{F}(v)\): 'RepoStalk' containing observed configuration
--      attributes extracted from the filesystem.
--    * Edge Stalk \(\mathcal{F}(e)\): 'ContractValue' representing projected contract states.
--
-- 4. __Restriction Morphisms (\(\rho_{u \trianglelefteq e}\)):__
--    Project the full repository state into the boundary contract language.
--
-- 5. __Sheaf Coboundary Operator (\(\delta^0\)):__
--    Maps 0-cochains \(C^0\) to 1-cochains \(C^1\), measuring boundary discrepancies:
--    \[
--      \delta^0 : C^0(G; \mathcal{F}) \to C^1(G; \mathcal{F})
--    \]
--    \[
--      \delta^0(x)_e = (\rho_{u \trianglelefteq e}(x_u), \rho_{v \trianglelefteq e}(x_v))
--    \]
--
-- 6. __Cohomological Invariants:__
--    * __0-th Cohomology \(H^0(G; \mathcal{F}) = \ker \delta^0\):__
--      The space of harmonic global sections. When all boundary projections coincide,
--      \(\delta^0(x) = 0\), mathematically certifying total ecosystem equilibrium (0 drift).
--    * __1-st Cohomology \(H^1(G; \mathcal{F}) = \operatorname{coker} \delta^0\):__
--      When \(\delta^0(x) \neq 0\), the non-vanishing cochains localize exact boundary
--      obstructions, pinpointing drifting repositories and breached contracts.
--
-- See Note [Cellular Sheaf Coherence and Homological Obstruction Localization]
-- [ref:note-cellular-sheaf-coherence].
--
-- = Worked Example
--
-- >>> import qualified Data.Map.Strict as Map
-- >>> let complex = buildCanonicalSheafComplex ["gachi"]
-- >>> let stalk = canonicalRepoStalk { stalkRepoName = "gachi" }
-- >>> let c0 = Cochain0 (Map.fromList [("canonical", canonicalRepoStalk), ("gachi", stalk)])
-- >>> let (_, isHarmonic) = coboundary complex defaultEcosystemSheaf c0
-- >>> isHarmonic
-- True
module Gachi.Sync.Sheaf
  ( -- * Note Annotation
    -- $note_cellular_sheaf

    -- * Cellular Complex Types
    CellComplex(..)
  , emptyComplex
  , addVertex
  , addEdge
  , numVertices
  , numEdges
  , eulerCharacteristic
  , Orientation(..)
  , orientationSign
  , Cell(..)

    -- * Cellular Sheaf & Cochains
  , CellularSheaf(..)
  , symmetricSheaf
  , directionalSheaf
  , Cochain0(..)
  , Cochain1(..)
  , CohomologyResult(..)
  , SheafObstruction(..)

    -- * Sheaf Cohomology Operators
  , coboundary
  , isHarmonicCochain
  , computeCohomology
  , locateSheafObstructions

    -- * Ecosystem Domain Types
  , ContractDimension(..)
  , contractDimensionName
  , contractDimensionRemediation
  , SheafEdgeId(..)
  , ContractValue(..)
  , RepoStalk(..)
  , SheafReport(..)

    -- * Ecosystem Sheaf Constructors & Evaluators
  , canonicalRepoStalk
  , restrictRepoStalk
  , defaultEcosystemSheaf
  , buildCanonicalSheafComplex
  , buildPairwiseComplex
  , evaluateSheafCoherence
  , formatSheafReport

    -- * Live Filesystem Inspection
  , inspectRepoStalk
  , inspectRepoGhcVersion
  , inspectRepoCabalVersion
  , inspectRepoLicense
  , findRepositoryRoot
  , auditSheafTarget
  , auditEcosystemSheaf
  ) where

import Control.Exception (SomeException, catch)
import Data.Char (isDigit)
import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( canonicalizePath
  , doesDirectoryExist
  , doesFileExist
  , getPermissions
  , executable
  , listDirectory
  )
import System.FilePath ((</>), takeFileName, takeExtension, takeDirectory)

import Gachi.Sync.Engine (discoverEcosystemRepositories)

-- $note_cellular_sheaf
-- Note [Cellular Sheaf Coherence and Homological Obstruction Localization]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-cellular-sheaf-coherence]
-- In distributed software systems engineering and applied algebraic topology
-- (Curry 2014, Ghrist 2014), cross-repository consistency is formalized as a
-- 1-dimensional cellular sheaf F over a cell complex G = (V, E):
--
-- 1. Topological Complex G = (V, E):
--    - 0-Cells (Vertices v ∈ V): Standalone repository checkouts across ~/src/*
--      (e.g., polytropos, gargamelle, sarutahiko, gachi, gongju) plus an
--      authoritative canonical reference vertex ("canonical").
--    - 1-Cells (Edges e = (u, v) ∈ E): Shared interface boundaries governing
--      toolchain pinning, license terms, git governance, linter guardrails,
--      and CI matrix workflows.
--
-- 2. Stalks and Restriction Morphisms:
--    - Stalk F(v) at vertex v: The local configuration state (RepoStalk)
--      extracted from disk at checkout v.
--    - Stalk F(e) on edge e: The projected contract value (ContractValue) along
--      dimension d.
--    - Restriction maps ρ_{u ⊴ e} : F(u) -> F(e) and ρ_{v ⊴ e} : F(v) -> F(e)
--      extract local configuration attributes into the contract boundary language.
--
-- 3. Sheaf Coboundary Operator δ⁰:
--    - Maps 0-cochains (vertex states) to 1-cochains (edge boundary discrepancies):
--        δ⁰ : C⁰(G; F) -> C¹(G; F)
--        δ⁰(x)_e = (ρ_{u ⊴ e}(x_u), ρ_{v ⊴ e}(x_v))
--
-- 4. Cohomological Invariants:
--    - 0-th Cohomology H⁰(G; F) = ker δ⁰:
--      Represents the space of global sections. When all boundary projections
--      coincide across all edges (isHarmonicCochain == True), δ⁰(x) vanishes.
--      This certifies that all repositories satisfy the ecosystem contracts in
--      total harmonic equilibrium (0 drift).
--    - 1-st Cohomology H¹(G; F) = coker δ⁰:
--      When δ⁰(x) fails to vanish, the non-zero cochains localize the exact
--      cohomological obstructions to global consistency, pinpointing the
--      drifting repository, the breached contract dimension, and the observed
--      mismatch without requiring whole-ecosystem compilation.

--------------------------------------------------------------------------------
-- 1. Generic 1-D Cell Complex Primitives
--------------------------------------------------------------------------------

-- | A finite 1-dimensional cell complex (graph complex) \(G = (V, E)\).
--
-- 0-cells represent repositories or configuration contexts, and 1-cells
-- represent shared contract interfaces connecting them.
data CellComplex vId eId = CellComplex
  { complexVertices :: ![vId]
    -- ^ Exhaustive list of 0-cells in the complex.
  , complexEdges    :: !(Map eId (vId, vId))
    -- ^ Map of 1-cells identifying @(source, target)@ endpoint incidence.
  } deriving stock (Eq, Show)

-- | Orientation of an incident 1-cell relative to a vertex 0-cell.
data Orientation
  = Forward   -- ^ Directed away from vertex (vertex is source: sign -1)
  | Backward  -- ^ Directed into vertex (vertex is target: sign +1)
  deriving stock (Eq, Ord, Show)

-- | Numeric homological sign for an orientation.
orientationSign :: Orientation -> Int
orientationSign Forward  = -1
orientationSign Backward = 1

-- | Graded cells of a 1-dimensional cell complex.
data Cell vId eId
  = Cell0 !vId  -- ^ 0-cell (vertex)
  | Cell1 !eId  -- ^ 1-cell (edge)
  deriving stock (Eq, Ord, Show)

-- | Empty cell complex with no vertices or edges.
emptyComplex :: CellComplex vId eId
emptyComplex = CellComplex
  { complexVertices = []
  , complexEdges    = Map.empty
  }

-- | Inserts a vertex into the cell complex if not already present.
addVertex :: (Eq vId) => vId -> CellComplex vId eId -> CellComplex vId eId
addVertex v complex
  | v `elem` complexVertices complex = complex
  | otherwise = complex { complexVertices = v : complexVertices complex }

-- | Inserts a directed 1-cell and ensures its endpoints are in the vertex set.
addEdge
  :: (Ord eId, Eq vId)
  => eId
  -> vId
  -> vId
  -> CellComplex vId eId
  -> CellComplex vId eId
addEdge e u w complex = complex
  { complexVertices = nub (u : w : complexVertices complex)
  , complexEdges    = Map.insert e (u, w) (complexEdges complex)
  }

-- | Total count of 0-cells in the complex.
numVertices :: CellComplex vId eId -> Int
numVertices = length . complexVertices

-- | Total count of 1-cells in the complex.
numEdges :: CellComplex vId eId -> Int
numEdges = Map.size . complexEdges

-- | Computes the topological Euler characteristic: \(\chi = |V| - |E|\).
eulerCharacteristic :: CellComplex vId eId -> Int
eulerCharacteristic c = numVertices c - numEdges c

--------------------------------------------------------------------------------
-- 2. Cellular Sheaf and Cochain Representations
--------------------------------------------------------------------------------

-- | A cellular sheaf \(\mathcal{F}\) over a cell complex \(G = (V, E)\).
--
-- Assigns stalks to 0-cells and 1-cells, with directional restriction
-- morphisms along cell face inclusions.
--
-- See Note [Cellular Sheaf Coherence and Homological Obstruction Localization]
-- [ref:note-cellular-sheaf-coherence].
data CellularSheaf vId eId stalk edgeStalk = CellularSheaf
  { restrictSrc :: eId -> stalk -> edgeStalk
    -- ^ Source restriction morphism \(\rho_{u \trianglelefteq e}\).
  , restrictTgt :: eId -> stalk -> edgeStalk
    -- ^ Target restriction morphism \(\rho_{v \trianglelefteq e}\).
  , liftSrc     :: eId -> edgeStalk -> stalk
    -- ^ Adjoint lift from edge stalk back to source vertex.
  , liftTgt     :: eId -> edgeStalk -> stalk
    -- ^ Adjoint lift from edge stalk back to target vertex.
  }

-- | Constructs a cellular sheaf where source and target restriction maps coincide.
symmetricSheaf
  :: (eId -> stalk -> edgeStalk)
  -> (eId -> edgeStalk -> stalk)
  -> CellularSheaf vId eId stalk edgeStalk
symmetricSheaf restr lift_ = CellularSheaf
  { restrictSrc = restr
  , restrictTgt = restr
  , liftSrc     = lift_
  , liftTgt     = lift_
  }

-- | Constructs a directional cellular sheaf with explicit source and target morphisms.
directionalSheaf
  :: (eId -> stalk -> edgeStalk)
  -> (eId -> stalk -> edgeStalk)
  -> (eId -> edgeStalk -> stalk)
  -> (eId -> edgeStalk -> stalk)
  -> CellularSheaf vId eId stalk edgeStalk
directionalSheaf = CellularSheaf

-- | 0-Cochain: an assignment of stalk elements across 0-cells (vertices).
newtype Cochain0 vId stalk = Cochain0
  { unCochain0 :: Map vId stalk
  } deriving stock (Eq, Show)
    deriving newtype (Functor)

-- | 1-Cochain: an assignment of edge stalk elements across 1-cells (edges).
newtype Cochain1 eId edgeStalk = Cochain1
  { unCochain1 :: Map eId edgeStalk
  } deriving stock (Eq, Show)
    deriving newtype (Functor)

-- | Result of cohomology computation at dimension 0 and 1.
data CohomologyResult eId edgeStalk
  = HarmonicSection
    -- ^ \(\ker \delta^0\): All boundary restrictions coincide; 0 drift.
  | ObstructionMap !(Map eId (edgeStalk, edgeStalk))
    -- ^ \(\operatorname{coker} \delta^0\): Non-zero boundary discrepancies.
  deriving stock (Eq, Show)

-- | Detailed diagnostic record for an interface obstruction along an edge.
data SheafObstruction vId eId edgeStalk = SheafObstruction
  { obstructionEdge    :: !eId
    -- ^ Identifier of the failing contract edge.
  , obstructionSource  :: !vId
    -- ^ Source vertex (e.g. @"canonical"@).
  , obstructionTarget  :: !vId
    -- ^ Target vertex (e.g. @"gongju"@).
  , sourceRestriction  :: !edgeStalk
    -- ^ Projected contract value from source.
  , targetRestriction  :: !edgeStalk
    -- ^ Projected contract value from target.
  , obstructionMessage :: !Text
    -- ^ Human-readable diagnostic explanation and remediation guidance.
  } deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- 3. Sheaf Coboundary Operator & Cohomology Invariants
--------------------------------------------------------------------------------

-- | Sheaf Coboundary Operator: \(\delta^0 : C^0(G; \mathcal{F}) \to C^1(G; \mathcal{F})\).
--
-- Evaluates the boundary discrepancy pair
-- \((\rho_{u \trianglelefteq e}(x_u), \rho_{v \trianglelefteq e}(x_v))\)
-- for every 1-cell \(e = (u, v)\) in the complex.
--
-- Returns the 1-cochain of boundary pairs and a boolean indicating whether the
-- 0-cochain is harmonic (i.e. all boundary restrictions match).
--
-- See Note [Cellular Sheaf Coherence and Homological Obstruction Localization]
-- [ref:note-cellular-sheaf-coherence].
coboundary
  :: forall vId eId stalk edgeStalk.
     (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> (Cochain1 eId (edgeStalk, edgeStalk), Bool)
coboundary complex sheaf (Cochain0 vMap) =
  let edgeDiffs = Map.mapMaybeWithKey computeEdge (complexEdges complex)
      harmonic = all (uncurry (==)) edgeDiffs
  in (Cochain1 edgeDiffs, harmonic)
  where
    computeEdge eId (u, v) = case (Map.lookup u vMap, Map.lookup v vMap) of
      (Just stU, Just stV) ->
        Just (restrictSrc sheaf eId stU, restrictTgt sheaf eId stV)
      _ -> Nothing

-- | Predicate checking if a 0-cochain satisfies the sheaf gluing condition (zero coboundary).
isHarmonicCochain
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Bool
isHarmonicCochain complex sheaf = snd . coboundary complex sheaf

-- | Computes cohomology: returns 'HarmonicSection' if all boundary restrictions
-- agree, or 'ObstructionMap' detailing the non-vanishing cocycles.
computeCohomology
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> CohomologyResult eId edgeStalk
computeCohomology complex sheaf c0 =
  let (Cochain1 diffs, harmonic) = coboundary complex sheaf c0
  in if harmonic
       then HarmonicSection
       else ObstructionMap (Map.filter (uncurry (/=)) diffs)

-- | Locates and extracts all failing interface boundaries where \(H^1\)
-- cohomological obstructions prevent global consensus.
locateSheafObstructions
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> (eId -> vId -> vId -> edgeStalk -> edgeStalk -> Text)
  -> [SheafObstruction vId eId edgeStalk]
locateSheafObstructions complex sheaf (Cochain0 vMap) explainFn =
  [ SheafObstruction
      { obstructionEdge    = e
      , obstructionSource  = u
      , obstructionTarget  = v
      , sourceRestriction  = s
      , targetRestriction  = t
      , obstructionMessage = explainFn e u v s t
      }
  | (e, (u, v)) <- Map.toList (complexEdges complex)
  , Just stU <- [Map.lookup u vMap]
  , let s = restrictSrc sheaf e stU
  , Just stV <- [Map.lookup v vMap]
  , let t = restrictTgt sheaf e stV
  , s /= t
  ]

--------------------------------------------------------------------------------
-- 4. Ecosystem Standardization Dimensions & Domain Stalks
--------------------------------------------------------------------------------

-- | Standardization contract dimensions evaluated across repository boundaries.
data ContractDimension
  = ContractGhcVersion       -- ^ GHC compiler version pinning (GHC 9.14.1)
  | ContractCabalVersion     -- ^ Cabal specification version (3.0 / 3.18)
  | ContractLicense          -- ^ Permissive open source license (EUPL-1.2)
  | ContractGitCommitHook    -- ^ Git commit-msg hook for AI trailers (.githooks/commit-msg)
  | ContractGitPreCommitHook -- ^ Git pre-commit static verification hook (.githooks/pre-commit)
  | ContractGitMessage       -- ^ Git commit message template (.gitmessage)
  | ContractHLintConfig      -- ^ HLint static analysis configuration (.hlint.yaml)
  | ContractCIWorkflow       -- ^ Continuous integration matrix (.github/workflows/ci.yml)
  | ContractAgentsAdvisory   -- ^ AI agent guidance pointer (AGENTS.md)
  | ContractVerifyRunner     -- ^ Turnkey physical verification script (bin/<name>-verify)
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Human-readable name for a contract dimension.
contractDimensionName :: ContractDimension -> Text
contractDimensionName = \case
  ContractGhcVersion       -> "GHC Compiler Pinning"
  ContractCabalVersion     -> "Cabal Spec Version"
  ContractLicense          -> "Software License (EUPL-1.2)"
  ContractGitCommitHook    -> "Git Commit-Msg Hook"
  ContractGitPreCommitHook -> "Git Pre-Commit Hook"
  ContractGitMessage       -> "Git Message Template"
  ContractHLintConfig      -> "HLint Guardrails"
  ContractCIWorkflow       -> "CI Workflow Matrix"
  ContractAgentsAdvisory   -> "Agent Advisory Context"
  ContractVerifyRunner     -> "Physical Verify Runner"

-- | Remediation guidance string for a contract dimension breach.
contractDimensionRemediation :: ContractDimension -> Text
contractDimensionRemediation = \case
  ContractGhcVersion       -> "Update cabal.project / .cabal to target GHC 9.14.1."
  ContractCabalVersion     -> "Update cabal manifests to cabal-version: 3.0 or 3.18."
  ContractLicense          -> "Add EUPL-1.2 LICENSE and update cabal license field."
  ContractGitCommitHook    -> "Install .githooks/commit-msg via 'gachi sync'."
  ContractGitPreCommitHook -> "Install .githooks/pre-commit via 'gachi sync'."
  ContractGitMessage       -> "Install .gitmessage via 'gachi sync' and set commit.template."
  ContractHLintConfig      -> "Install canonical .hlint.yaml via 'gachi sync'."
  ContractCIWorkflow       -> "Generate forge CI workflows via 'gachi sync'."
  ContractAgentsAdvisory   -> "Install AGENTS.md and .agents/ rules via 'gachi sync'."
  ContractVerifyRunner     -> "Scaffold bin/<project>-verify executable via 'gachi init/sync'."

-- | Edge identifier in the ecosystem sheaf complex.
data SheafEdgeId = SheafEdgeId
  { edgeSourceRepo :: !Text
    -- ^ Source repository name (e.g. @"canonical"@).
  , edgeTargetRepo :: !Text
    -- ^ Target repository name (e.g. @"gongju"@).
  , edgeDimension  :: !ContractDimension
    -- ^ Evaluated contract dimension.
  } deriving stock (Eq, Ord, Show)

-- | Projected contract value on an edge stalk.
data ContractValue
  = ContractText !(Maybe Text)  -- ^ Textual attribute (e.g. Just "9.14.1")
  | ContractBool !Bool          -- ^ Binary conformance status (True / False)
  deriving stock (Eq, Ord, Show)

-- | Observed repository configuration stalk extracted from a checkout.
data RepoStalk = RepoStalk
  { stalkRepoName        :: !Text
    -- ^ Canonical repository identifier.
  , stalkRepoPath        :: !FilePath
    -- ^ Absolute path to repository root.
  , stalkGhcVersion      :: !(Maybe Text)
    -- ^ Detected GHC compiler pinning.
  , stalkCabalVersion    :: !(Maybe Text)
    -- ^ Detected Cabal specification version.
  , stalkLicense         :: !(Maybe Text)
    -- ^ Detected license stanza or file.
  , stalkHasCommitMsg    :: !Bool
    -- ^ Presence and validity of .githooks/commit-msg.
  , stalkHasPreCommit    :: !Bool
    -- ^ Presence and validity of .githooks/pre-commit.
  , stalkHasGitMessage   :: !Bool
    -- ^ Presence of .gitmessage commit template.
  , stalkHasHLint        :: !Bool
    -- ^ Presence of .hlint.yaml.
  , stalkHasCIWorkflow   :: !Bool
    -- ^ Presence of CI configuration (.github/workflows/ci.yml or .gitlab-ci.yml).
  , stalkHasAgentsMd     :: !Bool
    -- ^ Presence of AGENTS.md orientation pointer.
  , stalkHasVerifyRunner :: !Bool
    -- ^ Presence of executable bin/*-verify runner.
  } deriving stock (Eq, Show)

-- | Canonical reference stalk representing the ideal ecosystem contract.
canonicalRepoStalk :: RepoStalk
canonicalRepoStalk = RepoStalk
  { stalkRepoName        = "canonical"
  , stalkRepoPath        = "/"
  , stalkGhcVersion      = Just "9.14.1"
  , stalkCabalVersion    = Just "3.0"
  , stalkLicense         = Just "EUPL-1.2"
  , stalkHasCommitMsg    = True
  , stalkHasPreCommit    = True
  , stalkHasGitMessage   = True
  , stalkHasHLint        = True
  , stalkHasCIWorkflow   = True
  , stalkHasAgentsMd     = True
  , stalkHasVerifyRunner = True
  }

-- | Restriction morphism: projects a 'RepoStalk' onto a 'ContractValue' along a dimension.
restrictRepoStalk :: ContractDimension -> RepoStalk -> ContractValue
restrictRepoStalk dim stalk = case dim of
  ContractGhcVersion       -> ContractText (stalkGhcVersion stalk)
  ContractCabalVersion     -> ContractText (normalizeCabalVer (stalkCabalVersion stalk))
  ContractLicense          -> ContractText (normalizeLicense (stalkLicense stalk))
  ContractGitCommitHook    -> ContractBool (stalkHasCommitMsg stalk)
  ContractGitPreCommitHook -> ContractBool (stalkHasPreCommit stalk)
  ContractGitMessage       -> ContractBool (stalkHasGitMessage stalk)
  ContractHLintConfig      -> ContractBool (stalkHasHLint stalk)
  ContractCIWorkflow       -> ContractBool (stalkHasCIWorkflow stalk)
  ContractAgentsAdvisory   -> ContractBool (stalkHasAgentsMd stalk)
  ContractVerifyRunner     -> ContractBool (stalkHasVerifyRunner stalk)
  where
    -- Normalize Cabal versions: 3.18, 3.12, 3.0 all treated as valid 3.x specifications
    normalizeCabalVer (Just v)
      | "3." `T.isPrefixOf` T.strip v = Just "3.0"
      | otherwise = Just (T.strip v)
    normalizeCabalVer Nothing = Nothing

    -- Normalize EUPL licenses: EUPL-1.2, EUPL-1.1 treated as canonical EUPL
    normalizeLicense (Just lic)
      | "EUPL" `T.isInfixOf` T.toUpper lic = Just "EUPL-1.2"
      | otherwise = Just (T.strip lic)
    normalizeLicense Nothing = Nothing

-- | Default cellular sheaf connecting repositories to the canonical reference.
defaultEcosystemSheaf
  :: CellularSheaf Text SheafEdgeId RepoStalk ContractValue
defaultEcosystemSheaf = CellularSheaf
  { restrictSrc = restrictRepoStalk . edgeDimension
  , restrictTgt = restrictRepoStalk . edgeDimension
  , liftSrc     = \_ _ -> canonicalRepoStalk
  , liftTgt     = \_ _ -> canonicalRepoStalk
  }

--------------------------------------------------------------------------------
-- 5. Complex Construction & Sheaf Coherence Evaluation
--------------------------------------------------------------------------------

-- | All ten contract dimensions evaluated in the ecosystem complex.
allContractDimensions :: [ContractDimension]
allContractDimensions = [minBound .. maxBound]

-- | Constructs a star cell complex centered at @"canonical"@ connecting every
-- client repository along all ten contract dimensions.
buildCanonicalSheafComplex :: [Text] -> CellComplex Text SheafEdgeId
buildCanonicalSheafComplex clientRepos =
  let v0 = "canonical"
      allVerts = v0 : clientRepos
      edgeList =
        [ ( SheafEdgeId v0 repo dim, (v0, repo) )
        | repo <- clientRepos
        , dim  <- allContractDimensions
        ]
  in CellComplex
      { complexVertices = allVerts
      , complexEdges    = Map.fromList edgeList
      }

-- | Constructs a pairwise cell complex connecting adjacent client repositories.
buildPairwiseComplex :: [Text] -> CellComplex Text SheafEdgeId
buildPairwiseComplex repos =
  let pairs = zip repos (drop 1 repos)
      edgeList =
        [ ( SheafEdgeId u v dim, (u, v) )
        | (u, v) <- pairs
        , dim    <- allContractDimensions
        ]
  in CellComplex
      { complexVertices = repos
      , complexEdges    = Map.fromList edgeList
      }

-- | Comprehensive diagnostic summary of cellular sheaf coherence.
data SheafReport = SheafReport
  { reportVertices          :: ![Text]
    -- ^ All 0-cells in the complex.
  , reportEdgeCount         :: !Int
    -- ^ Total 1-cells evaluated across all contract dimensions.
  , reportEulerChar         :: !Int
    -- ^ Euler characteristic \(\chi = |V| - |E|\).
  , reportHarmonicEdges     :: !Int
    -- ^ Count of edges satisfying boundary agreement.
  , reportDriftEdges        :: !Int
    -- ^ Count of edges exhibiting boundary discrepancies.
  , reportCoherencePct      :: !Double
    -- ^ Percentage of edges in harmonic resonance (0.0 to 100.0).
  , reportIsHarmonic        :: !Bool
    -- ^ True if \(H^0\) is complete and \(H^1 = \emptyset\) (0 obstructions).
  , reportObstructions      :: ![SheafObstruction Text SheafEdgeId ContractValue]
    -- ^ Localized cohomological obstructions.
  } deriving stock (Eq, Show)

-- | Evaluates cellular sheaf coherence over a cell complex and 0-cochain.
evaluateSheafCoherence
  :: CellComplex Text SheafEdgeId
  -> Cochain0 Text RepoStalk
  -> SheafReport
evaluateSheafCoherence complex c0 =
  let (Cochain1 diffs, harmonic) = coboundary complex defaultEcosystemSheaf c0
      totalEdges = Map.size diffs
      driftCount = Map.size (Map.filter (uncurry (/=)) diffs)
      harmonicCount = totalEdges - driftCount
      pct = if totalEdges == 0 then 100.0 else (fromIntegral harmonicCount / fromIntegral totalEdges) * 100.0
      obstructions = locateSheafObstructions complex defaultEcosystemSheaf c0 formatObstructionMsg
  in SheafReport
      { reportVertices      = complexVertices complex
      , reportEdgeCount     = totalEdges
      , reportEulerChar     = eulerCharacteristic complex
      , reportHarmonicEdges = harmonicCount
      , reportDriftEdges    = driftCount
      , reportCoherencePct  = pct
      , reportIsHarmonic    = harmonic
      , reportObstructions  = obstructions
      }
  where
    formatObstructionMsg e u v s t =
      "Boundary obstruction on edge (" <> u <> " ⊵ " <> v <> ", "
      <> contractDimensionName (edgeDimension e) <> "): expected "
      <> formatContractVal s <> ", observed " <> formatContractVal t <> ". "
      <> contractDimensionRemediation (edgeDimension e)

    formatContractVal (ContractText (Just txt)) = "'" <> txt <> "'"
    formatContractVal (ContractText Nothing)    = "Nothing"
    formatContractVal (ContractBool b)          = T.show b

-- | Formats a 'SheafReport' into an aligned terminal diagnostic ASCII report.
formatSheafReport :: SheafReport -> Text
formatSheafReport rep = T.unlines $
  [ "================================================================================"
  , " Gachi Cellular Sheaf Coherence Report (~/src/PLAN.md §1.A, Milestone 3.5)"
  , "================================================================================"
  , " Complex Topology:   1-D Cell Complex G = (V, E)"
  , " 0-Cells (Vertices): " <> T.show (length (reportVertices rep))
      <> " " <> T.pack (show (reportVertices rep))
  , " 1-Cells (Edges):    " <> T.show (reportEdgeCount rep)
      <> " evaluated across " <> T.show (length allContractDimensions) <> " contract dimensions"
  , " Euler Char (\x03c7):     " <> T.show (reportEulerChar rep)
  , "--------------------------------------------------------------------------------"
  , " Cohomological Invariants:"
  , " [+] 0-th Cohomology H^0 (Harmonic Equilibrium): ker \x03b4\x2070"
  , "     Status: " <> T.show (reportHarmonicEdges rep) <> " / " <> T.show (reportEdgeCount rep)
      <> " edges in harmonic resonance (" <> formatPct (reportCoherencePct rep) <> "% coherent)"
  ]
  ++ (if reportIsHarmonic rep
        then [ "     System State: HARMONIC EQUILIBRIUM (zero boundary obstruction)" ]
        else [ "     System State: DRIFT DETECTED" ])
  ++
  [ " [-] 1-st Cohomology H^1 (Boundary Obstructions): coker \x03b4\x2070"
  , "     Status: " <> T.show (reportDriftEdges rep) <> " boundary obstructions localized"
  ]
  ++ (if null (reportObstructions rep)
        then [ "--------------------------------------------------------------------------------"
             , " [+] All repositories satisfy ecosystem contracts in total harmonic equilibrium."
             , "================================================================================"
             ]
        else
          [ "--------------------------------------------------------------------------------"
          , " Localized Cohomological Obstructions (H^1):"
          , "--------------------------------------------------------------------------------"
          ]
          ++ concatMap formatObstructionCard (reportObstructions rep)
          ++
          [ "================================================================================" ]
     )
  where
    formatPct val =
      let whole = truncate val :: Int
          dec = truncate (val * 10) `mod` 10 :: Int
      in T.show whole <> "." <> T.show dec

    formatObstructionCard obs =
      let dim = edgeDimension (obstructionEdge obs)
      in [ " Edge: " <> obstructionSource obs <> " \x22b5 " <> obstructionTarget obs
             <> " (" <> contractDimensionName dim <> ")"
         , "   Expected:    " <> formatVal (sourceRestriction obs)
         , "   Observed:    " <> formatVal (targetRestriction obs)
         , "   Remediation: " <> contractDimensionRemediation dim
         , ""
         ]

    formatVal (ContractText (Just txt)) = "'" <> txt <> "'"
    formatVal (ContractText Nothing)    = "Missing / Not Specified"
    formatVal (ContractBool True)       = "Compliant (True)"
    formatVal (ContractBool False)      = "Missing / Non-Compliant (False)"

--------------------------------------------------------------------------------
-- 6. Live Filesystem Inspection Routines
--------------------------------------------------------------------------------

-- | Traverses upward from a given directory to locate the authoritative
-- workspace or repository root containing @.git@, @cabal.project@, or @project.dhall@.
findRepositoryRoot :: FilePath -> IO FilePath
findRepositoryRoot startPath = do
  absPath <- canonicalizePath startPath
  let searchUp p = do
        hasGit <- doesDirectoryExist (p </> ".git")
        hasProj <- doesFileExist (p </> "cabal.project")
        hasDhall <- doesFileExist (p </> "project.dhall")
        if hasGit || hasProj || hasDhall
          then pure p
          else do
            let parent = takeDirectory p
            if parent == p
              then pure absPath
              else searchUp parent
  searchUp absPath

-- | Inspects a repository directory and extracts its 'RepoStalk'.
inspectRepoStalk :: FilePath -> IO RepoStalk
inspectRepoStalk rawPath = do
  repoPath <- findRepositoryRoot rawPath
  let repoName = T.pack (takeFileName repoPath)
  ghcVer <- inspectRepoGhcVersion repoPath
  cabalVer <- inspectRepoCabalVersion repoPath
  lic <- inspectRepoLicense repoPath

  hasCommitMsg <- doesFileExist (repoPath </> ".githooks" </> "commit-msg")
  hasPreCommit <- doesFileExist (repoPath </> ".githooks" </> "pre-commit")
  hasGitMsg <- doesFileExist (repoPath </> ".gitmessage")
  hasHLint <- doesFileExist (repoPath </> ".hlint.yaml")

  hasGhCi <- doesFileExist (repoPath </> ".github" </> "workflows" </> "ci.yml")
  hasGlCi <- doesFileExist (repoPath </> ".gitlab-ci.yml")
  let hasCI = hasGhCi || hasGlCi

  hasAgents <- doesFileExist (repoPath </> "AGENTS.md")

  hasRunner <- checkVerifyRunner repoPath repoName

  pure RepoStalk
    { stalkRepoName        = repoName
    , stalkRepoPath        = repoPath
    , stalkGhcVersion      = ghcVer
    , stalkCabalVersion    = cabalVer
    , stalkLicense         = lic
    , stalkHasCommitMsg    = hasCommitMsg
    , stalkHasPreCommit    = hasPreCommit
    , stalkHasGitMessage   = hasGitMsg
    , stalkHasHLint        = hasHLint
    , stalkHasCIWorkflow   = hasCI
    , stalkHasAgentsMd     = hasAgents
    , stalkHasVerifyRunner = hasRunner
    }

-- | Inspects GHC compiler version pinning from @cabal.project@ or @*.cabal@.
inspectRepoGhcVersion :: FilePath -> IO (Maybe Text)
inspectRepoGhcVersion repoPath = do
  let projPath = repoPath </> "cabal.project"
  hasProj <- doesFileExist projPath
  if hasProj
    then do
      txt <- TIO.readFile projPath `catch` (\(_ :: SomeException) -> pure "")
      case extractGhcFromText txt of
        Just v  -> pure (Just v)
        Nothing -> inspectFromCabal
    else inspectFromCabal
  where
    extractGhcFromText txt =
      let ls = T.lines txt
          findCompiler l =
            let s = T.strip l
            in if "with-compiler:" `T.isPrefixOf` s
                 then let rest = T.strip (T.drop 14 s)
                      in if "ghc-" `T.isPrefixOf` rest
                           then Just (T.drop 4 rest)
                           else Just rest
                 else Nothing
      in case mapMaybe findCompiler ls of
           (v:_) -> Just v
           []    -> Nothing

    inspectFromCabal = do
      cabalFiles <- findCabalFiles repoPath
      results <- mapM readGhcFromCabal cabalFiles
      let allVers = concat results
      pure (if "9.14.1" `elem` allVers
              then Just "9.14.1"
              else case allVers of { (v:_) -> Just v; [] -> Nothing })

    readGhcFromCabal path = do
      txt <- TIO.readFile path `catch` (\(_ :: SomeException) -> pure "")
      let ls = T.lines txt
          findGhcLine l =
            let s = T.strip l
            in if "GHC ==" `T.isInfixOf` s
                 then let afterEq = T.strip (snd (T.breakOnEnd "==" s))
                          v = T.takeWhile (\c -> isDigit c || c == '.') afterEq
                      in if T.null v then Nothing else Just v
                 else Nothing
      pure (mapMaybe findGhcLine ls)

-- | Inspects Cabal specification version from @*.cabal@ files.
inspectRepoCabalVersion :: FilePath -> IO (Maybe Text)
inspectRepoCabalVersion repoPath = do
  cabalFiles <- findCabalFiles repoPath
  case cabalFiles of
    [] -> pure Nothing
    (c:_) -> do
      txt <- TIO.readFile c `catch` (\(_ :: SomeException) -> pure "")
      let ls = T.lines txt
          findCabalVer l =
            let s = T.strip l
            in if "cabal-version:" `T.isPrefixOf` s
                 then Just (T.strip (T.drop 14 s))
                 else Nothing
      pure (case mapMaybe findCabalVer ls of { (v:_) -> Just v; [] -> Nothing })

-- | Inspects license stanza from @*.cabal@ or root @LICENSE@ file.
inspectRepoLicense :: FilePath -> IO (Maybe Text)
inspectRepoLicense repoPath = do
  cabalFiles <- findCabalFiles repoPath
  cabalLic <- case cabalFiles of
    (c:_) -> do
      txt <- TIO.readFile c `catch` (\(_ :: SomeException) -> pure "")
      let ls = T.lines txt
          findLic l =
            let s = T.strip l
            in if "license:" `T.isPrefixOf` s
                 then Just (T.strip (T.drop 8 s))
                 else Nothing
      pure (case mapMaybe findLic ls of { (v:_) -> Just v; [] -> Nothing })
    [] -> pure Nothing

  case cabalLic of
    Just lic -> pure (Just lic)
    Nothing  -> do
      let licPath = repoPath </> "LICENSE"
      hasLic <- doesFileExist licPath
      if hasLic
        then do
          txt <- TIO.readFile licPath `catch` (\(_ :: SomeException) -> pure "")
          if "European Union Public Licence" `T.isInfixOf` txt || "EUPL" `T.isInfixOf` txt
            then pure (Just "EUPL-1.2")
            else pure (Just "LICENSE-FOUND")
        else pure Nothing

-- | Checks for an executable verification runner under @bin/@.
checkVerifyRunner :: FilePath -> Text -> IO Bool
checkVerifyRunner repoPath repoName = do
  let explicitRunner = repoPath </> "bin" </> (T.unpack repoName ++ "-verify")
  hasExplicit <- doesFileExist explicitRunner
  if hasExplicit
    then do
      perms <- getPermissions explicitRunner
      pure (executable perms)
    else do
      let binDir = repoPath </> "bin"
      hasBin <- doesDirectoryExist binDir
      if hasBin
        then do
          files <- listDirectory binDir
          let verifyScripts = filter (\f -> "-verify" `T.isSuffixOf` T.pack f) files
          case verifyScripts of
            [] -> pure False
            (v:_) -> do
              perms <- getPermissions (binDir </> v)
              pure (executable perms)
        else pure False

-- | Finds all @.cabal@ files within a repository directory or @packages/*/@.
findCabalFiles :: FilePath -> IO [FilePath]
findCabalFiles repoPath = do
  rootEntries <- listDirectory repoPath `catch` (\(_ :: SomeException) -> pure [])
  let rootCabals = [ repoPath </> f | f <- rootEntries, takeExtension f == ".cabal" ]
  if not (null rootCabals)
    then pure rootCabals
    else do
      let pkgsDir = repoPath </> "packages"
      hasPkgs <- doesDirectoryExist pkgsDir
      if hasPkgs
        then do
          pkgEntries <- listDirectory pkgsDir `catch` (\(_ :: SomeException) -> pure [])
          nestedCabals <- mapM (findPkgCabal pkgsDir) pkgEntries
          pure (concat nestedCabals)
        else pure []
  where
    findPkgCabal baseDir pkgName = do
      let dir = baseDir </> pkgName
      isDir <- doesDirectoryExist dir
      if isDir
        then do
          entries <- listDirectory dir `catch` (\(_ :: SomeException) -> pure [])
          pure [ dir </> f | f <- entries, takeExtension f == ".cabal" ]
        else pure []

-- | Audits a single target repository using the cellular sheaf model.
auditSheafTarget :: FilePath -> IO SheafReport
auditSheafTarget targetDir = do
  stalk <- inspectRepoStalk targetDir
  let clientName = stalkRepoName stalk
      complex = buildCanonicalSheafComplex [clientName]
      c0 = Cochain0 (Map.fromList [("canonical", canonicalRepoStalk), (clientName, stalk)])
  pure (evaluateSheafCoherence complex c0)

-- | Audits all discovered ecosystem repositories within a parent directory.
auditEcosystemSheaf :: FilePath -> IO SheafReport
auditEcosystemSheaf parentDir = do
  repoPaths <- discoverEcosystemRepositories parentDir
  stalks <- mapM inspectRepoStalk repoPaths
  let clientNames = map stalkRepoName stalks
      complex = buildCanonicalSheafComplex clientNames
      stalkPairs = ("canonical", canonicalRepoStalk) : zip clientNames stalks
      c0 = Cochain0 (Map.fromList stalkPairs)
  pure (evaluateSheafCoherence complex c0)
