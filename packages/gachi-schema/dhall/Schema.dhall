{-
  Gachi Project & Ecosystem Scaffolding Schema
  SPDX-License-Identifier: EUPL-1.2
-}
let Author : Type =
  { name : Text
  , email : Text
  }

let Package : Type =
  { name : Text
  , synopsis : Text
  , exposes : List Text
  }

let Remote : Type =
  { name : Text
  , url : Text
  }

let Project : Type =
  { name : Text
  , description : Text
  , license : Text
  , author : Author
  , ghcVersion : Text
  , cabalVersion : Text
  , packages : List Package
  , remotes : List Remote
  }

in  { Author = Author
    , Package = Package
    , Remote = Remote
    , Project = Project
    }
