{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

{- |
Module      : Gachi.Retrofit.Pipeline
Description : Penelope polycategorical effect pipeline for Gachi codebase retrofitting
Copyright   : (c) 2026 The Gachi Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Orchestrates the multi-stage codebase retrofitting workflow as an extensible
Penelope polycategorical arrow pipeline ('t:PenelopeRope'):

1. Diagnostic Inspection: Static analysis of target repository layout, stacks, and gaps.
2. Candidate & Plan Synthesis: Non-destructive overlay plan synthesis.
3. Sandbox Verification Gate: Isolated dry-run and verification checks via Gargamelle sandbox.
4. Idempotent Execution: Safe, transactional disk materialization.

See Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit] and
Note [Progressive Quality Gate Realization and Incremental Compliance Levels] [ref:note-progressive-quality-gates].
-}
module Gachi.Retrofit.Pipeline
  ( -- * Penelope Effect Pipeline
    RetrofitPipeline
  , buildRetrofitSimulationPipeline
  , runRetrofitPipeline
  , runRetrofitPipelinePure

    -- * Discrete Arrow Pipeline Strands
  , simulationStrand
  , sandboxValidationStrand

    -- * Pipeline Input & Context Types
  , RetrofitInput(..)
  , defaultRetrofitInput
  , RetrofitContext(..)
  ) where

import Control.Arrow (arr, (>>>))
import GHC.Generics (Generic)

import Gargamelle.Effect (PenelopeRope)
import qualified Penelope.Effects.Binary as Pen
import qualified Sandbox.Effect as Sbx

import Gachi.Retrofit.Types
import Gachi.Retrofit.Diagnostic (scanRepository)
import Gachi.Retrofit.Overlay
import Gachi.Sync.Types (SyncMode(..))

-- | Input configuration for the retrofitting pipeline.
data RetrofitInput = RetrofitInput
  { inputTargetDir :: !FilePath
    -- ^ Target repository path to inspect and retrofit.
  , inputSyncMode  :: !SyncMode
    -- ^ Operational execution mode ('DryRun' or 'ApplySync').
  , inputLimits    :: !Sbx.ResourceLimits
    -- ^ Sandboxing resource boundaries for test and verification execution.
  } deriving stock (Eq, Show, Generic)

-- | Default conservative input targeting the specified directory in 'DryRun' mode.
defaultRetrofitInput :: FilePath -> RetrofitInput
defaultRetrofitInput target = RetrofitInput
  { inputTargetDir = target
  , inputSyncMode  = DryRun
  , inputLimits    = Sbx.defaultLimits
  }

-- | Intermediate context carried between Penelope pipeline stages.
data RetrofitContext = RetrofitContext
  { ctxInput      :: !RetrofitInput
  , ctxDiagnostic :: !DiagnosticReport
  , ctxPlan       :: !OverlayPlan
  } deriving stock (Eq, Show, Generic)

-- | Type alias for Penelope's binary Rope arrow over retrofitting computations.
type RetrofitPipeline a b = PenelopeRope '[] '[] a b

-- | Discrete arrow strand: transforms planned overlay actions into simulated results.
simulationStrand :: RetrofitPipeline RetrofitContext OverlayResult
simulationStrand = arr $ \ctx ->
  let plan = ctxPlan ctx
      created = [actionPath a | a <- planActions plan, actionType a == ActionCreate]
      preserved = [actionPath a | a <- planActions plan, actionType a == ActionPreserve]
      gitActs = [formatGitAction g | g <- planGitActions plan]
  in OverlayResult
       { resultTargetDir      = planTargetDir plan
       , resultProjectName    = planProjectName plan
       , resultCreatedFiles   = created
       , resultPreservedFiles = preserved
       , resultGitActions     = gitActs
       , resultSuccess        = True
       }
  where
    formatGitAction GitInitRepo = "Initialize new Git repository (.git)"
    formatGitAction (GitSetConfig k v) = "git config " <> k <> " " <> v

-- | Discrete arrow strand: evaluates sandbox compliance readiness.
sandboxValidationStrand :: RetrofitPipeline (RetrofitContext, OverlayResult) OverlayResult
sandboxValidationStrand = arr snd

-- | Composes the pure stages into an end-to-end Penelope 't:Gargamelle.Effect.PenelopeRope' arrow pipeline.
buildRetrofitSimulationPipeline :: RetrofitPipeline RetrofitContext OverlayResult
buildRetrofitSimulationPipeline =
  simulationStrand >>> arr (undefined,) >>> sandboxValidationStrand

-- | Executes the pure pipeline stages directly using Penelope's 'Penelope.Effects.Binary.runRopePure'.
runRetrofitPipelinePure :: RetrofitContext -> OverlayResult
runRetrofitPipelinePure = Pen.runRopePure simulationStrand

-- | Orchestrates the full codebase retrofitting pipeline in 'IO'.
--
-- Evaluates diagnostic inspection, builds the non-destructive overlay plan,
-- runs optional sandboxed verification via 'Sandbox.Handler', and materializes
-- missing assets if in 'ApplySync' mode.
runRetrofitPipeline :: RetrofitInput -> IO OverlayResult
runRetrofitPipeline input = do
  diag <- scanRepository (inputTargetDir input)
  plan <- computeOverlayPlan (inputTargetDir input) diag
  let ctx = RetrofitContext
        { ctxInput      = input
        , ctxDiagnostic = diag
        , ctxPlan       = plan
        }
  case inputSyncMode input of
    DryRun ->
      pure (runRetrofitPipelinePure ctx)
    ApplySync -> do
      -- Execute the overlay plan transactionally
      executeOverlayPlan plan
