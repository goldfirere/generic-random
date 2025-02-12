-- | Generic implementations of
-- [QuickCheck](https://hackage.haskell.org/package/QuickCheck)'s
-- @arbitrary@.
--
-- = Example
--
-- Define your type.
--
-- @
-- data Tree a = Leaf a | Node (Tree a) (Tree a)
--   deriving 'GHC.Generics.Generic'
-- @
--
-- Pick an 'Test.QuickCheck.arbitrary' implementation, specifying the required distribution of
-- data constructors.
--
-- @
-- instance Arbitrary a => Arbitrary (Tree a) where
--   arbitrary = 'genericArbitrary' (9 '%' 8 '%' ())
-- @
--
-- That random generator @arbitrary :: 'Test.QuickCheck.Gen' (Tree a)@ picks a
-- @Leaf@ with probability 9\/17, or a
-- @Node@ with probability 8\/17, and recursively fills their fields with
-- @arbitrary@.
--
-- For @Tree@, the generic implementation 'genericArbitrary' is equivalent to
-- the following:
--
-- @
-- 'genericArbitrary' :: Arbitrary a => 'Weights' (Tree a) -> Gen (Tree a)
-- 'genericArbitrary' (x '%' y '%' ()) =
--   frequency
--     [ (x, Leaf '<$>' arbitrary)
--     , (y, Node '<$>' arbitrary '<*>' arbitrary)
--     ]
-- @
--
-- = Distribution of constructors
--
-- The distribution of constructors can be specified as
-- a special list of /weights/ in the same order as the data type definition.
-- This assigns to each constructor a probability @p_C@ proportional to its weight @weight_C@;
-- in other words, @p_C = weight_C / sumOfWeights@.
--
-- The list of weights is built up with the @('%')@ operator as a cons, and using
-- the unit @()@ as the empty list, in the order corresponding to the data type
-- definition.
--
-- == Uniform distribution
--
-- You can specify the uniform distribution (all weights equal to 1) with 'uniform'.
-- ('genericArbitraryU' is available as a shorthand for
-- @'genericArbitrary' 'uniform'@.)
--
-- Note that for many recursive types, a uniform distribution tends to produce
-- big or even infinite values.
--
-- == Typed weights
--
-- The weights actually have type @'W' \"ConstructorName\"@ (just a newtype
-- around 'Int'), so that you can annotate a weight with its corresponding
-- constructor. The constructors must appear in the same order as in the
-- original type definition.
--
-- This will type-check:
--
-- @
-- ((x :: 'W' \"Leaf\") '%' (y :: 'W' \"Node\") '%' ()) :: 'Weights' (Tree a)
-- ( x              '%' (y :: 'W' \"Node\") '%' ()) :: 'Weights' (Tree a)
-- @
--
-- This will not:
--
-- @
-- ((x :: 'W' \"Node\") '%' y '%' ()) :: 'Weights' (Tree a)
-- -- Requires an order of constructors different from the definition of the @Tree@ type.
--
-- ( x              '%' y '%' z '%' ()) :: 'Weights' (Tree a)
-- -- Doesn't have the right number of weights.
-- @
--
-- = Ensuring termination
--
-- As mentioned earlier, one must be careful with recursive types
-- to avoid producing extremely large values.
-- The alternative generator 'genericArbitraryRec' decreases the size
-- parameter at every call to keep values at reasonable sizes.
-- It is to be used together with 'withBaseCase'.
--
-- For example, we may provide a base case consisting of only @Leaf@:
--
-- @
-- instance Arbitrary a => Arbitrary (Tree a) where
--   arbitrary = 'genericArbitraryRec' (1 '%' 2 '%' ())
--     ``withBaseCase`` (Leaf '<$>' arbitrary)
-- @
--
-- That is equivalent to the following definition. Note the
-- 'Test.QuickCheck.resize' modifier.
--
-- @
-- arbitrary :: Arbitrary a => Gen (Tree a)
-- arbitrary = sized $ \\n ->
--   -- "if" condition from withBaseCase
--   if n == 0 then
--     Leaf \<$\> arbitrary
--   else
--     -- genericArbitraryRec
--     frequency
--       [ (1, resize (max 0 (n - 1)) (Leaf '<$>' arbitrary))
--       , (2, resize (n \`div\` 2)     (Node '<$>' arbitrary '<*>' arbitrary))
--       ]
-- @
--
-- The resizing strategy is as follows:
-- the size parameter of 'Test.QuickCheck.Gen' is divided among the fields of
-- the chosen constructor, or decreases by one if the constructor is unary.
-- @'withBaseCase' defG baseG@ is equal to @defG@ as long as the size parameter
-- is nonzero, and it becomes @baseG@ once the size reaches zero.
-- This combination generally ensures that the number of constructors remains
-- bounded by the initial size parameter passed to 'Test.QuickCheck.Gen'.
--
-- == Automatic base case discovery
--
-- In some situations, generic-random can also construct base cases automatically.
-- This works best with fully concrete types (no type parameters).
--
-- @
-- {-\# LANGUAGE FlexibleInstances #-}
--
-- instance Arbitrary (Tree ()) where
--   arbitrary = 'genericArbitrary'' (1 '%' 2 '%' ())
-- @
--
-- The above instance will infer the value @Leaf ()@ as a base case.
--
-- To discover values of type @Tree a@, we must inspect the type argument @a@,
-- thus we incur some extra constraints if we want polymorphism.
-- It is preferrable to apply the type class 'BaseCase' to the instance head
-- (@Tree a@) as follows, as it doesn't reduce to something worth seeing.
--
-- @
-- {-\# LANGUAGE FlexibleContexts, UndecidableInstances \#-}
--
-- instance (Arbitrary a, 'BaseCase' (Tree a))
--   => Arbitrary (Tree a) where
--   arbitrary = 'genericArbitrary'' (1 '%' 2 '%' ())
-- @
--
-- The 'BaseCase' type class finds values of minimal depth,
-- where the depth of a constructor is defined as @1 + max(0, depths of fields)@,
-- e.g., @Leaf ()@ has depth 2.
--
-- == Note about lists #notelists#
--
-- The @Arbitrary@ instance for lists can be problematic for this way
-- of implementing recursive sized generators, because they make a lot of
-- recursive calls to 'Test.QuickCheck.arbitrary' without decreasing the size parameter.
-- Hence, as a default, 'genericArbitraryRec' also detects fields which are
-- lists to replace 'Test.QuickCheck.arbitrary' with a different generator that divides
-- the size parameter by the length of the list before generating each
-- element. This uses the customizable mechanism shown in the next section.
--
-- If you really want to use 'Test.QuickCheck.arbitrary' for lists in the derived instances,
-- substitute @'genericArbitraryRec'@ with @'genericArbitraryRecG' ()@.
--
-- @
-- arbitrary = 'genericArbitraryRecG' ()
--   ``withBaseCase`` baseGen
-- @
--
-- Some combinators are available for further tweaking: 'listOf'', 'listOf1'',
-- 'vectorOf''.
--
-- = Custom generators for some fields
--
-- == Example 1 ('Test.QuickCheck.Gen', 'FieldGen')
--
-- Sometimes, a few fields may need custom generators instead of 'Test.QuickCheck.arbitrary'.
-- For example, imagine here that @String@ is meant to represent
-- alphanumerical strings only, and that IDs are meant to be nonnegative,
-- whereas balances can have any sign.
--
-- @
-- data User = User {
--   userName :: String,
--   userId :: Int,
--   userBalance :: Int
--   } deriving 'GHC.Generics.Generic'
-- @
--
-- A naive approach has the following problems:
--
-- - @'Test.QuickCheck.Arbitrary' String@ may generate any unicode character,
--   alphanumeric or not;
-- - @'Test.QuickCheck.Arbitrary' Int@ may generate negative values;
-- - using @newtype@ wrappers or passing generators explicitly to properties
--   may be impractical (the maintenance overhead can be high because the types
--   are big or change often).
--
-- Using generic-random, we can declare a (heterogeneous) list of generators to
-- be used instead of 'Test.QuickCheck.arbitrary' when generating certain fields.
--
-- @
-- customGens :: 'FieldGen' "userId" Int ':+' 'Test.QuickCheck.Gen' String
-- customGens =
--   'FieldGen' ('Test.QuickCheck.getNonNegative' '<$>' arbitrary) ':+'
--   'Test.QuickCheck.listOf' ('Test.QuickCheck.elements' (filter isAlphaNum [minBound .. maxBound]))
-- @
--
-- Now we use the 'genericArbitraryG' combinator and other @G@-suffixed
-- variants that accept those explicit generators.
--
-- - All @String@ fields will use the provided generator of
--   alphanumeric strings;
-- - the field @"userId"@ of type @Int@ will use the generator
--   of nonnegative integers;
-- - everything else defaults to 'Test.QuickCheck.arbitrary'.
--
-- @
-- instance Arbitrary User where
--   arbitrary = 'genericArbitrarySingleG' customGens
-- @
--
-- == Example 2 ('ConstrGen')
--
-- Here's the @Tree@ type from the beginning again.
--
-- @
-- data Tree a = Leaf a | Node (Tree a) (Tree a)
--   deriving 'GHC.Generics.Generic'
-- @
--
-- We will generate "right-leaning linear trees", which look like this:
--
-- > Node (Leaf 1)
-- >      (Node (Leaf 2)
-- >            (Node (Leaf 3)
-- >                  (Node (Leaf 4)
-- >                        (Leaf 5))))
--
-- To do so, we force every left child of a @Node@ to be a @Leaf@:
--
-- @
-- {-\# LANGUAGE ScopedTypeVariables \#-}
--
-- instance Arbitrary a => Arbitrary (Tree a) where
--   arbitrary = 'genericArbitraryUG' customGens
--     where
--       -- Generator for the left field (i.e., at index 0) of constructor Node,
--       -- which must have type (Tree a).
--       customGens :: 'ConstrGen' \"Node\" 0 (Tree a)
--       customGens =  'ConstrGen' (Leaf '<$>' arbitrary)
-- @
--
-- That instance is equivalent to the following:
--
-- @
-- instance Arbitrary a => Arbitrary (Tree a) where
--   arbitrary = oneof
--     [ Leaf '<$>' arbitrary
--     , Node '<$>' (Leaf '<$>' arbitrary) '<*>' arbitrary
--     --                                  ^ recursive call
--     ]
-- @
--
-- == Custom generators reference
--
-- The custom generator modifiers that can occur in the list are:
--
-- - 'Test.QuickCheck.Gen': a generator for a specific type;
-- - 'FieldGen': a generator for a record field;
-- - 'ConstrGen': a generator for a field of a given constructor;
-- - 'Gen1': a generator for \"containers\", parameterized by a generator
--   for individual elements;
-- - 'Gen1_': a generator for unary type constructors that are not
--   containers.
--
-- Suggestions to add more modifiers or otherwise improve this tutorial are welcome!
-- <https://github.com/Lysxia/generic-random/issues The issue tracker is this way.>

{-# OPTIONS_GHC -Wno-unused-imports #-}

module Generic.Random.Tutorial () where

import Generic.Random
