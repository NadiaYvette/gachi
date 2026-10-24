{-
  Example Gachi Project Specification
  SPDX-License-Identifier: EUPL-1.2
-}
let Schema = ./Schema.dhall

let project : Schema.Project =
  { name = "gongju"
  , description = "Type-level utility functions and Peano arithmetic crucible"
  , license = "EUPL-1.2"
  , author =
      { name = "Nadia Yvette Chambers"
      , email = "nadia.yvette.chambers@ik.me"
      }
  , ghcVersion = "9.14.1"
  , cabalVersion = "3.18"
  , packages =
      [ { name = "gongju"
        , synopsis = "Pure Peano type-level utilities and HList operations"
        , exposes =
            [ "Gongju.Peano"
            , "Gongju.Composition"
            , "Gongju.Positional"
            , "Gongju.Permute"
            , "Gongju.HList"
            ]
        }
      ]
  , remotes =
      [ { name = "github"
        , url = "git@github.com:NadiaYvette/gongju.git"
        }
      , { name = "gitlab"
        , url = "git@gitlab.com:NadiaYvette/gongju.git"
        }
      ]
  }

in  project
