{-
  Gachi Project & Ecosystem Scaffolding Schema
  SPDX-License-Identifier: EUPL-1.2
-}
let NonEmpty : Type -> Type =
  \(a : Type) ->
    { head : a
    , tail : List a
    }

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
  , version : Text
  , category : Text
  , license : NonEmpty Text
  , author : Author
  , ghcVersion : Text
  , cabalVersion : Text
  , packages : NonEmpty Package
  , remotes : List Remote
  }

let singleton : forall (a : Type) -> a -> NonEmpty a =
  \(a : Type) -> \(x : a) -> { head = x, tail = [] : List a }

let cons : forall (a : Type) -> a -> List a -> NonEmpty a =
  \(a : Type) -> \(x : a) -> \(xs : List a) -> { head = x, tail = xs }

in  { NonEmpty = NonEmpty
    , Author = Author
    , Package = Package
    , Remote = Remote
    , Project = Project
    , singleton = singleton
    , cons = cons
    }
