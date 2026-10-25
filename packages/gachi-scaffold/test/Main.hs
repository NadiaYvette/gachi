{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Main
-- Description: Comprehensive specification and verification suite for gachi-scaffold
--
-- Validates:
-- 1. Pure in-memory generation of canonical file trees ('generateProjectScaffold').
-- 2. Filesystem materialization, permissions, and directory structures ('writeScaffold').
-- 3. Execution modes ('FailOnExisting', 'SkipExisting', 'OverwriteExisting').
-- 4. Five-gate physical self-consistency across generated target workspaces (Tagref, Linkcheck, CLOC).
module Main (main) where

import Control.Exception (SomeException(..), bracket, catch, try)
import Control.Monad (forM_)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , executable
  , getPermissions
  , getTemporaryDirectory
  , removeDirectoryRecursive
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)
import Test.Hspec

import Gachi.Schema.Project
  ( Author(..)
  , PackageSpec(..)
  , Project(..)
  , defaultProject
  )
import Gachi.Scaffold

-- | Helper executing an action within an isolated temporary directory.
withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action = do
  base <- getTemporaryDirectory
  t <- getPOSIXTime
  let dirPath = base </> (prefix ++ "-" ++ show (round (t * 1000) :: Integer))
  bracket
    (createDirectoryIfMissing True dirPath >> pure dirPath)
    (\p -> catch (removeDirectoryRecursive p) (\(SomeException _) -> pure ()))
    action

-- | Canonical test project fixture representing the 'gongju' type-level utility victim project.
gongjuFixture :: Project
gongjuFixture =
  let auth = Author
        { name = "Nadia Yvette Chambers"
        , email = "nadia.yvette.chambers@ik.me"
        }
      pkg = PackageSpec
        { name = "gongju-core"
        , synopsis = "Type-level utility functions and row-polymorphic primitives"
        , exposes = ["Gongju.Core", "Gongju.TypeLevel"]
        }
  in (defaultProject "gongju" auth)
       { description = "Type-level utility library and open ADT substrate for Haskell"
       , packages = [pkg]
       }

