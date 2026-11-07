let Schema = ./Schema.dhall

let project : Schema.Project =
  { name = "gongju"
  , description = "Algebraic standard library and domain utilities for Haskell ecosystems"
  , version = "0.1.0.0"
  , category = "Development"
  , license = Schema.singleton Text "EUPL-1.2"
  , author =
    { name = "Nadia Yvette Chambers"
    , email = "nadia.yvette.chambers@ik.me"
    }
  , ghcVersion = "9.14.1"
  , cabalVersion = "3.18"
  , packages =
      Schema.singleton Schema.Package
        { name = "gongju"
        , synopsis = "Algebraic library foundation"
        , exposes = [ "Gongju", "Gongju.Core" ]
        }
  , remotes =
    [ { name = "radicle", url = "rad:git:hnrk.../gongju" }
    , { name = "github", url = "git@github.com:NadiaYvette/gongju.git" }
    ]
  }

in  project
