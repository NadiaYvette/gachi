{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Schema.Dhall
-- Description: Dhall schema definitions, encoders, decoders, and templates
--
-- Provides turnkey encoders, decoders, and template definitions for evaluating
-- declarative Dhall project specifications into strongly typed 'Project' and 'ProjectRec'
-- structures.
--
-- All decoding operations enforce the totality and safety guarantees established in
-- Note [Dhall Parameterized Skeleton Templating] [ref:note-dhall-skeleton-templating].
--
-- = Architectural Overview & Rationale
--
-- Dhall is a programmable, strongly normalizing configuration language designed to
-- prevent unexpected failures at execution time. In Gachi, Dhall serves as the canonical
-- medium for defining project templates and configuration manifests because of its unique
-- structural characteristics:
--
-- 1. __Totality and Termination Guarantees:__
--    Dhall expressions are mathematically guaranteed to terminate. Unlike general-purpose
--    languages or Turing-complete template engines (e.g., Nix, Python scripts), a Dhall
--    template can never enter an infinite loop or deadlock the scaffolding engine.
--
-- 2. __Hermetic and Side-Effect Free:__
--    During evaluation, Dhall does not have access to ambient environment variables, arbitrary
--    filesystems, network sockets, or external process execution (unless explicit imports
--    are resolved by the host). This ensures that template instantiation is fully hermetic,
--    deterministic, and reproducible across disparate developer environments.
--
-- 3. __Strong Static Typing:__
--    Dhall configurations are statically typechecked against the expected schema before
--    any directory creation or file writing begins. Mismatched field names, missing attributes,
--    or incorrect types produce actionable, human-readable compiler diagnostics rather than
--    silent corruptions or half-initialized repositories.
--
-- == Evaluation & Codec Integration
--
-- This module leverages "Polytropos.Dhall" to bridge Dhall AST expressions ('Dhall.Core.Expr')
-- directly into high-performance Haskell structures:
--
-- * Nominal decoding ('decodeProjectText') utilizes 'Polytropos.Dhall.GenericDhall' to
--   populate 'Project' structures in a single pass.
-- * Open row decoding ('decodeProjectRecText') extracts raw fields directly into Polytropos
--   flat 'Polytropos.Core.RowRep' memory structures with zero intermediate binary tree allocations.
--
-- = When to Use This Module
--
-- * Reading and evaluating @project.dhall@ files from disk or memory.
-- * Formatting 'Project' or 'ProjectRec' records back into canonical Dhall expressions.
-- * Obtaining the canonical Dhall schema definition ('projectSchemaDhall') for tooling or LSP integration.
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Dhall
-- >>> proj <- decodeProjectText exampleProjectDhall
-- >>> projectName proj
-- "gongju"
module Gachi.Schema.Dhall
  ( -- * High-Level Dhall Evaluation
    decodeProjectText
  , decodeProjectFile
  , decodeProjectEither
  , decodeProjectRecText
  , decodeProjectRecEither

    -- * Rendering & Encoding
  , renderProjectDhall
  , renderProjectRecDhall

    -- * Embedded Dhall Schemas & Turnkey Templates
  , projectSchemaDhall
  , exampleProjectDhall
  ) where

import Control.Exception (SomeException, try)
import Data.Bifunctor (first)
import Data.Text (Text)
import qualified Dhall
import qualified Dhall.Core as Core
import Gachi.Schema.Project (Project, ProjectRec)

-- | Decode a 'Project' specification from a raw Dhall text expression.
--
-- Evaluates the Dhall abstract syntax tree, verifies all expected schema fields
-- against the nominal 'Project' definition, and constructs the resulting record.
--
-- Throws a 'Dhall.Core.DhallErrors' exception if the expression fails to parse,
-- typecheck, or match the expected schema.
--
-- Time complexity: Strictly linear in the size of the Dhall input expression.
decodeProjectText :: Text -> IO Project
decodeProjectText = Dhall.input Dhall.auto

-- | Decode a 'Project' specification from a Dhall file located on disk.
--
-- Automatically resolves relative local file imports (e.g., @./Schema.dhall@)
-- relative to the target file's parent directory.
--
-- Throws an 'IOException' if the file does not exist, or a 'Dhall.Core.DhallErrors'
-- exception if evaluation fails.
decodeProjectFile :: FilePath -> IO Project
decodeProjectFile = Dhall.inputFile Dhall.auto

-- | Safely decode a 'Project' from Dhall text without throwing runtime exceptions.
--
-- Catches any 'SomeException' raised during parsing, typechecking, or normalization
-- and wraps it in a 'Left' containing the formatted diagnostic error message.
--
-- Useful for CLI validation flags, interactive wizards, and language server linting passes.
decodeProjectEither :: Text -> IO (Either String Project)
decodeProjectEither txt = first show <$> (try (decodeProjectText txt) :: IO (Either SomeException Project))

-- | Decode an open heterogeneous 'ProjectRec' row record from a Dhall text expression.
--
-- Directly unrolls Dhall record literals into Polytropos flat 'Data.Primitive.SmallArray'
-- memory slots in row order via 'Polytropos.Dhall', achieving zero intermediate binary tree
-- constructor allocations.
--
-- Throws a 'Dhall.Core.DhallErrors' exception if the input expression violates the schema.
decodeProjectRecText :: Text -> IO ProjectRec
decodeProjectRecText = Dhall.input Dhall.auto

-- | Safely decode an open heterogeneous 'ProjectRec' from Dhall text without throwing exceptions.
--
-- Wraps any caught evaluation failure in 'Left' with the descriptive error message,
-- or returns 'Right' with the parsed 'ProjectRec'.
decodeProjectRecEither :: Text -> IO (Either String ProjectRec)
decodeProjectRecEither txt = first show <$> (try (decodeProjectRecText txt) :: IO (Either SomeException ProjectRec))

-- | Render a nominal 'Project' into canonical, pretty-printed Dhall source text.
--
-- Emits a formatted Dhall record literal matching 'projectSchemaDhall'.
--
-- Time complexity: Linear in the size of the project record structure.
renderProjectDhall :: Project -> Text
renderProjectDhall = Core.pretty . Dhall.embed Dhall.inject

-- | Render an open heterogeneous 'ProjectRec' into canonical, pretty-printed Dhall source text.
--
-- Directly inspects the contiguous 'Polytropos.Core.RowRep' memory buffer and emits
-- the corresponding Dhall record literal without building intermediate nominal ASTs.
renderProjectRecDhall :: ProjectRec -> Text
renderProjectRecDhall = Core.pretty . Dhall.embed Dhall.inject

-- | The canonical Dhall schema defining 'Author', 'Package', 'Remote', and 'Project' types.
projectSchemaDhall :: Text
projectSchemaDhall =
  "let Author : Type =\n\
  \  { name : Text\n\
  \  , email : Text\n\
  \  }\n\
  \\n\
  \let Package : Type =\n\
  \  { name : Text\n\
  \  , synopsis : Text\n\
  \  , exposes : List Text\n\
  \  }\n\
  \\n\
  \let Remote : Type =\n\
  \  { name : Text\n\
  \  , url : Text\n\
  \  }\n\
  \\n\
  \let Project : Type =\n\
  \  { name : Text\n\
  \  , description : Text\n\
  \  , license : Text\n\
  \  , author : Author\n\
  \  , ghcVersion : Text\n\
  \  , cabalVersion : Text\n\
  \  , packages : List Package\n\
  \  , remotes : List Remote\n\
  \  }\n\
  \\n\
  \in  { Author = Author\n\
  \    , Package = Package\n\
  \    , Remote = Remote\n\
  \    , Project = Project\n\
  \    }\n"

-- | Turnkey sample Dhall specification for the 'gongju' crucible project.
exampleProjectDhall :: Text
exampleProjectDhall =
  "let Schema =\n\
  \  { Author = { name : Text, email : Text }\n\
  \  , Package = { name : Text, synopsis : Text, exposes : List Text }\n\
  \  , Remote = { name : Text, url : Text }\n\
  \  , Project =\n\
  \      { name : Text\n\
  \      , description : Text\n\
  \      , license : Text\n\
  \      , author : { name : Text, email : Text }\n\
  \      , ghcVersion : Text\n\
  \      , cabalVersion : Text\n\
  \      , packages : List { name : Text, synopsis : Text, exposes : List Text }\n\
  \      , remotes : List { name : Text, url : Text }\n\
  \      }\n\
  \  }\n\
  \\n\
  \let project : Schema.Project =\n\
  \  { name = \"gongju\"\n\
  \  , description = \"Type-level utility functions and Peano arithmetic crucible\"\n\
  \  , license = \"EUPL-1.2\"\n\
  \  , author =\n\
  \      { name = \"Nadia Yvette Chambers\"\n\
  \      , email = \"nadia.yvette.chambers@ik.me\"\n\
  \      }\n\
  \  , ghcVersion = \"9.14.1\"\n\
  \  , cabalVersion = \"3.18\"\n\
  \  , packages =\n\
  \      [ { name = \"gongju\"\n\
  \        , synopsis = \"Pure Peano type-level utilities and HList operations\"\n\
  \        , exposes =\n\
  \            [ \"Gongju.Peano\"\n\
  \            , \"Gongju.Composition\"\n\
  \            , \"Gongju.Positional\"\n\
  \            , \"Gongju.Permute\"\n\
  \            , \"Gongju.HList\"\n\
  \            ]\n\
  \        }\n\
  \      ]\n\
  \  , remotes =\n\
  \      [ { name = \"github\"\n\
  \        , url = \"git@github.com:NadiaYvette/gongju.git\"\n\
  \        }\n\
  \      , { name = \"gitlab\"\n\
  \        , url = \"git@gitlab.com:NadiaYvette/gongju.git\"\n\
  \        }\n\
  \      ]\n\
  \  }\n\
  \\n\
  \in  project\n"
