{-# OPTIONS --no-copatterns #-}

-- Andreas, 2015-08-26: copatterns are on by default now.
-- Andreas, James, 2011-11-24
-- trigger error message 'NeedOptionCopatterns'
module NeedOptionCopatterns where

record Bla : Set2 where
  field
    bla : Set1
open Bla

f : Bla
bla f = Set
-- should request option --copatterns
