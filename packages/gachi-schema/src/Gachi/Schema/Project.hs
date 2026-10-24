{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | Module: Gachi.Schema.Project
-- Description: Strongly-typed nominal records and open row representations for projects
--
-- Defines foundational schema types for declarative workspace and package configurations:
-- 'Author', 'PackageSpec', 'RemoteSpec', and 'Project'.
--
-- All types provide both nominal representations deriving 'FromDhall' / 'ToDhall' via
-- 'GenericDhall' and isomorphic open row representations ('ProjectRec', 'AuthorRec', etc.)
-- backed by Polytropos flat 'Record' storage.
--
-- = Architectural Overview & Rationale
--
-- In Gachi's infrastructure model, all repository scaffolding, configuration synthesis,
-- and project retrofitting operate on declarative, hermetic schemas encoded in the
-- Dhall configuration language. Rather than relying on fragile untyped string substitution
-- (such as Jinja, Mustache, or sed expressions), Gachi models repository metadata as
-- strongly-typed algebraic records.
--
-- == Duality: Nominal Records and Open Rows
--
-- This module implements a deliberate structural duality:
--
-- 1. __Nominal Representations ('Project', 'Author', etc.):__
--    Provide standard Haskell data types with 'Generic' deriving. These types interface
--    seamlessly with Dhall via 'Polytropos.Dhall.GenericDhall' through @DerivingVia@,
--    enabling automatic decoder ('FromDhall') and encoder ('ToDhall') synthesis.
--
-- 2. __Open Row Isomorphisms ('ProjectRec', 'AuthorRec', etc.):__
--    Provide isomorphic open record types backed by Polytropos contiguous
--    'Polytropos.Core.RowRep' storage. In the open row representation, field values reside in
--    contiguous 'Data.Primitive.SmallArray' slots, permitting dynamic field extension,
--    narrowing, and sub-row projection without intermediate data type declarations.
--
-- == Ecosystem Invariants & Licensing
--
-- All project skeletons generated or verified by Gachi adhere to core ecosystem policies:
--
-- * __Licensing Discipline:__ By default, all ecosystem assets are licensed under
--   the European Union Public Licence (EUPL-1.2) or Apache-2.0. The EUPL is legally
--   interoperable across 22 European languages and compatible with GPLv2/v3 while protecting
--   upstream authors against SaaS-loophole proprietary enclosure.
-- * __Toolchain Pinning:__ Projects explicitly pin GHC 9.14.1 and Cabal 3.18, enabling
--   reproducible, bit-identical build artifacts across heterogeneous development workstations
--   and automated CI matrices.
-- * __Modular Multi-Package DAGs:__ Large systems are decomposed into fine-grained packages
--   (e.g., @*-core@, @*-schema@, @*-cli@) with explicit module exposure lists, maximizing
--   compilation parallelism and enforcing clean architectural boundaries.
--
-- = When to Use This Module
--
-- * Reading, validating, or writing Dhall project manifests (@project.dhall@).
-- * Generating multi-package workspace structures in @gachi init@.
-- * Converting between nominal Haskell configurations and open row representations.
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project
-- >>> let auth = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
-- >>> let proj = defaultProject "gongju" auth
-- >>> projectName proj
-- "gongju"
-- >>> projectLicense proj
-- "EUPL-1.2"
module Gachi.Schema.Project
  ( -- * Nominal Schema Data Types
    Author(..)
  , PackageSpec(..)
  , RemoteSpec(..)
  , Project(..)

    -- * Field Projection Aliases
  , authorName
  , authorEmail
  , packageName
  , packageSynopsis
  , packageExposes
  , remoteName
  , remoteUrl
  , projectName
  , projectDescription
  , projectLicense
  , projectAuthor
  , projectGhcVersion
  , projectCabalVersion
  , projectPackages
  , projectRemotes

    -- * Open Row Types
  , AuthorRow
  , AuthorRec
  , toAuthorRec
  , fromAuthorRec

  , PackageRow
  , PackageRec
  , toPackageRec
  , fromPackageRec

  , RemoteRow
  , RemoteRec
  , toRemoteRec
  , fromRemoteRec

  , ProjectRow
  , ProjectRec
  , toProjectRec
  , fromProjectRec

    -- * Defaults & Canonical Invariants
  , defaultProject
  , defaultPackage
  , canonicalLicense
  , canonicalGhcVersion
  , canonicalCabalVersion
  ) where

import Data.Text (Text)
import Data.Functor.Identity (Identity(..))
import Dhall (FromDhall, ToDhall)
import GHC.Generics (Generic)
import Polytropos
  ( Pair(..)
  , Record
  )
import Polytropos.Core
  ( RowRep(..)
  , fieldAt
  , noInlineUnsafeCo
  , productRep
  )
import Polytropos.Dhall (GenericDhall(..))

-- | Author and maintainer metadata for a project.
data Author = Author
  { name  :: !Text
    -- ^ Full personal or organizational author name.
  , email :: !Text
    -- ^ Contact email address.
  } deriving stock (Generic, Show, Eq)
    deriving (FromDhall, ToDhall) via (GenericDhall Author)

-- | Specification for an individual Cabal package within a multi-package workspace.
data PackageSpec = PackageSpec
  { name     :: !Text
    -- ^ Package name (e.g., @"gachi-core"@).
  , synopsis :: !Text
    -- ^ Short one-line synopsis of package purpose.
  , exposes  :: ![Text]
    -- ^ List of exposed top-level modules.
  } deriving stock (Generic, Show, Eq)
    deriving (FromDhall, ToDhall) via (GenericDhall PackageSpec)

-- | Remote Git repository configuration for multi-forge mirroring.
data RemoteSpec = RemoteSpec
  { name :: !Text
    -- ^ Remote identifier (e.g., @"github"@, @"gitlab"@, @"radicle"@).
  , url  :: !Text
    -- ^ Canonical fetch/push URL.
  } deriving stock (Generic, Show, Eq)
    deriving (FromDhall, ToDhall) via (GenericDhall RemoteSpec)

-- | Comprehensive declarative specification for a project workspace.
--
-- See Note [Dhall Parameterized Skeleton Templating] [ref:note-dhall-skeleton-templating].
data Project = Project
  { name         :: !Text
    -- ^ Canonical project name.
  , description  :: !Text
    -- ^ Human-readable project description and mission.
  , license      :: !Text
    -- ^ SPDX license identifier (defaults to @"EUPL-1.2"@).
  , author       :: !Author
    -- ^ Primary maintainer or author identity.
  , ghcVersion   :: !Text
    -- ^ Pinned GHC compiler release (e.g., @"9.14.1"@).
  , cabalVersion :: !Text
    -- ^ Pinned Cabal specification release (e.g., @"3.18"@).
  , packages     :: ![PackageSpec]
    -- ^ Modular package hierarchy constituting this workspace.
  , remotes      :: ![RemoteSpec]
    -- ^ Multi-forge remotes configured for replication.
  } deriving stock (Generic, Show, Eq)
    deriving (FromDhall, ToDhall) via (GenericDhall Project)

--------------------------------------------------------------------------------
-- Field Projection Aliases (disambiguating DuplicateRecordFields when needed)
--------------------------------------------------------------------------------

-- | Disambiguated projection selector for 'Author' name.
--
-- Time complexity: @O(1)@ direct pattern match.
authorName :: Author -> Text
authorName (Author n _) = n

-- | Disambiguated projection selector for 'Author' email.
--
-- Time complexity: @O(1)@ direct pattern match.
authorEmail :: Author -> Text
authorEmail (Author _ e) = e

-- | Disambiguated projection selector for 'PackageSpec' name.
--
-- Time complexity: @O(1)@ direct pattern match.
packageName :: PackageSpec -> Text
packageName (PackageSpec n _ _) = n

-- | Disambiguated projection selector for 'PackageSpec' synopsis.
--
-- Time complexity: @O(1)@ direct pattern match.
packageSynopsis :: PackageSpec -> Text
packageSynopsis (PackageSpec _ s _) = s

-- | Disambiguated projection selector for 'PackageSpec' exposed modules.
--
-- Time complexity: @O(1)@ direct pattern match.
packageExposes :: PackageSpec -> [Text]
packageExposes (PackageSpec _ _ ex) = ex

-- | Disambiguated projection selector for 'RemoteSpec' name.
--
-- Time complexity: @O(1)@ direct pattern match.
remoteName :: RemoteSpec -> Text
remoteName (RemoteSpec n _) = n

-- | Disambiguated projection selector for 'RemoteSpec' URL.
--
-- Time complexity: @O(1)@ direct pattern match.
remoteUrl :: RemoteSpec -> Text
remoteUrl (RemoteSpec _ u) = u

-- | Disambiguated projection selector for 'Project' name.
--
-- Time complexity: @O(1)@ direct pattern match.
projectName :: Project -> Text
projectName (Project n _ _ _ _ _ _ _) = n

-- | Disambiguated projection selector for 'Project' description.
--
-- Time complexity: @O(1)@ direct pattern match.
projectDescription :: Project -> Text
projectDescription (Project _ d _ _ _ _ _ _) = d

-- | Disambiguated projection selector for 'Project' license.
--
-- Time complexity: @O(1)@ direct pattern match.
projectLicense :: Project -> Text
projectLicense (Project _ _ l _ _ _ _ _) = l

-- | Disambiguated projection selector for 'Project' author.
--
-- Time complexity: @O(1)@ direct pattern match.
projectAuthor :: Project -> Author
projectAuthor (Project _ _ _ a _ _ _ _) = a

-- | Disambiguated projection selector for 'Project' GHC version.
--
-- Time complexity: @O(1)@ direct pattern match.
projectGhcVersion :: Project -> Text
projectGhcVersion (Project _ _ _ _ g _ _ _) = g

-- | Disambiguated projection selector for 'Project' Cabal version.
--
-- Time complexity: @O(1)@ direct pattern match.
projectCabalVersion :: Project -> Text
projectCabalVersion (Project _ _ _ _ _ c _ _) = c

-- | Disambiguated projection selector for 'Project' packages.
--
-- Time complexity: @O(1)@ direct pattern match.
projectPackages :: Project -> [PackageSpec]
projectPackages (Project _ _ _ _ _ _ pkgs _) = pkgs

-- | Disambiguated projection selector for 'Project' remotes.
--
-- Time complexity: @O(1)@ direct pattern match.
projectRemotes :: Project -> [RemoteSpec]
projectRemotes (Project _ _ _ _ _ _ _ rms) = rms

--------------------------------------------------------------------------------
-- Open Row Representations (Polytropos Flat Memory Records)
--------------------------------------------------------------------------------

-- | Heterogeneous type-level row for 'Author'.
type AuthorRow = '["name" ':= Text, "email" ':= Text]

-- | Open record type for 'Author'.
type AuthorRec = Record AuthorRow

-- | Convert nominal 'Author' into open 'AuthorRec'.
--
-- Packs fields into a contiguous 2-element 'Data.Primitive.SmallArray' in row order:
-- Slot 0 (@"name"@) and Slot 1 (@"email"@).
--
-- Time complexity: @O(1)@.
toAuthorRec :: Author -> AuthorRec
toAuthorRec (Author n e) =
  RowRep (productRep [Identity (noInlineUnsafeCo n), Identity (noInlineUnsafeCo e)])

-- | Convert open 'AuthorRec' into nominal 'Author'.
--
-- Dereferences contiguous array slots via 'fieldAt' with zero intermediate heap allocation.
--
-- Time complexity: @O(1)@.
fromAuthorRec :: AuthorRec -> Author
fromAuthorRec (RowRep rep) = Author
  { name  = let Identity n = fieldAt 0 rep in n
  , email = let Identity e = fieldAt 1 rep in e
  }

-- | Heterogeneous type-level row for 'PackageSpec'.
type PackageRow = '["name" ':= Text, "synopsis" ':= Text, "exposes" ':= [Text]]

