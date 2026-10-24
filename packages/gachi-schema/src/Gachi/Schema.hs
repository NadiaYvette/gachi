{-# LANGUAGE DuplicateRecordFields #-}

-- | Module: Gachi.Schema
-- Description: Declarative project schemas, Dhall codecs, and open row representations
--
-- Front door module for the @gachi-schema@ package.
--
-- Provides strongly-typed project manifests ('Project', 'PackageSpec', 'Author', 'RemoteSpec'),
-- Dhall deserialization engines, pretty-printers, and open row isomorphisms ('ProjectRec')
-- powered by "Polytropos.Dhall".
--
-- = Architectural Overview
--
-- In the Gachi architecture, all project instantiation (@gachi init@), cross-repository
-- standardization (@gachi sync@), and retrofitting (@gachi retrofit@) operate on total,
-- deterministic Dhall schemas rather than untyped string templating (Jinja/Mustache).
--
-- Schemas are decoded through 'Polytropos.Dhall' into either nominal records or open
-- heterogeneous rows without intermediate binary tree allocations.
--
-- = When to Use This Module
--
-- * Importing all project schema types and Dhall decoders with a single module import.
-- * Authoring or validating @project.dhall@ configurations.
-- * Converting between nominal project configurations and open row representations.
--
-- = Worked Example
--
-- >>> import Gachi.Schema
-- >>> proj <- decodeProjectText exampleProjectDhall
-- >>> projectName proj
-- "gongju"
-- >>> projectLicense proj
-- "EUPL-1.2"
module Gachi.Schema
  ( -- * Note Architecture
    -- $notes

    -- * Nominal Schema Types
    Project(..)
  , Author(..)
  , PackageSpec(..)
  , RemoteSpec(..)

    -- * Projection Selectors
  , projectName
  , projectDescription
  , projectLicense
  , projectAuthor
  , projectGhcVersion
  , projectCabalVersion
  , projectPackages
  , projectRemotes
  , authorName
  , authorEmail
  , packageName
  , packageSynopsis
  , packageExposes
  , remoteName
  , remoteUrl

    -- * Open Row Types & Isomorphisms
  , ProjectRow
  , ProjectRec
  , toProjectRec
  , fromProjectRec

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

    -- * Dhall Evaluation & Serialization
  , decodeProjectText
  , decodeProjectFile
  , decodeProjectEither
  , decodeProjectRecText
  , decodeProjectRecEither
  , renderProjectDhall
  , renderProjectRecDhall

    -- * Turnkey Schemas & Canonical Defaults
  , projectSchemaDhall
  , exampleProjectDhall
  , defaultProject
  , defaultPackage
  , canonicalLicense
  , canonicalGhcVersion
  , canonicalCabalVersion
  ) where

import Gachi.Schema.Project
import Gachi.Schema.Dhall

{- $notes
See Note [Dhall Parameterized Skeleton Templating] [ref:note-dhall-skeleton-templating].
-}

{- Note [Dhall Parameterized Skeleton Templating]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-dhall-skeleton-templating]
All project templates, multi-package layouts, and tooling manifests in Gachi are defined
as total, strongly typed Dhall schemas decoded into osteological structures.

Architectural Rationale:
  1. Determinism and Totality: Dhall expressions are guaranteed to terminate (strongly
     normalizing) and have zero access to ambient system calls, filesystems, or networks
     during evaluation. This ensures template evaluation is hermetic and reproducible.
  2. Strongly-Typed Schemas: Project metadata ('Project', 'PackageSpec', 'Author', 'RemoteSpec')
     is validated at evaluation time before directory creation, preventing partial or corrupt
     scaffolding runs.
  3. Seamless Generic & Row Decoding: By leveraging 'polytropos-dhall', schemas can be decoded
     either into nominal Haskell records via 'GenericDhall' or into open heterogeneous records
     ('Record') without intermediate AST tree allocations.
  4. Non-Destructive Extensibility: Schemas can provide default records, allowing user
     overrides for specific fields without breaking backward compatibility when new metadata
     fields are introduced.

See also:
  - Note [Ecosystem Standardization Invariants] [ref:note-ecosystem-standardization]
-}
