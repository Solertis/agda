{-# LANGUAGE CPP             #-}
{-# LANGUAGE TemplateHaskell #-}

module InternalTests.TypeChecking.Positivity.Occurrence ( tests ) where

import Agda.TypeChecking.Positivity.Occurrence
import Agda.Utils.SemiRing
import Agda.Utils.List ( uniqOn )

#if __GLASGOW_HASKELL__ <= 708
import Control.Applicative ( (<$>), (<*>) )
#endif

import Data.Either
import qualified Data.Map.Strict as Map

import InternalTests.Helpers
import InternalTests.Syntax.Abstract.Name ()

import Test.QuickCheck

------------------------------------------------------------------------------
-- QuickCheck instances

instance Arbitrary OccursWhere where
  arbitrary = oneof [return Unknown, Known <$> arbitrary <*> arbitrary]

  shrink Unknown      = []
  shrink (Known r ws) = Unknown : [ Known r ws | r <- shrink r, ws <- shrink ws ]

instance Arbitrary Where where
  arbitrary = oneof
    [ return LeftOfArrow
    , DefArg <$> arbitrary <*> arbitrary
    , return UnderInf
    , return VarArg
    , return MetaArg
    , ConArgType <$> arbitrary
    , IndArgType <$> arbitrary
    , InClause <$> arbitrary
    , return Matched
    , InDefOf <$> arbitrary
    ]

instance CoArbitrary OccursWhere where
  coarbitrary (Known r ws) = variant 0 . coarbitrary (r, ws)
  coarbitrary Unknown      = variant 1

instance CoArbitrary Where where
  coarbitrary LeftOfArrow    = variant 0
  coarbitrary (DefArg a b)   = variant 1 . coarbitrary (a, b)
  coarbitrary UnderInf       = variant 2
  coarbitrary VarArg         = variant 3
  coarbitrary MetaArg        = variant 4
  coarbitrary (ConArgType a) = variant 5 . coarbitrary a
  coarbitrary (IndArgType a) = variant 6 . coarbitrary a
  coarbitrary (InClause a)   = variant 7 . coarbitrary a
  coarbitrary Matched        = variant 8
  coarbitrary (InDefOf a)    = variant 9 . coarbitrary a

instance Arbitrary Occurrence where
  arbitrary = elements [minBound .. maxBound]

  shrink Unused = []
  shrink _      = [Unused]

instance CoArbitrary Occurrence where
  coarbitrary = coarbitrary . fromEnum

------------------------------------------------------------------------
-- Tests

prop_Occurrence_oplus_associative ::
  Occurrence -> Occurrence -> Occurrence -> Bool
prop_Occurrence_oplus_associative = isAssociative oplus

prop_Occurrence_oplus_ozero :: Occurrence -> Bool
prop_Occurrence_oplus_ozero = isIdentity ozero oplus

prop_Occurrence_oplus_commutative :: Occurrence -> Occurrence -> Bool
prop_Occurrence_oplus_commutative = isCommutative oplus

prop_Occurrence_otimes_associative ::
  Occurrence -> Occurrence -> Occurrence -> Bool
prop_Occurrence_otimes_associative = isAssociative otimes

prop_Occurrence_otimes_oone :: Occurrence -> Bool
prop_Occurrence_otimes_oone = isIdentity oone otimes

prop_Occurrence_distributive ::
  Occurrence -> Occurrence -> Occurrence -> Bool
prop_Occurrence_distributive = isDistributive otimes oplus

prop_Occurrence_otimes_ozero :: Occurrence -> Bool
prop_Occurrence_otimes_ozero = isZero ozero otimes

prop_Occurrence_ostar :: Occurrence -> Bool
prop_Occurrence_ostar x =
  ostar x == oplus oone (otimes x (ostar x))
    &&
  ostar x == oplus oone (otimes (ostar x) x)

-- | Is the given predicate satisfiable?

satisfiable :: (Occurrence -> Bool) -> Bool
satisfiable p = or [ p o | o <- [minBound .. maxBound] ]

-- Some properties that are used in the implementation of
-- prop_boundToEverySome2.

prop_boundToEverySome0 :: Bool
prop_boundToEverySome0 = and
  [ length ess >= 1
      &&
    all satisfiable ps
      &&
    and [ p minBound | p <- ps ]
      &&
    all (\p -> satisfiable (not . p)) [ e | (e, _) <- ess ]
      &&
    and [ not (p maxBound) | p <- ps, satisfiable (not . p) ]
  | (_, ess) <- Map.toList boundToEverySome
  , let ps = concat [ [e, s] | (e, s) <- ess ]
  ]

-- A simple property that does not always generate enough interesting
-- test cases.

prop_boundToEverySome1 :: NonEmptyList Occurrence -> Property
prop_boundToEverySome1 (NonEmpty w) =
  forAll (elements $ Map.toList boundToEverySome) $ \(bound, ess) ->
    (foldr1 otimes w <= bound)
      ==
    or [ all every w && any some w | (every, some) <- ess ]

-- A more complicated property that does not always generate enough
-- interesting test cases.

prop_boundToEverySome2 :: Property
prop_boundToEverySome2 =
  forAll (elements $ Map.toList boundToEverySome) $ \(bound, ess) ->
    (forAll (oneof [ do os1 <- listOf (arbitrary `suchThat` every)
                        o   <- arbitrary
                                 `suchThat` (\o -> every o && some o)
                        os2 <- listOf (arbitrary `suchThat` every)
                        return (os1 ++ [o] ++ os2)
                   | (every, some) <- ess
                   ]) $ \w ->
       foldr1 otimes w <= bound)
      .&&.
    (forAll (do
         ess <- mapM (\(e, s) ->
                         elements
                           (Left e :
                            [ Right s | satisfiable (not . s) ])) ess
         let (es, ss) = partitionEithers ess
             every    = \o -> and [ not (s o) | s <- ss ]
             some e   = \o -> every o && not (e o)
             everyG   = arbitrary `suchThat` every
             segment  = listOf everyG
         os <- uniqOn id <$> mapM (\e -> arbitrary `suchThat` some e) es
         if Prelude.null os
           then listOf1 everyG
           else (++) <$> listOf everyG
                     <*> (concat <$>
                            mapM (\o -> (o :) <$> listOf everyG) os))
       (\w -> not (foldr1 otimes w <= bound)))

------------------------------------------------------------------------

-- Template Haskell hack to make the following $quickCheckAll work
-- under GHC 7.8.
return []

-- | Tests.

tests :: IO Bool
tests = do
  putStrLn "InternalTests.TypeChecking.Positivity.Occurrence"
  $quickCheckAll