-- | Open record type for 'PackageSpec'.
type PackageRec = Record PackageRow

-- | Convert nominal 'PackageSpec' into open 'PackageRec'.
--
-- Packs fields into a contiguous 3-element 'Data.Primitive.SmallArray' in row order:
-- Slot 0 (@"name"@), Slot 1 (@"synopsis"@), and Slot 2 (@"exposes"@).
--
-- Time complexity: @O(1)@.
toPackageRec :: PackageSpec -> PackageRec
toPackageRec (PackageSpec n s ex) =
  RowRep (productRep [Identity (noInlineUnsafeCo n), Identity (noInlineUnsafeCo s), Identity (noInlineUnsafeCo ex)])

-- | Convert open 'PackageRec' into nominal 'PackageSpec'.
--
-- Dereferences contiguous array slots via 'fieldAt' with zero intermediate heap allocation.
--
-- Time complexity: @O(1)@.
fromPackageRec :: PackageRec -> PackageSpec
fromPackageRec (RowRep rep) = PackageSpec
  { name     = let Identity n  = fieldAt 0 rep in n
  , synopsis = let Identity s  = fieldAt 1 rep in s
  , exposes  = let Identity ex = fieldAt 2 rep in ex
  }

-- | Heterogeneous type-level row for 'RemoteSpec'.
type RemoteRow = '["name" ':= Text, "url" ':= Text]

