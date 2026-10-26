{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Sync.Remote
-- Description: Multi-remote topology management, provider compliance auditing, and replication synchronization
--
-- This module implements Milestone 3.4 of the Gachi strategic roadmap (~/src/PLAN.md §1.A).
-- It establishes declarative models and operational synchronization routines for
-- the 5-remote ecosystem replication topology (Dimension 6), enforcing sovereign
-- peer-to-peer distribution and provider compliance auditing across all checkouts.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [ref:note-standardization-matrix], and Note [Multi-Remote Replication Topology and Provider Compliance]
-- [ref:note-remote-topology], all ecosystem repositories replicate across five
-- canonical remotes, balancing decentralized sovereignty, community resilience,
-- and global developer accessibility.
--
-- == Note [Multi-Remote Replication Topology and Provider Compliance]
-- [tag:note-remote-topology]
--
-- Relying on a single proprietary hosting forge (such as GitHub) introduces an
-- existential single point of failure, censorship vulnerability, and platform
-- lock-in. A healthy open-source ecosystem must maintain sovereign, automated
-- replication across heterogeneous governance tiers:
--
-- 1.  __Sovereign Peer-to-Peer Identity ('RemotePeerToPeer'):__
--     Anchored on Radicle (@rad@: @rad://<project-urn>@). Uses cryptographic
--     DIDs and local gossip networks without centralized servers or single-entity
--     terms of service. Guarantees immutable ownership and censorship resistance.
--
-- 2.  __Community Non-Profit Forges ('RemoteCommunity'):__
--     Mirrored to trusted non-profit community instances:
--     * __Framagit__ (@framagit@: @git@framagit.org:NadiaYvette/<project>.git@):
--       GitLab Community Edition operated by the French digital commons non-profit Framasoft.
--     * __Disroot__ (@disroot@: @git@git.disroot.org:NadiaYvette/<project>.git@):
--       Forgejo/Gitea instance operated by the privacy-centric Disroot Foundation.
--
-- 3.  __Global Commercial Mirrors ('RemoteCommercial'):__
--     Maintained for discoverability, high-bandwidth package ingestion, and CI compute:
--     * __GitHub__ (@github@: @git@github.com:NadiaYvette/<project>.git@):
--       High-resource commercial runner execution and global contributor visibility.
--     * __GitCode__ (@gitcode@: @git@gitcode.com:NadiaYvette/<project>.git@):
--       High-speed regional mirror ensuring accessibility across global network partitions.
--
-- 4.  __Aggregate Multi-Target Push Remote ('RemoteAggregate'):__
--     An optional convenience remote (@all@) configured with multiple push URLs
--     enabling a single command (@git push all master@) to broadcast changes
--     synchronously across all configured mirrors.
--
-- == Provider Compliance & Exclusion Policy
--
-- Not all Git hosting services are compatible with ecosystem governance invariants:
-- * __SourceHut Exclusion:__ Services such as SourceHut (@git.sr.ht@) enforce
--   restrictive terms of service prohibiting automated AI-assisted coding tools,
--   and require idiosyncratic email-only patch submission workflows that reject
--   standard Git push replication and pull request verification. Consequently,
--   SourceHut remotes are formally excluded and flagged as policy violations.
-- * __Plaintext Insecurity:__ Plaintext HTTP remotes (@http://@) without TLS
--   encryption are strictly prohibited to prevent man-in-the-middle attacks.
--
-- The remote management engine automatically audits target repositories, flags
-- non-compliant remotes for removal, detects missing canonical remotes, and provides
-- atomic synchronization to restore the canonical 5-remote topology.
--
-- == Operational Transition Pipeline
--
-- Remote synchronization progresses through a three-stage functional pipeline:
--
-- 1.  __Inspection ('auditRemoteTopology' / 'auditRemoteTopologyQuick'):__
--     Executes @git remote -v@ within the checkout, parses the output via
--     'parseGitRemoteOutput', and compares existing remotes against expected
--     canonical specifications via 'evaluateRemoteTopology'.
--
-- 2.  __Planning ('computeRemoteSyncPlan'):__
--     Purity-preserving step transforming 'RemoteTopologyReport' into an atomic
--     'RemoteSyncPlan' composed of concrete 'RemoteSyncAction' mutations.
--
-- 3.  __Execution ('executeRemoteSyncPlan' / 'syncRemoteTopologyQuick'):__
--     Applies the plan under 'SyncMode'. In 'DryRun', preview logs are produced;
--     in 'ApplySync', idempotent Git commands mutate the repository configuration.
--
-- = Worked Example: Auditing Remote Topology
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Remote
-- >>> let proj = defaultProject "gachi" (Author "Nadia" "nadia@example.com")
-- >>> let existing = parseGitRemoteOutput "github\tgit@github.com:NadiaYvette/gachi.git (fetch)\n"
-- >>> let report = evaluateRemoteTopology "gachi" (defaultRemoteSpecsFor "gachi") existing
-- >>> remoteMissingCount report >= 4
-- True
-- >>> isProviderCompliant "git@github.com:NadiaYvette/gachi.git"
-- True
-- >>> isProviderCompliant "git@git.sr.ht:~user/gachi"
-- False
module Gachi.Sync.Remote
  ( -- * Remote Category & Compliance Types
    RemoteCategory(..)
  , ProviderPolicy(..)
  , ConfiguredRemote(..)
  , RemoteAuditStatus(..)
  , RemoteAuditResult(..)
  , RemoteTopologyReport(..)
  , RemoteSyncAction(..)
  , RemoteSyncPlan(..)

    -- * Provider Compliance & Policy Combinators
  , classifyProvider
  , isProviderCompliant
  , filterCompliantRemotes
  , filterNonCompliantRemotes
  , normalizeRemoteUrl
  , urlsMatch

    -- * Canonical Remote Topology Synthesis
  , canonicalRemoteNames
  , isCanonicalRemoteName
  , canonicalRemoteSpecs
  , defaultRemoteSpecsFor
  , defaultOwnerName

    -- * Deterministic Parsing & Pure Evaluation
  , parseGitRemoteOutput
  , evaluateRemoteTopology
  , computeRemoteSyncPlan
  , formatRemoteReport
  , formatRemoteSyncPlan

    -- * Live Filesystem IO Integration
  , queryGitRemotes
  , auditRemoteTopology
  , auditRemoteTopologyQuick
  , executeRemoteSyncPlan
  , syncRemoteTopology
  , syncRemoteTopologyQuick
  ) where

import Control.Exception (SomeException, catch)
import Data.Either (lefts, rights)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Directory (canonicalizePath, doesFileExist)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeFileName)
import System.Process (readProcessWithExitCode)

import Gachi.Schema.Dhall (decodeProjectFile)
import Gachi.Schema.Project
  ( Author(..)
  , Project
  , RemoteSpec(..)
  , defaultProject
  , projectName
  , projectRemotes
  , remoteName
  , remoteUrl
  )
import Gachi.Sync.Types (SyncMode(..))

--------------------------------------------------------------------------------
-- 1. Remote Category & Compliance Types
--------------------------------------------------------------------------------

-- | Architectural category governing a Git remote in the replication topology.
--
-- Categorizes remotes according to their cryptographic governance model,
-- funding substrate, and infrastructure reliability.
--
-- === The Five Architectural Categories
--
-- 1.  __Sovereign Peer-to-Peer ('RemotePeerToPeer'):__
--     Radicle decentralized nodes identified by cryptographic public key DIDs
--     (@rad://<project-urn>@). Guarantees censorship resistance and local availability
--     without reliance on centralized intermediary servers or commercial terms of service.
--
-- 2.  __Community Non-Profit ('RemoteCommunity'):__
--     Open-source community forges operated by public-interest foundations (e.g. Framagit
--     by Framasoft, Disroot by Disroot Foundation). Guarantees data portability, privacy,
--     and community stewardship.
--
-- 3.  __Commercial Mirrors ('RemoteCommercial'):__
--     High-bandwidth commercial Git hosting providers (e.g. GitHub, GitCode) offering
--     extensive CI compute capacity, edge CDN acceleration, and global discoverability.
--
-- 4.  __Aggregate Multi-Push Remote ('RemoteAggregate'):__
--     Convenience remote identifier (typically @all@) configured with multiple push
--     URLs allowing a single @git push all master@ command to replicate commits across
--     all mirrors synchronously.
--
-- 5.  __Custom Endpoint ('RemoteCustom'):__
--     User-defined remotes (such as private staging forges or personal home servers)
--     operating alongside the standard 5-remote topology.
data RemoteCategory
  = RemotePeerToPeer
    -- ^ Sovereign peer-to-peer storage (Radicle DIDs: @rad://@).
  | RemoteCommunity
    -- ^ Non-profit public-interest community instances (Framagit, Disroot).
  | RemoteCommercial
    -- ^ Global commercial cloud mirrors (GitHub, GitCode).
  | RemoteAggregate
    -- ^ Multi-target aggregate push remote (@all@).
  | RemoteCustom
    -- ^ User-defined custom remote outside the standard 5-forge topology.
  deriving stock (Eq, Show, Ord, Enum, Bounded, Generic)

-- | Hosting provider compliance classification result.
--
-- Distinguishes permitted, policy-compliant repository hosting platforms from
-- excluded services that violate ecosystem governance rules.
--
-- === Exclusion Rationale
--
-- Hosting providers that enforce terms of service restricting automated AI pair
-- programming tooling (e.g. SourceHut) or require proprietary patch email workflows
-- that forbid Git push replication are classified under 'ProviderExcluded'.
-- Plaintext HTTP transport (@http://@) is similarly prohibited due to lack of encryption.
data ProviderPolicy
  = ProviderAllowed !Text
    -- ^ Compliant hosting provider with human-readable provider name (e.g., @"GitHub"@).
  | ProviderExcluded !Text !Text
    -- ^ Non-compliant provider name and detailed rationale for exclusion.
  deriving stock (Eq, Show, Generic)

-- | Represents a Git remote physically configured in a local checkout.
--
-- Encapsulates the remote name, optional fetch URL, and a list of push URLs
-- as discovered via porcelain Git commands (@git remote -v@).
data ConfiguredRemote = ConfiguredRemote
  { crName     :: !Text
    -- ^ Remote identifier string (e.g., @"github"@, @"rad"@, @"origin"@).
  , crFetchUrl :: !(Maybe Text)
    -- ^ Primary fetch URL configured for the remote.
  , crPushUrls :: ![Text]
    -- ^ List of push URLs associated with the remote.
  } deriving stock (Eq, Show, Generic)

-- | Detailed inspection status for an individual Git remote.
--
-- Classified during repository remote topology auditing against expected canonical specs.
data RemoteAuditStatus
  = RemoteCompliant
    -- ^ Remote exists, points to compliant provider, and matches expected canonical URL.
  | RemoteMissing
    -- ^ Canonical remote is absent from the local repository Git configuration.
  | RemoteUrlDrift !Text !Text
    -- ^ Remote exists but configured URL diverges from expected canonical URL.
    -- Carries (ActualUrl, ExpectedUrl).
  | RemoteNonCompliant !Text !Text
    -- ^ Remote points to a prohibited or non-compliant provider.
    -- Carries (ProviderName, ExclusionRationale).
  | RemoteUnknown
    -- ^ Remote exists and is compliant, but is not part of the standard 5-remote topology.
  deriving stock (Eq, Show, Generic)

-- | Audit finding for a single evaluated remote.
data RemoteAuditResult = RemoteAuditResult
  { resRemoteName  :: !Text
    -- ^ Name of the remote evaluated (e.g. @"github"@, @"srht"@).
  , resExpectedUrl :: !(Maybe Text)
    -- ^ Expected canonical URL if this remote is part of the standard topology.
  , resActualUrl   :: !(Maybe Text)
    -- ^ Actual configured URL detected in Git metadata.
  , resStatus      :: !RemoteAuditStatus
    -- ^ Audit classification outcome.
  } deriving stock (Eq, Show, Generic)

-- | Comprehensive audit report covering a repository's remote topology.
data RemoteTopologyReport = RemoteTopologyReport
  { reportRepoDir           :: !FilePath
    -- ^ Filesystem path of the audited repository checkout.
  , reportProject           :: !Text
    -- ^ Declared project name.
  , reportRemotes           :: ![RemoteAuditResult]
    -- ^ List of findings across all audited remotes.
  , reportCompliant         :: !Bool
    -- ^ Overall compliance flag (True iff all canonical remotes exist and 0 non-compliant remotes exist).
  , remoteMissingCount      :: !Int
    -- ^ Total count of missing canonical remotes.
  , remoteDriftCount        :: !Int
    -- ^ Total count of remotes exhibiting URL configuration drift.
  , remoteNonCompliantCount :: !Int
    -- ^ Total count of prohibited or non-compliant remotes detected.
  } deriving stock (Eq, Show, Generic)

-- | Atomic mutation action planned to reconcile remote topology drift.
data RemoteSyncAction
  = ActionAddRemote !Text !Text
    -- ^ Proposes executing @git remote add <name> <url>@.
  | ActionSetUrl !Text !Text
    -- ^ Proposes executing @git remote set-url <name> <url>@ to correct URL drift.
  | ActionAddPushUrl !Text !Text
    -- ^ Proposes executing @git remote set-url --add --push <name> <url>@ for multi-push remotes.
  | ActionRemoveRemote !Text
    -- ^ Proposes executing @git remote remove <name>@ to purge non-compliant remotes.
  | ActionRemoteNoOp !Text
    -- ^ Remote is fully compliant; zero mutation required.
  deriving stock (Eq, Show, Generic)

-- | Operational plan containing atomic actions to align a repository's remotes.
data RemoteSyncPlan = RemoteSyncPlan
  { planTargetRepo    :: !FilePath
    -- ^ Target repository path.
  , planProject       :: !Text
    -- ^ Project identifier.
  , planRemoteActions :: ![RemoteSyncAction]
    -- ^ Ordered sequence of remote configuration actions.
  , planAddCount      :: !Int
    -- ^ Number of remote addition actions planned.
  , planUpdateCount   :: !Int
    -- ^ Number of URL update actions planned.
  , planRemoveCount :: !Int
    -- ^ Number of non-compliant remote removal actions planned.
  } deriving stock (Eq, Show, Generic)

--------------------------------------------------------------------------------
-- 2. Provider Compliance & Policy Combinators
--------------------------------------------------------------------------------

-- | Default GitHub and multi-forge account organization name.
--
-- The authoritative account identifier across commercial and community Git forges.
defaultOwnerName :: Text
defaultOwnerName = "NadiaYvette"

-- | Classifies a remote URL according to ecosystem hosting provider compliance rules.
--
-- === Evaluated Policies & Threat Model
--
-- 1. __Plaintext HTTP Transport Security:__
--    Any URL starting with @"http://"@ is rejected due to lack of cryptographic transport
--    security. In accordance with zero-trust network principles, unencrypted endpoints
--    are susceptible to credential harvesting, commit manipulation, and active
--    man-in-the-middle code injection. Compliant endpoints must employ either SSH
--    (@git\@@) or TLS-wrapped HTTPS (@https:\/\/@).
--
-- 2. __SourceHut Platform Exclusion:__
--    URLs matching @"sr.ht"@ or @"sourcehut"@ are formally prohibited. SourceHut's terms
--    of service restrict automated AI pair programming assistants, and the platform
--    mandates an email-driven patch workflow that deliberately rejects push-based Git
--    replication, branch tracking, and webhook-driven multi-forge CI automation.
--
-- 3.  __Approved Multi-Forge Targets:__
--     * __GitHub__ (@github.com@): Commercial primary mirror for high-capacity runner CI.
--     * __GitCode__ (@gitcode.com@): Regional mirror guaranteeing high availability.
--     * __Framagit__ (@framagit.org@): Community GitLab mirror operated by Framasoft.
--     * __Disroot__ (@disroot.org@): Privacy-centric Forgejo mirror by Disroot Foundation.
--     * __Radicle__ (@rad://@): Sovereign decentralized peer-to-peer repository storage.
classifyProvider :: Text -> ProviderPolicy
classifyProvider rawUrl
  -- Check plaintext transport insecurity
  | "http://" `T.isPrefixOf` urlLower =
      ProviderExcluded "Insecure Plaintext HTTP"
        "Plaintext HTTP remotes are prohibited; use SSH (git@) or HTTPS (https://)."
  -- Check SourceHut exclusion policy
  | "sr.ht" `T.isInfixOf` urlLower || "sourcehut" `T.isInfixOf` urlLower =
      ProviderExcluded "SourceHut (git.sr.ht)"
        "SourceHut is prohibited due to terms restricting automated AI tooling and incompatible email-only workflows."
  -- Approved canonical providers
  | "github.com" `T.isInfixOf` urlLower =
      ProviderAllowed "GitHub"
  | "gitcode.com" `T.isInfixOf` urlLower =
      ProviderAllowed "GitCode"
  | "framagit.org" `T.isInfixOf` urlLower || "gitlab" `T.isInfixOf` urlLower =
      ProviderAllowed "Framagit (GitLab CE)"
  | "disroot.org" `T.isInfixOf` urlLower || "forgejo" `T.isInfixOf` urlLower || "gitea" `T.isInfixOf` urlLower =
      ProviderAllowed "Disroot (Forgejo)"
  | "rad://" `T.isPrefixOf` rawUrl =
      ProviderAllowed "Radicle P2P"
  -- Custom compliant host
  | otherwise =
      ProviderAllowed "Custom Compliant Host"
  where
    urlLower = T.toLower rawUrl

-- | Predicate checking whether a remote URL satisfies provider compliance rules.
isProviderCompliant :: Text -> Bool
isProviderCompliant checkUrl = case classifyProvider checkUrl of
  ProviderAllowed _      -> True
  ProviderExcluded _ _   -> False

-- | Filters a list of 'RemoteSpec' records, retaining only compliant remotes.
--
-- Guaranteed to discard any remote pointing to prohibited services (such as
-- SourceHut) or insecure plaintext HTTP endpoints.
--
-- === Invariants
--
-- All remotes in the output satisfy 'isProviderCompliant'.
filterCompliantRemotes :: [RemoteSpec] -> [RemoteSpec]
filterCompliantRemotes = filter (isProviderCompliant . remoteUrl)

-- | Extracts non-compliant 'RemoteSpec' records paired with their exclusion rationale.
--
-- Returns a list of @(remote, rationale)@ pairs identifying prohibited remotes
-- that must be purged or updated during topology synchronization.
filterNonCompliantRemotes :: [RemoteSpec] -> [(RemoteSpec, Text)]
filterNonCompliantRemotes = mapMaybe extractExcluded
  where
    extractExcluded r = case classifyProvider (remoteUrl r) of
      ProviderExcluded _ reason -> Just (r, reason)
      ProviderAllowed _         -> Nothing

-- | Normalizes a Git remote URL for semantic equivalence comparison.
--
-- Strips trailing @.git@ suffixes, trailing slashes, and converts to lowercase.
--
-- === Worked Example
--
-- >>> normalizeRemoteUrl "git@github.com:NadiaYvette/gachi.git"
-- "git@github.com:nadiayvette/gachi"
-- >>> normalizeRemoteUrl "https://github.com/NadiaYvette/gachi/"
-- "https://github.com/nadiayvette/gachi"
normalizeRemoteUrl :: Text -> Text
normalizeRemoteUrl raw =
  let lower = T.toLower (T.strip raw)
      noSlash = if "/" `T.isSuffixOf` lower then T.dropEnd 1 lower else lower
      noGit = if ".git" `T.isSuffixOf` noSlash then T.dropEnd 4 noSlash else noSlash
  in noGit

-- | Compares two Git remote URLs for semantic equivalence.
--
-- Considers SSH and HTTPS URLs targeting the same repository on the same forge as equivalent,
-- and ignores trailing @.git@ extensions and trailing slashes.
urlsMatch :: Text -> Text -> Bool
urlsMatch u1 u2 =
  let n1 = normalizeRemoteUrl u1
      n2 = normalizeRemoteUrl u2
  in n1 == n2 || stripProtocol n1 == stripProtocol n2
  where
    stripProtocol u =
      let dropPrefix' pfx t = if pfx `T.isPrefixOf` t then T.drop (T.length pfx) t else t
          noScheme = dropPrefix' "https://" (dropPrefix' "http://" (dropPrefix' "ssh://" (dropPrefix' "rad://" u)))
          noUser = dropPrefix' "git@" noScheme
      in T.replace ":" "/" noUser

--------------------------------------------------------------------------------
-- 3. Canonical Remote Topology Synthesis
--------------------------------------------------------------------------------

-- | Canonical remote names comprising the authoritative 5-forge replication topology.
canonicalRemoteNames :: [Text]
canonicalRemoteNames = ["rad", "github", "gitcode", "framagit", "disroot"]

-- | Predicate checking whether a remote name belongs to the canonical 5-forge topology.
isCanonicalRemoteName :: Text -> Bool
isCanonicalRemoteName candidateName = candidateName `elem` canonicalRemoteNames

-- | Synthesizes the canonical 5-remote topology for a given account owner and project name.
--
-- Constructs RemoteSpec entries for:
-- 1. @"rad"@: Radicle decentralized peer-to-peer URN.
-- 2. @"github"@: GitHub commercial mirror.
-- 3. @"gitcode"@: GitCode regional mirror.
-- 4. @"framagit"@: Framagit community GitLab mirror.
-- 5. @"disroot"@: Disroot community Forgejo mirror.
canonicalRemoteSpecs :: Text -> Text -> [RemoteSpec]
canonicalRemoteSpecs owner pName =
  [ RemoteSpec "rad"      ("rad://" <> pName)
  , RemoteSpec "github"   ("git@github.com:" <> owner <> "/" <> pName <> ".git")
  , RemoteSpec "gitcode"  ("git@gitcode.com:" <> owner <> "/" <> pName <> ".git")
  , RemoteSpec "framagit" ("git@framagit.org:" <> owner <> "/" <> pName <> ".git")
  , RemoteSpec "disroot"  ("git@git.disroot.org:" <> owner <> "/" <> pName <> ".git")
  ]

-- | Synthesizes the default 5-remote topology using the standard owner (@NadiaYvette@).
defaultRemoteSpecsFor :: Text -> [RemoteSpec]
defaultRemoteSpecsFor = canonicalRemoteSpecs defaultOwnerName

--------------------------------------------------------------------------------
-- 4. Deterministic Parsing & Pure Evaluation
--------------------------------------------------------------------------------

-- | Pure parser transforming the output of @git remote -v@ into structured 'ConfiguredRemote' records.
--
-- Handles multiple push URLs and separate fetch/push specifications cleanly.
--
-- === Format Specification
--
-- Expected input lines follow standard Git porcelain format:
-- @<name>TAB<url>SPACE(fetch)@ or @<name>TAB<url>SPACE(push)@
parseGitRemoteOutput :: Text -> [ConfiguredRemote]
parseGitRemoteOutput raw =
  let rawLines = filter (not . T.null . T.strip) (T.lines raw)
      parsedEntries = mapMaybe parseLine rawLines
      grouped = foldl insertEntry Map.empty parsedEntries
  in map toConfigured (Map.toList grouped)
  where
    parseLine :: Text -> Maybe (Text, Text, Bool)
    parseLine line =
      let parts = T.words line
      in case parts of
        (rName : rUrl : rType : _) ->
          let isPush = "(push)" `T.isPrefixOf` rType
          in Just (rName, rUrl, isPush)
        _ -> Nothing

    insertEntry acc (rName, rUrl, isPush) =
      let (mFetch, pushes) = fromMaybe (Nothing, []) (Map.lookup rName acc)
          updated = if isPush
            then (mFetch, pushes ++ [rUrl | rUrl `notElem` pushes])
            else (Just rUrl, pushes)
      in Map.insert rName updated acc

    toConfigured (rName, (mFetch, pushes)) =
      ConfiguredRemote
        { crName     = rName
        , crFetchUrl = mFetch
        , crPushUrls = pushes
        }

-- | Pure evaluation routine assessing configured remotes against expected canonical specs.
--
-- Detects:
-- * Missing canonical remotes that must be added.
-- * Remotes exhibiting URL drift requiring reconciliation.
-- * Non-compliant or prohibited remotes (e.g. SourceHut) that must be removed.
-- * Unknown remotes configured outside the canonical topology.
evaluateRemoteTopology
  :: Text
  -- ^ Project name identifier.
  -> [RemoteSpec]
  -- ^ Expected canonical remote specifications.
  -> [ConfiguredRemote]
  -- ^ Physically configured remotes parsed from Git.
  -> RemoteTopologyReport
evaluateRemoteTopology pName expected configured =
  let configMap = Map.fromList [(crName r, r) | r <- configured]
      expectedNames = [remoteName r | r <- expected]

      -- 1. Evaluate expected canonical remotes
      expectedResults = map (evaluateExpected configMap) expected

      -- 2. Evaluate extra/unknown configured remotes
      extraConfigured = filter (\r -> crName r `notElem` expectedNames) configured
      extraResults = map evaluateExtra extraConfigured

      allResults = expectedResults ++ extraResults

      missingC = length [() | r <- allResults, case resStatus r of RemoteMissing -> True; _ -> False]
      driftC   = length [() | r <- allResults, case resStatus r of RemoteUrlDrift {} -> True; _ -> False]
      nonCompC = length [() | r <- allResults, case resStatus r of RemoteNonCompliant {} -> True; _ -> False]

      isCompliant = missingC == 0 && driftC == 0 && nonCompC == 0
  in RemoteTopologyReport
    { reportRepoDir           = ""
    , reportProject           = pName
    , reportRemotes           = allResults
    , reportCompliant         = isCompliant
    , remoteMissingCount      = missingC
    , remoteDriftCount        = driftC
    , remoteNonCompliantCount = nonCompC
    }
  where
    evaluateExpected configMap spec =
      let rName = remoteName spec
          expUrl = remoteUrl spec
      in case Map.lookup rName configMap of
        Nothing ->
          RemoteAuditResult rName (Just expUrl) Nothing RemoteMissing
        Just conf ->
          let actUrl = fromMaybe "" (crFetchUrl conf)
          in case classifyProvider actUrl of
            ProviderExcluded pName' reason ->
              RemoteAuditResult rName (Just expUrl) (Just actUrl) (RemoteNonCompliant pName' reason)
            ProviderAllowed _ ->
              if urlsMatch actUrl expUrl
                then RemoteAuditResult rName (Just expUrl) (Just actUrl) RemoteCompliant
                else RemoteAuditResult rName (Just expUrl) (Just actUrl) (RemoteUrlDrift actUrl expUrl)

    evaluateExtra conf =
      let rName = crName conf
          actUrl = fromMaybe "" (crFetchUrl conf)
      in case classifyProvider actUrl of
        ProviderExcluded pName' reason ->
          RemoteAuditResult rName Nothing (Just actUrl) (RemoteNonCompliant pName' reason)
        ProviderAllowed _ ->
          RemoteAuditResult rName Nothing (Just actUrl) RemoteUnknown

-- | Computes a deterministic 'RemoteSyncPlan' from a 'RemoteTopologyReport'.
--
-- Translates audit findings into concrete Git actions:
-- * 'RemoteMissing' -> 'ActionAddRemote'
-- * 'RemoteUrlDrift' -> 'ActionSetUrl'
-- * 'RemoteNonCompliant' -> 'ActionRemoveRemote'
computeRemoteSyncPlan :: RemoteTopologyReport -> RemoteSyncPlan
computeRemoteSyncPlan report =
  let actions = mapMaybe actionForResult (reportRemotes report)
      adds    = length [() | ActionAddRemote {} <- actions]
      updates = length [() | ActionSetUrl {} <- actions]
      removes = length [() | ActionRemoveRemote {} <- actions]
  in RemoteSyncPlan
    { planTargetRepo    = reportRepoDir report
    , planProject       = reportProject report
    , planRemoteActions = actions
    , planAddCount      = adds
    , planUpdateCount   = updates
    , planRemoveCount   = removes
    }
  where
    actionForResult res = case resStatus res of
      RemoteMissing ->
        case resExpectedUrl res of
          Just expUrl' -> Just (ActionAddRemote (resRemoteName res) expUrl')
          Nothing      -> Nothing
      RemoteUrlDrift _ expUrl' ->
        Just (ActionSetUrl (resRemoteName res) expUrl')
      RemoteNonCompliant _ _ ->
        Just (ActionRemoveRemote (resRemoteName res))
      RemoteCompliant ->
        Just (ActionRemoteNoOp (resRemoteName res))
      RemoteUnknown ->
        Nothing

-- | Formats a 'RemoteTopologyReport' into a clean ASCII diagnostic table for CLI rendering.
formatRemoteReport :: RemoteTopologyReport -> Text
formatRemoteReport report =
  let header =
        [ "=========================================================================================="
        , "  Gachi Multi-Remote Topology Audit: " <> reportProject report
        , "  Note [Multi-Remote Replication Topology and Provider Compliance] [ref:note-remote-topology]"
        , "=========================================================================================="
        , "  Remote Name   | Status        | Configured / Actual URL"
        , "----------------+---------------+---------------------------------------------------------"
        ]
      rows = map formatResultRow (reportRemotes report)
      summary =
        [ "----------------+---------------+---------------------------------------------------------"
        , "  Total Evaluated: " <> T.pack (show (length (reportRemotes report)))
          <> " | Missing: " <> T.pack (show (remoteMissingCount report))
          <> " | Drifted: " <> T.pack (show (remoteDriftCount report))
          <> " | Prohibited: " <> T.pack (show (remoteNonCompliantCount report))
        , "  Compliance: " <> (if reportCompliant report then "PASS (Topology Fully Aligned)" else "DRIFT DETECTED")
        , "=========================================================================================="
        ]
  in T.unlines (header ++ rows ++ summary)
  where
    formatResultRow res =
      let nameCol = T.justifyLeft 14 ' ' (resRemoteName res)
          statusCol = T.justifyLeft 13 ' ' (statusLabel (resStatus res))
          urlCol = fromMaybe "(none)" (resActualUrl res)
      in "  " <> nameCol <> " | " <> statusCol <> " | " <> urlCol

    statusLabel RemoteCompliant         = "COMPLIANT"
    statusLabel RemoteMissing           = "MISSING"
    statusLabel (RemoteUrlDrift {})     = "URL DRIFT"
    statusLabel (RemoteNonCompliant {}) = "PROHIBITED"
    statusLabel RemoteUnknown          = "CUSTOM"

-- | Formats a 'RemoteSyncPlan' into a clean ASCII summary table.
formatRemoteSyncPlan :: RemoteSyncPlan -> Text
formatRemoteSyncPlan plan =
  let header =
        [ "=========================================================================================="
        , "  Gachi Remote Synchronization Plan: " <> planProject plan
        , "=========================================================================================="
        ]
      rows = map formatActionRow (planRemoteActions plan)
      summary =
        [ "------------------------------------------------------------------------------------------"
        , "  Planned Actions: " <> T.pack (show (length (planRemoteActions plan)))
          <> " (Add: " <> T.pack (show (planAddCount plan))
          <> ", Update: " <> T.pack (show (planUpdateCount plan))
          <> ", Remove: " <> T.pack (show (planRemoveCount plan)) <> ")"
        , "=========================================================================================="
        ]
  in T.unlines (header ++ rows ++ summary)
  where
    formatActionRow (ActionAddRemote rName targetUrl) =
      "  [ADD REMOTE]    " <> rName <> " -> " <> targetUrl
    formatActionRow (ActionSetUrl rName targetUrl) =
      "  [UPDATE URL]    " <> rName <> " -> " <> targetUrl
    formatActionRow (ActionAddPushUrl rName targetUrl) =
      "  [ADD PUSH URL]  " <> rName <> " -> " <> targetUrl
    formatActionRow (ActionRemoveRemote rName) =
      "  [REMOVE REMOTE] " <> rName <> " (Purging prohibited provider)"
    formatActionRow (ActionRemoteNoOp rName) =
      "  [NO-OP]         " <> rName <> " (Already aligned)"

--------------------------------------------------------------------------------
-- 5. Live Filesystem IO Integration
--------------------------------------------------------------------------------

-- | Queries Git remotes physically configured in a local repository checkout.
--
-- Executes @git -C <repoRoot> remote -v@ and parses the resulting output.
queryGitRemotes :: FilePath -> IO (Either Text [ConfiguredRemote])
queryGitRemotes repoRoot = (do
  (exitCode, stdout, stderr) <- readProcessWithExitCode "git" ["-C", repoRoot, "remote", "-v"] ""
  case exitCode of
    ExitSuccess -> pure (Right (parseGitRemoteOutput (T.pack stdout)))
    ExitFailure code ->
      pure (Left ("Git remote query failed with exit code " <> T.pack (show code) <> ": " <> T.pack stderr))
  ) `catch` (\(e :: SomeException) ->
    pure (Left ("Exception querying git remotes: " <> T.pack (show e))))

-- | Audits the physical remote topology of a repository checkout against canonical expectations.
auditRemoteTopology :: FilePath -> Project -> IO RemoteTopologyReport
auditRemoteTopology repoRoot proj = do
  let pName = projectName proj
      expected = case projectRemotes proj of
        []  -> defaultRemoteSpecsFor pName
        rms -> filterCompliantRemotes rms
  res <- queryGitRemotes repoRoot
  case res of
    Left _ ->
      -- If git fails, report all expected as missing
      pure (evaluateRemoteTopology pName expected [])
        { reportRepoDir = repoRoot }
    Right configured ->
      pure (evaluateRemoteTopology pName expected configured)
        { reportRepoDir = repoRoot }

-- | Executes a 'RemoteSyncPlan' in either 'DryRun' or 'ApplySync' mode.
--
-- In 'DryRun' mode: emits descriptive action logs without mutating Git configuration.
-- In 'ApplySync' mode: invokes Git commands to add, update, or remove remotes.
executeRemoteSyncPlan :: SyncMode -> RemoteSyncPlan -> IO (Either Text [Text])
executeRemoteSyncPlan DryRun plan =
  pure (Right [formatActionLog a | a <- planRemoteActions plan])
  where
    formatActionLog (ActionAddRemote n u)    = "DRY RUN: would execute 'git remote add " <> n <> " " <> u <> "'"
    formatActionLog (ActionSetUrl n u)       = "DRY RUN: would execute 'git remote set-url " <> n <> " " <> u <> "'"
    formatActionLog (ActionAddPushUrl n u)   = "DRY RUN: would execute 'git remote set-url --add --push " <> n <> " " <> u <> "'"
    formatActionLog (ActionRemoveRemote n)   = "DRY RUN: would execute 'git remote remove " <> n <> "'"
    formatActionLog (ActionRemoteNoOp n)     = "DRY RUN: no-op for " <> n

executeRemoteSyncPlan ApplySync plan = do
  let repo = planTargetRepo plan
  results <- mapM (applyAction repo) (planRemoteActions plan)
  let errors = lefts results
  if null errors
    then pure (Right (rights results))
    else pure (Left (T.intercalate "; " errors))
  where
    -- Executes 'git remote add <name> <url>' in target repository
    applyAction repo (ActionAddRemote n u) = do
      (c, _, err) <- readProcessWithExitCode "git" ["-C", repo, "remote", "add", T.unpack n, T.unpack u] ""
      case c of
        ExitSuccess -> pure (Right ("Added remote '" <> n <> "' pointing to " <> u))
        ExitFailure code -> pure (Left ("Failed to add remote '" <> n <> "' (code " <> T.pack (show code) <> "): " <> T.pack err))

    -- Executes 'git remote set-url <name> <url>' to reconcile URL drift
    applyAction repo (ActionSetUrl n u) = do
      (c, _, err) <- readProcessWithExitCode "git" ["-C", repo, "remote", "set-url", T.unpack n, T.unpack u] ""
      case c of
        ExitSuccess -> pure (Right ("Updated URL for remote '" <> n <> "' to " <> u))
        ExitFailure code -> pure (Left ("Failed to update remote '" <> n <> "' (code " <> T.pack (show code) <> "): " <> T.pack err))

    -- Executes 'git remote set-url --add --push <name> <url>' for multi-push targets
    applyAction repo (ActionAddPushUrl n u) = do
      (c, _, err) <- readProcessWithExitCode "git" ["-C", repo, "remote", "set-url", "--add", "--push", T.unpack n, T.unpack u] ""
      case c of
        ExitSuccess -> pure (Right ("Added push URL for remote '" <> n <> "': " <> u))
        ExitFailure _code -> pure (Left ("Failed to add push URL for remote '" <> n <> "': " <> T.pack err))

    -- Executes 'git remote remove <name>' to purge prohibited or non-compliant providers
    applyAction repo (ActionRemoveRemote n) = do
      (c, _, err) <- readProcessWithExitCode "git" ["-C", repo, "remote", "remove", T.unpack n] ""
      case c of
        ExitSuccess -> pure (Right ("Removed prohibited remote '" <> n <> "'"))
        ExitFailure _code -> pure (Left ("Failed to remove remote '" <> n <> "': " <> T.pack err))

    -- No-op for already aligned remotes
    applyAction _ (ActionRemoteNoOp n) =
      pure (Right ("Remote '" <> n <> "' is already aligned."))

-- | High-level orchestrator auditing and synchronizing remote topology for a project.
--
-- First audits the local checkout using 'auditRemoteTopology', derives an atomic
-- 'RemoteSyncPlan' via 'computeRemoteSyncPlan', and executes the planned mutations
-- under the specified 'SyncMode' ('DryRun' simulation or 'ApplySync' execution).
syncRemoteTopology :: SyncMode -> FilePath -> Project -> IO (Either Text [Text])
syncRemoteTopology mode repoRoot proj = do
  report <- auditRemoteTopology repoRoot proj
  let plan = computeRemoteSyncPlan report
  executeRemoteSyncPlan mode plan

-- | Zero-configuration remote topology inspection routine with automatic project inference.
--
-- Inspects the local checkout directory for @project.dhall@. When present, hermetically
-- decodes the declarative project specification to extract configured remotes.
-- When absent, derives a default project model using the checkout directory's canonical
-- basename and standard ecosystem owner conventions (@NadiaYvette@).
--
-- === Operational Safety
--
-- This operation is strictly read-only and will never alter Git configuration or
-- files on disk.
auditRemoteTopologyQuick :: FilePath -> IO RemoteTopologyReport
auditRemoteTopologyQuick repoRoot = do
  absRoot <- canonicalizePath repoRoot
  let dhallPath = absRoot </> "project.dhall"
  hasDhall <- doesFileExist dhallPath
  proj <- if hasDhall
    then decodeProjectFile dhallPath `catch` (\(_ :: SomeException) -> do
      let inferredName = T.pack (takeFileName absRoot)
      pure (defaultProject inferredName (Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me")))
    else do
      let inferredName = T.pack (takeFileName absRoot)
      pure (defaultProject inferredName (Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"))
  auditRemoteTopology absRoot proj

-- | High-level zero-configuration remote topology synchronization orchestrator.
--
-- Automatically resolves project metadata via 'auditRemoteTopologyQuick', computes the
-- declarative synchronization plan, and applies or simulates the required remote
-- adjustments according to 'SyncMode'.
--
-- Returns a tuple containing the evaluated 'RemoteTopologyReport' and the resulting
-- execution outcome (a list of descriptive log messages or an error string).
syncRemoteTopologyQuick
  :: SyncMode
  -> FilePath
  -> IO (RemoteTopologyReport, Either Text [Text])
syncRemoteTopologyQuick mode repoRoot = do
  absRoot <- canonicalizePath repoRoot
  report <- auditRemoteTopologyQuick absRoot
  let plan = computeRemoteSyncPlan report
  res <- executeRemoteSyncPlan mode plan
  pure (report, res)
