{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Control.Exception (SomeException, try)
import Data.Either (isLeft)
import Data.Text (Text)

import Gachi.Schema

main :: IO ()
main = hspec do
  -- Tested against Note [Dhall Parameterized Skeleton Templating] [ref:note-dhall-skeleton-templating]
  describe "Gachi.Schema Nominal Types & Invariants" do
    it "constructs turnkey default projects with canonical ecosystem standards" do
      let auth = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
          proj = defaultProject "gongju" auth

      projectName proj `shouldBe` "gongju"
      projectLicense proj `shouldBe` "EUPL-1.2"
      projectGhcVersion proj `shouldBe` "9.14.1"
      projectCabalVersion proj `shouldBe` "3.18"
      authorName (projectAuthor proj) `shouldBe` "Nadia Yvette Chambers"
      authorEmail (projectAuthor proj) `shouldBe` "nadia.yvette.chambers@ik.me"
      length (projectPackages proj) `shouldBe` 1
      case projectPackages proj of
        (pkg : _) -> packageName pkg `shouldBe` "gongju"
        []        -> expectationFailure "expected at least one package"
      projectRemotes proj `shouldBe` []

    it "exposes projection helpers disambiguating DuplicateRecordFields" do
      let auth = Author { name = "Ada Lovelace", email = "ada@analytical.org" }
          pkg = PackageSpec { name = "engine-core", synopsis = "Babbage engine simulator", exposes = ["Engine.Core"] }
          remote = RemoteSpec { name = "origin", url = "git@github.com:Ada/engine.git" }
          proj = Project
            { name = "analytical-engine"
            , description = "Computational pioneer project"
            , license = canonicalLicense
            , author = auth
            , ghcVersion = canonicalGhcVersion
            , cabalVersion = canonicalCabalVersion
            , packages = [pkg]
            , remotes = [remote]
            }

      projectName proj `shouldBe` "analytical-engine"
      authorName auth `shouldBe` "Ada Lovelace"
      packageName pkg `shouldBe` "engine-core"
      packageSynopsis pkg `shouldBe` "Babbage engine simulator"
      packageExposes pkg `shouldBe` ["Engine.Core"]
      remoteName remote `shouldBe` "origin"
      remoteUrl remote `shouldBe` "git@github.com:Ada/engine.git"

  describe "Gachi.Schema Open Row Isomorphisms" do
    it "faithfully roundtrips Author <-> AuthorRec" do
      let auth = Author { name = "Charles Babbage", email = "charles@difference.org" }
          recA = toAuthorRec auth
          auth' = fromAuthorRec recA
      auth' `shouldBe` auth

    it "faithfully roundtrips PackageSpec <-> PackageRec" do
      let pkg = PackageSpec
            { name = "difference-math"
            , synopsis = "Polynomial difference computation"
            , exposes = ["Math.Difference", "Math.Gear"]
            }
          recP = toPackageRec pkg
          pkg' = fromPackageRec recP
      pkg' `shouldBe` pkg

    it "faithfully roundtrips RemoteSpec <-> RemoteRec" do
      let rm = RemoteSpec { name = "radicle", url = "rad:git:hnrk12345678" }
          recR = toRemoteRec rm
          rm' = fromRemoteRec recR
      rm' `shouldBe` rm

    it "faithfully roundtrips Project <-> ProjectRec" do
      let auth = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
          proj = defaultProject "gachi" auth
          recProj = toProjectRec proj
          proj' = fromProjectRec recProj
      proj' `shouldBe` proj

  -- Tested against Note [Dhall Parameterized Skeleton Templating] [ref:note-dhall-skeleton-templating]
  describe "Gachi.Schema.Dhall Codecs & Evaluation" do
    it "decodes embedded exampleProjectDhall into strongly typed Project" do
      proj <- decodeProjectText exampleProjectDhall
      projectName proj `shouldBe` "gongju"
      projectLicense proj `shouldBe` "EUPL-1.2"
      authorName (projectAuthor proj) `shouldBe` "Nadia Yvette Chambers"
      length (projectPackages proj) `shouldBe` 1
      case projectPackages proj of
        (pkg : _) -> do
          packageName pkg `shouldBe` "gongju"
          packageExposes pkg `shouldBe`
            [ "Gongju.Peano"
            , "Gongju.Composition"
            , "Gongju.Positional"
            , "Gongju.Permute"
            , "Gongju.HList"
            ]
        [] -> expectationFailure "expected package list to be non-empty"
      length (projectRemotes proj) `shouldBe` 2
      map remoteName (projectRemotes proj) `shouldBe` ["github", "gitlab"]

    it "decodes open heterogeneous ProjectRec directly from Dhall" do
      recProj <- decodeProjectRecText exampleProjectDhall
      let proj = fromProjectRec recProj
      projectName proj `shouldBe` "gongju"
      projectLicense proj `shouldBe` "EUPL-1.2"

    it "roundtrips nominal Project through renderProjectDhall and decodeProjectText" do
      let auth = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
          orig = defaultProject "polytropos" auth
          rendered = renderProjectDhall orig
      decoded <- decodeProjectText rendered
      decoded `shouldBe` orig

    it "roundtrips open ProjectRec through renderProjectRecDhall and decodeProjectRecText" do
      let auth = Author { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" }
          origRec = toProjectRec (defaultProject "polytropos" auth)
          rendered = renderProjectRecDhall origRec
      decodedRec <- decodeProjectRecText rendered
      fromProjectRec decodedRec `shouldBe` fromProjectRec origRec
      projectName (fromProjectRec decodedRec) `shouldBe` "polytropos"

    it "gracefully returns Left for malformed Dhall expressions" do
      let invalidDhall = "{ name = \"broken\", license = 123 }" :: Text
      res <- decodeProjectEither invalidDhall
      res `shouldSatisfy` isLeft

    it "decodes project specification from disk file" do
      res1 <- try (decodeProjectFile "dhall/example-project.dhall") :: IO (Either SomeException Project)
      proj <- case res1 of
        Right p -> pure p
        Left _  -> decodeProjectFile "packages/gachi-schema/dhall/example-project.dhall"
      projectName proj `shouldBe` "gongju"
      projectLicense proj `shouldBe` "EUPL-1.2"