-- | Open record type for 'RemoteSpec'.
type RemoteRec = Record RemoteRow

-- | Convert nominal 'RemoteSpec' into open 'RemoteRec'.
--
-- Packs fields into a contiguous 2-element 'Data.Primitive.SmallArray' in row order:
-- Slot 0 (@"name"@) and Slot 1 (@"url"@).
--
-- Time complexity: @O(1)@.
toRemoteRec :: RemoteSpec -> RemoteRec
toRemoteRec (RemoteSpec n u) =
  RowRep (productRep [Identity (noInlineUnsafeCo n), Identity (noInlineUnsafeCo u)])

-- | Convert open 'RemoteRec' into nominal 'RemoteSpec'.
--
-- Dereferences contiguous array slots via 'fieldAt' with zero intermediate heap allocation.
--
-- Time complexity: @O(1)@.
fromRemoteRec :: RemoteRec -> RemoteSpec
fromRemoteRec (RowRep rep) = RemoteSpec
  { name = let Identity n = fieldAt 0 rep in n
  , url  = let Identity u = fieldAt 1 rep in u
  }

-- | Heterogeneous type-level row for 'Project'.
type ProjectRow =
  '[ "name" ':= Text
   , "description" ':= Text
   , "license" ':= Text
   , "author" ':= Author
   , "ghcVersion" ':= Text
   , "cabalVersion" ':= Text
   , "packages" ':= [PackageSpec]
   , "remotes" ':= [RemoteSpec]
   ]

