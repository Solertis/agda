{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE PatternGuards #-}

-- | The treeless syntax is intended to be used as input for the compiler backends.
-- It is more low-level than Internal syntax and is not used for type checking.
--
-- Some of the features of treeless syntax are:
-- - case expressions instead of case trees
-- - no instantiated datatypes / constructors
module Agda.Syntax.Treeless
    ( module Agda.Syntax.Abstract.Name
    , module Agda.Syntax.Treeless
    ) where

import Prelude

import Data.Map (Map)
import Data.Typeable (Typeable)

import Agda.Syntax.Position
import Agda.Syntax.Literal
import Agda.Syntax.Abstract.Name

type Args = [TTerm]

-- this currently assumes that TApp is translated in a lazy/cbn fashion.
-- The AST should also support strict translation.
--
-- All local variables are using de Bruijn indices.
data TTerm = TVar Int
           | TPrim TPrim
           | TDef QName
           | TApp TTerm Args
           | TLam TTerm
           | TLit Literal
           | TCon QName
           | TLet TTerm TTerm
           -- ^ introduces a new local binding. The bound term
           -- MUST only be evaluated if it is used inside the body.
           -- Sharing may happen, but is optional.
           -- It is also perfectly valid to just inline the bound term in the body.
           | TCase Int CaseType TTerm [TAlt]
           -- ^ Case scrutinee (always variable), case type, default value, alternatives
           -- The order of alternatives is significant if there is any TAPlus alternative;
           -- alternatives are matched top to bottom in that case.
           | TUnit -- used for levels right now
           | TSort
           | TErased
           | TError TError
           -- ^ A runtime error, something bad has happened.
  deriving (Typeable, Show, Eq, Ord)

-- | Compiler-related primitives. This are NOT the same thing as primitives
-- in Agda's surface or internal syntax!
data TPrim = PAdd | PSub | PDiv | PMod | PGeq | PIf
  deriving (Typeable, Show, Eq, Ord)

mkTApp :: TTerm -> Args -> TTerm
mkTApp x [] = x
mkTApp x as = TApp x as

tAppView :: TTerm -> [TTerm]
tAppView = view
  where
    view t = case t of
      TApp a bs -> view a ++ bs
      _         -> [t]

-- | Introduces a new binding
mkLet :: TTerm -> TTerm -> TTerm
mkLet x body = TLet x body

tInt :: Integer -> TTerm
tInt = TLit . LitInt noRange

intView :: TTerm -> Maybe Integer
intView (TLit (LitInt _ x)) = Just x
intView _ = Nothing

tPlusK :: Integer -> TTerm -> TTerm
tPlusK k n = TApp (TPrim PAdd) [tInt k, n]

plusKView :: TTerm -> Maybe (Integer, TTerm)
plusKView (TApp (TPrim PAdd) [k, n]) | Just k <- intView k = Just (k, n)
plusKView _ = Nothing

tOp :: TPrim -> TTerm -> TTerm -> TTerm
tOp op a b = TApp (TPrim op) [a, b]

data CaseType
  = CTData QName -- case on datatype
  | CTChar
  | CTString
  | CTQName
  deriving (Typeable, Show, Eq, Ord)

data TAlt
  = TACon    { aCon  :: QName, aArity :: Int, aBody :: TTerm }
  -- ^ Matches on the given constructor. If the match succeeds,
  -- the pattern variables are prepended to the current environment
  -- (pushes all existing variables aArity steps further away)
  | TAPlus   { aSucs :: Integer, aBody :: TTerm }
  -- ^ n+k pattern
  | TALit    { aLit :: Literal,   aBody:: TTerm }
  deriving (Typeable, Show, Eq, Ord)

data TError
  = TUnreachable QName {- def name where it happend -}
  -- ^ Code which is unreachable. E.g. absurd branches or missing case defaults.
  -- Runtime behaviour of unreachable code is undefined, but preferably
  -- the program will exit with an error message. The compiler is free
  -- to assume that this code is unreachable and to remove it.
  deriving (Typeable, Show, Eq, Ord)