main :: IO ()
main = hspec $ do
  describe "Gachi.Scaffold.Markdown (GFM AST & Pretty-Printing)" $ do
    it "renders headings at appropriate depth levels" $ do
      renderMarkdown [h1 "Level 1", h2 "Level 2", h3 "Level 3", h4 "Level 4"]
        `shouldBe` "# Level 1\n\n## Level 2\n\n### Level 3\n\n#### Level 4\n"

    it "renders inlines including formatting, hyperlinks, and dynamic tags" $ do
      let doc = [paraInlines [plain "Text with ", bold "bold", plain ", ", italic "italic", plain ", ", code "code", plain ", ", link "example" "https://example.com", plain ", and ", tagDef "my-tag"]]
      renderMarkdown doc
        `shouldBe` "Text with **bold**, *italic*, `code`, [example](https://example.com), and [tag:my-tag]\n"

    it "renders fenced code blocks with language annotation and clean margins" $ do
      let doc = [codeBlock "haskell" "main :: IO ()\nmain = putStrLn \"hello\"\n"]
      renderMarkdown doc
        `shouldBe` "```haskell\nmain :: IO ()\nmain = putStrLn \"hello\"\n```\n"

    it "renders bullet lists and ordered lists deterministically" $ do
      let bList = [bulletList [plain "Item A", bold "Item B"]]
          oList = [orderedList [plain "Step 1", code "Step 2"]]
      renderMarkdown bList `shouldBe` "- Item A\n- **Item B**\n"
      renderMarkdown oList `shouldBe` "1. Step 1\n2. `Step 2`\n"

    it "dynamically measures and pads table columns with aligned separator lines" $ do
      let headers = ["Component", "Language", "Status"]
          rows =
            [ [plain "Engine", code "Haskell", bold "Active"]
            , [plain "Compiler Verification", code "Bash", plain "Operational"]
            ]
          rendered = renderMarkdown [table headers rows]
      rendered `shouldSatisfy` T.isInfixOf "| Component             | Language  | Status      |"
      rendered `shouldSatisfy` T.isInfixOf "| :-------------------- | :-------- | :---------- |"
      rendered `shouldSatisfy` T.isInfixOf "| Engine                | `Haskell` | **Active**  |"
      rendered `shouldSatisfy` T.isInfixOf "| Compiler Verification | `Bash`    | Operational |"

  describe "Gachi.Scaffold.Templates (Pure Generation)" $ do
    it "generates complete canonical asset set (>25 files)" $ do
      let entries = generateProjectScaffold gongjuFixture
      length entries `shouldSatisfy` (> 25)

    it "synthesizes all mandatory root toolchain files" $ do
      let entries = generateProjectScaffold gongjuFixture
          paths = map entryPath entries
      paths `shouldContain`
        [ "cabal.project"
        , "cabal.project.local.example"
        , ".hlint.yaml"
        , ".gitmessage"
        , "tagref.yml"
        ]

    it "synthesizes all required Git hooks with executable permissions" $ do
      let entries = generateProjectScaffold gongjuFixture
          hookEntries = filter (\e -> entryPath e `elem` [".githooks/commit-msg", ".githooks/pre-commit"]) entries
      length hookEntries `shouldBe` 2
      all entryExecutable hookEntries `shouldBe` True

    it "synthesizes all turnkey physical verification scripts in bin/" $ do
      let entries = generateProjectScaffold gongjuFixture
          paths = map entryPath entries
      paths `shouldContain`
        [ "bin/gongju-verify"
        , "bin/gongju-tagref"
        , "bin/gongju-linkcheck"
        , "bin/gongju-cloc"
        , "bin/generate-tags"
        ]
      let binEntries = filter (\e -> take 4 (entryPath e) == "bin/") entries
      all entryExecutable binEntries `shouldBe` True

    it "synthesizes canonical documentation corpus" $ do
      let entries = generateProjectScaffold gongjuFixture
          paths = map entryPath entries
      paths `shouldContain`
        [ "docs/INDEX.md"
        , "docs/TUTORIAL.md"
        , "docs/NEWBIE_GUIDE.md"
        , "docs/MAINTAINER_GUIDE.md"
        , "docs/notes/GONGJU_DESIGN.md"
        , "docs/notes/DOC_STRATEGY.md"
        , "docs/notes/COMMIT_ATTRIBUTION.md"
        ]

    it "synthesizes operational roadmap and agent advisory assets" $ do
      let entries = generateProjectScaffold gongjuFixture
          paths = map entryPath entries
      paths `shouldContain`
        [ "README.md"
        , "AGENTS.md"
        , "CLAUDE.md"
        , "PLAN.md"
        , "STATE.md"
        , ".agents/rules/commit-attribution.md"
        , ".agents/rules/code-navigation.md"
        , ".agents/rules/compiler-verification.md"
        , ".agents/rules/documentation-precedence.md"
        ]

    it "synthesizes multi-package hierarchy matching PackageSpec" $ do
      let entries = generateProjectScaffold gongjuFixture
          paths = map entryPath entries
      forM_
        [ "packages/gongju-core/gongju-core.cabal"
        , "packages/gongju-core/README.md"
        , "packages/gongju-core/src/Gongju/Core.hs"
        , "packages/gongju-core/src/Gongju/TypeLevel.hs"
        , "packages/gongju-core/test/Main.hs"
        ]
        (\p -> paths `shouldSatisfy` elem p)

    it "interpolates project metadata accurately across generated templates" $ do
      let entries = generateProjectScaffold gongjuFixture
          lookupContent p = case filter (\e -> entryPath e == p) entries of
            (e:_) -> entryContent e
            []    -> error ("Missing entry: " ++ p)
          cabalProject = lookupContent "cabal.project"
          readme = lookupContent "README.md"
          pkgCabal = lookupContent "packages/gongju-core/gongju-core.cabal"
          agents = lookupContent "AGENTS.md"

      cabalProject `shouldSatisfy` T.isInfixOf "with-compiler: ghc-9.14.1"
      readme `shouldSatisfy` T.isInfixOf "Nadia Yvette Chambers"
      readme `shouldSatisfy` T.isInfixOf "EUPL-1.2"
      pkgCabal `shouldSatisfy` T.isInfixOf "Gongju.Core"
      pkgCabal `shouldSatisfy` T.isInfixOf "Gongju.TypeLevel"
      agents `shouldSatisfy` T.isInfixOf "GONGJU_DESIGN.md"

  describe "Gachi.Scaffold.Engine (Filesystem Materialization)" $ do
    it "writes all files to disk creating parent directories and permissions" $ do
      withTempDir "gachi-scaffold-test" $ \tmpDir -> do
        let entries = generateProjectScaffold gongjuFixture
        res <- writeScaffold tmpDir FailOnExisting entries
        length (writtenFiles res) `shouldBe` length entries
        skippedFiles res `shouldBe` []

        -- Verify all files exist on disk
        forM_ entries $ \e -> do
          let path = tmpDir </> entryPath e
          exists <- doesFileExist path
          exists `shouldBe` True

        -- Verify executable bits
        let verifyScript = tmpDir </> "bin/gongju-verify"
            readme = tmpDir </> "README.md"
        verifyPerms <- getPermissions verifyScript
        executable verifyPerms `shouldBe` True
        readmePerms <- getPermissions readme
        executable readmePerms `shouldBe` False

    it "enforces FailOnExisting mode on pre-existing files" $ do
      withTempDir "gachi-fail-test" $ \tmpDir -> do
        let entries = generateProjectScaffold gongjuFixture
        _ <- writeScaffold tmpDir FailOnExisting entries
        result <- try (writeScaffold tmpDir FailOnExisting entries)
        case result of
          Left (DestinationExists _) -> pure ()
          _ -> expectationFailure "Expected FailOnExisting to raise DestinationExists exception"

    it "skips existing files cleanly under SkipExisting mode" $ do
      withTempDir "gachi-skip-test" $ \tmpDir -> do
        let entries = generateProjectScaffold gongjuFixture
        _ <- writeScaffold tmpDir FailOnExisting entries
        res <- writeScaffold tmpDir SkipExisting entries
        writtenFiles res `shouldBe` []
        length (skippedFiles res) `shouldBe` length entries

    it "overwrites existing files cleanly under OverwriteExisting mode" $ do
      withTempDir "gachi-overwrite-test" $ \tmpDir -> do
        let entries = generateProjectScaffold gongjuFixture
            readmePath = tmpDir </> "README.md"
        _ <- writeScaffold tmpDir FailOnExisting entries
        TIO.writeFile readmePath "CORRUPTED CONTENT"
        res <- writeScaffold tmpDir OverwriteExisting entries
        length (writtenFiles res) `shouldBe` length entries
        restoredContent <- TIO.readFile readmePath
        restoredContent `shouldSatisfy` T.isInfixOf "gongju"
        restoredContent `shouldNotSatisfy` T.isInfixOf "CORRUPTED CONTENT"

  describe "Generated Skeleton Self-Consistency Gates" $ do
    it "satisfies Tagref cross-reference integrity (0 dangling references, 0 duplicate tags)" $ do
      withTempDir "gachi-tagref-test" $ \tmpDir -> do
        _ <- generateAndWriteScaffold tmpDir FailOnExisting gongjuFixture
        let tagrefScript = tmpDir </> "bin/gongju-tagref"
        (exitCode, stdout, stderr) <- readProcessWithExitCode tagrefScript [] ""
        exitCode `shouldBe` ExitSuccess
        stdout `shouldSatisfy` (\out -> "0 dangling" `isInfixOfStr` out || "validated in" `isInfixOfStr` out)
        stderr `shouldBe` ""

    it "satisfies Markdown link & anchor integrity (0 broken links)" $ do
      withTempDir "gachi-link-test" $ \tmpDir -> do
        _ <- generateAndWriteScaffold tmpDir FailOnExisting gongjuFixture
        let linkScript = tmpDir </> "bin/gongju-linkcheck"
        (exitCode, stdout, stderr) <- readProcessWithExitCode linkScript ["--quiet"] ""
        exitCode `shouldBe` ExitSuccess
        stdout `shouldSatisfy` ("0 broken links" `isInfixOfStr`)
        stderr `shouldBe` ""

    it "satisfies CLOC comment density threshold (>= 25.0% gate, src >= 50.0%)" $ do
      withTempDir "gachi-cloc-test" $ \tmpDir -> do
        _ <- generateAndWriteScaffold tmpDir FailOnExisting gongjuFixture
        let clocScript = tmpDir </> "bin/gongju-cloc"
        (exitCode, stdout, stderr) <- readProcessWithExitCode clocScript ["--quiet", "--check"] ""
        exitCode `shouldBe` ExitSuccess
        stdout `shouldSatisfy` ("target: 50.0%+" `isInfixOfStr`)
        stderr `shouldBe` ""

-- | String infix helper for test assertions.
isInfixOfStr :: String -> String -> Bool
isInfixOfStr needle haystack =
  T.isInfixOf (T.pack needle) (T.pack haystack)