-- | Open record type for 'Project'.
type ProjectRec = Record ProjectRow

-- | Convert nominal 'Project' into open 'ProjectRec'.
--
-- Packs all 8 project fields into a single contiguous 'Data.Primitive.SmallArray' in row order:
-- Slot 0 (@"name"@), Slot 1 (@"description"@), Slot 2 (@"license"@), Slot 3 (@"author"@),
-- Slot 4 (@"ghcVersion"@), Slot 5 (@"cabalVersion"@), Slot 6 (@"packages"@), and Slot 7 (@"remotes"@).
--
-- Time complexity: @O(1)@.
toProjectRec :: Project -> ProjectRec
toProjectRec (Project n d l a g c pkgs rms) =
  RowRep (productRep
    [ Identity (noInlineUnsafeCo n)
    , Identity (noInlineUnsafeCo d)
    , Identity (noInlineUnsafeCo l)
    , Identity (noInlineUnsafeCo a)
    , Identity (noInlineUnsafeCo g)
    , Identity (noInlineUnsafeCo c)
    , Identity (noInlineUnsafeCo pkgs)
    , Identity (noInlineUnsafeCo rms)
    ])

-- | Convert open 'ProjectRec' into nominal 'Project'.
--
-- Unpacks the flat contiguous array into the nominal 'Project' record in $O(1)$ time
-- with zero intermediate tree allocations.
--
-- Time complexity: @O(1)@.
fromProjectRec :: ProjectRec -> Project
fromProjectRec (RowRep rep) = Project
  { name         = let Identity n    = fieldAt 0 rep in n
  , description  = let Identity d    = fieldAt 1 rep in d
  , license      = let Identity l    = fieldAt 2 rep in l
  , author       = let Identity a    = fieldAt 3 rep in a
  , ghcVersion   = let Identity g    = fieldAt 4 rep in g
  , cabalVersion = let Identity c    = fieldAt 5 rep in c
  , packages     = let Identity pkgs = fieldAt 6 rep in pkgs
  , remotes      = let Identity rms  = fieldAt 7 rep in rms
  }

--------------------------------------------------------------------------------
-- Canonical Ecosystem Standards & Turnkey Defaults
--------------------------------------------------------------------------------

-- | Canonical default license per ecosystem policy: EUPL-1.2.
canonicalLicense :: Text
canonicalLicense = "EUPL-1.2"

-- | Canonical default GHC version: 9.14.1.
canonicalGhcVersion :: Text
canonicalGhcVersion = "9.14.1"

-- | Canonical default Cabal specification version: 3.18.
canonicalCabalVersion :: Text
canonicalCabalVersion = "3.18"

-- | Construct a default 'PackageSpec' with canonical conventions.
defaultPackage :: Text -> PackageSpec
defaultPackage pkgName = PackageSpec
  { name     = pkgName
  , synopsis = "Foundational package for " <> pkgName
  , exposes  = []
  }

-- | Construct a turnkey 'Project' with canonical defaults.
--
-- Automatically configures EUPL-1.2 license, GHC 9.14.1, Cabal 3.18, and a primary package.
defaultProject :: Text -> Author -> Project
defaultProject projName auth = Project
  { name         = projName
  , description  = "Ecosystem workspace for " <> projName
  , license      = canonicalLicense
  , author       = auth
  , ghcVersion   = canonicalGhcVersion
  , cabalVersion = canonicalCabalVersion
  , packages     = [defaultPackage projName]
  , remotes      = []
  }
