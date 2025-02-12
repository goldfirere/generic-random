{-# OPTIONS_HADDOCK not-home #-}

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Base case discovery.
--
-- === Warning
--
-- This is an internal module: it is not subject to any versioning policy,
-- breaking changes can happen at any time.
--
-- If something here seems useful, please report it or create a pull request to
-- export it from an external module.

module Generic.Random.Internal.BaseCase where

import Control.Applicative
import Data.Proxy
import Data.Kind (Type)
import GHC.Generics
import GHC.TypeLits
import Test.QuickCheck

import Generic.Random.Internal.Generic

-- | Decrease size to ensure termination for
-- recursive types, looking for base cases once the size reaches 0.
--
-- > genericArbitrary' (17 % 19 % 23 % ()) :: Gen a
--
-- N.B.: This replaces the generator for fields of type @[t]@ with
-- @'Test.QuickCheck.listOf'' arbitrary@ instead of @'Test.QuickCheck.listOf' arbitrary@ (i.e., @arbitrary@ for
-- lists).
genericArbitrary'
  :: (GArbitrary SizedOptsDef a, BaseCase a)
  => Weights a  -- ^ List of weights for every constructor
  -> Gen a
genericArbitrary' w = genericArbitraryRec w `withBaseCase` baseCase

-- | Equivalent to @'genericArbitrary'' 'uniform'@.
--
-- > genericArbitraryU' :: Gen a
--
-- N.B.: This replaces the generator for fields of type @[t]@ with
-- @'Test.QuickCheck.listOf'' arbitrary@ instead of @'Test.QuickCheck.listOf' arbitrary@ (i.e., @arbitrary@ for
-- lists).
genericArbitraryU'
  :: (GArbitrary SizedOptsDef a, BaseCase a, GUniformWeight a)
  => Gen a
genericArbitraryU' = genericArbitrary' uniform

-- | Run the first generator if the size is positive.
-- Run the second if the size is zero.
--
-- > defaultGen `withBaseCase` baseCaseGen
withBaseCase :: Gen a -> Gen a -> Gen a
withBaseCase def bc = sized $ \sz ->
  if sz > 0 then def else bc


-- | Find a base case of type @a@ with maximum depth @z@,
-- recursively using 'BaseCaseSearch' instances to search deeper levels.
--
-- @y@ is the depth of a base case, if found.
--
-- @e@ is the original type the search started with, that @a@ appears in.
-- It is used for error reporting.
class BaseCaseSearch (a :: Type) (z :: Nat) (y :: Maybe Nat) (e :: Type) where
  baseCaseSearch :: prox y -> proxy '(z, e) -> IfM y Gen Proxy a


instance {-# OVERLAPPABLE #-} GBaseCaseSearch a z y e => BaseCaseSearch a z y e where
  baseCaseSearch = gBaseCaseSearch


instance (y ~ 'Just 0) => BaseCaseSearch Char z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Int z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Integer z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Float z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Double z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Word z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch () z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch Bool z y e where
  baseCaseSearch _ _ = arbitrary

instance (y ~ 'Just 0) => BaseCaseSearch [a] z y e where
  baseCaseSearch _ _ = return []

instance (y ~ 'Just 0) => BaseCaseSearch Ordering z y e where
  baseCaseSearch _ _ = arbitrary

-- Either and (,) use Generics


class BaseCaseSearching_ a z y where
  baseCaseSearching_ :: proxy y -> proxy2 '(z, a) -> IfM y Gen Proxy a -> Gen a

instance BaseCaseSearching_ a z ('Just m) where
  baseCaseSearching_ _ _ = id

instance BaseCaseSearching a (z + 1) => BaseCaseSearching_ a z 'Nothing where
  baseCaseSearching_ _ _ _ = baseCaseSearching (Proxy :: Proxy '(z + 1, a))

-- | Progressively increase the depth bound for 'BaseCaseSearch'.
class BaseCaseSearching a z where
  baseCaseSearching :: proxy '(z, a) -> Gen a

instance (BaseCaseSearch a z y a, BaseCaseSearching_ a z y) => BaseCaseSearching a z where
  baseCaseSearching z = baseCaseSearching_ y z (baseCaseSearch y z)
    where
      y = Proxy :: Proxy y

-- | Custom instances can override the default behavior.
class BaseCase a where
  -- | Generator of base cases.
  baseCase :: Gen a

-- | Overlappable
instance {-# OVERLAPPABLE #-} BaseCaseSearching a 0 => BaseCase a where
  baseCase = baseCaseSearching (Proxy :: Proxy '(0, a))


type family IfM (b :: Maybe t) (c :: k) (d :: k) :: k
type instance IfM ('Just t) c d = c
type instance IfM 'Nothing c d = d

type (==) m n = IsEQ (CmpNat m n)

type family IsEQ (e :: Ordering) :: Bool
type instance IsEQ 'EQ = 'True
type instance IsEQ 'GT = 'False
type instance IsEQ 'LT = 'False

type family (||?) (b :: Maybe Nat) (c :: Maybe Nat) :: Maybe Nat
type instance 'Just m ||? 'Just n = 'Just (Min m n)
type instance m ||? 'Nothing = m
type instance 'Nothing ||? n = n

type family (&&?) (b :: Maybe Nat) (c :: Maybe Nat) :: Maybe Nat
type instance 'Just m &&? 'Just n = 'Just (Max m n)
type instance m &&? 'Nothing = 'Nothing
type instance 'Nothing &&? n = 'Nothing

type Max m n = MaxOf (CmpNat m n) m n

type family MaxOf (e :: Ordering) (m :: k) (n :: k) :: k
type instance MaxOf 'GT m n = m
type instance MaxOf 'EQ m n = m
type instance MaxOf 'LT m n = n

type Min m n = MinOf (CmpNat m n) m n

type family MinOf (e :: Ordering) (m :: k) (n :: k) :: k
type instance MinOf 'GT m n = n
type instance MinOf 'EQ m n = n
type instance MinOf 'LT m n = m

class Alternative (IfM y Weighted Proxy)
  => GBCS (f :: k -> Type) (z :: Nat) (y :: Maybe Nat) (e :: Type) where
  gbcs :: prox y -> proxy '(z, e) -> IfM y Weighted Proxy (f p)

instance GBCS f z y e => GBCS (M1 i c f) z y e where
  gbcs y z = fmap M1 (gbcs y z)

instance
  ( GBCSSum f g z e yf yg
  , GBCS f z yf e
  , GBCS g z yg e
  , y ~ (yf ||? yg)
  ) => GBCS (f :+: g) z y e where
  gbcs _ z = gbcsSum (Proxy :: Proxy '(yf, yg)) z
    (gbcs (Proxy :: Proxy yf) z)
    (gbcs (Proxy :: Proxy yg) z)

class Alternative (IfM (yf ||? yg) Weighted Proxy) => GBCSSum f g z e yf yg where
  gbcsSum
    :: prox '(yf, yg)
    -> proxy '(z, e)
    -> IfM yf Weighted Proxy (f p)
    -> IfM yg Weighted Proxy (g p)
    -> IfM (yf ||? yg) Weighted Proxy ((f :+: g) p)

instance GBCSSum f g z e 'Nothing 'Nothing where
  gbcsSum _ _ _ _ = Proxy

instance GBCSSum f g z e ('Just m) 'Nothing where
  gbcsSum _ _ f _ = fmap L1 f

instance GBCSSum f g z e 'Nothing ('Just n) where
  gbcsSum _ _ _ g = fmap R1 g

instance GBCSSumCompare f g z e (CmpNat m n)
  => GBCSSum f g z e ('Just m) ('Just n) where
  gbcsSum _ = gbcsSumCompare (Proxy :: Proxy (CmpNat m n))

class GBCSSumCompare f g z e o where
  gbcsSumCompare
    :: proxy0 o
    -> proxy '(z, e)
    -> Weighted (f p)
    -> Weighted (g p)
    -> Weighted ((f :+: g) p)

instance GBCSSumCompare f g z e 'EQ where
  gbcsSumCompare _ _ f g = fmap L1 f <|> fmap R1 g

instance GBCSSumCompare f g z e 'LT where
  gbcsSumCompare _ _ f _ = fmap L1 f

instance GBCSSumCompare f g z e 'GT where
  gbcsSumCompare _ _ _ g = fmap R1 g

instance
  ( GBCSProduct f g z e yf yg
  , GBCS f z yf e
  , GBCS g z yg e
  , y ~ (yf &&? yg)
  ) => GBCS (f :*: g) z y e where
  gbcs _ z = gbcsProduct (Proxy :: Proxy '(yf, yg)) z
    (gbcs (Proxy :: Proxy yf) z)
    (gbcs (Proxy :: Proxy yg) z)

class Alternative (IfM (yf &&? yg) Weighted Proxy) => GBCSProduct f g z e yf yg where
  gbcsProduct
    :: prox '(yf, yg)
    -> proxy '(z, e)
    -> IfM yf Weighted Proxy (f p)
    -> IfM yg Weighted Proxy (g p)
    -> IfM (yf &&? yg) Weighted Proxy ((f :*: g) p)

instance {-# OVERLAPPABLE #-} ((yf &&? yg) ~ 'Nothing) => GBCSProduct f g z e yf yg where
  gbcsProduct _ _ _ _ = Proxy

instance GBCSProduct f g z e ('Just m) ('Just n) where
  gbcsProduct _ _ f g = liftA2 (:*:) f g

class IsMaybe b where
  ifMmap :: proxy b -> (c a -> c' a') -> (d a -> d' a') -> IfM b c d a -> IfM b c' d' a'
  ifM :: proxy b -> c a -> d a -> IfM b c d a

instance IsMaybe ('Just t) where
  ifMmap _ f _ a = f a
  ifM _ f _ = f

instance IsMaybe 'Nothing where
  ifMmap _ _ g a = g a
  ifM _ _ g = g

instance {-# OVERLAPPABLE #-}
  ( BaseCaseSearch c (z - 1) y e
  , (z == 0) ~ 'False
  , Alternative (IfM y Weighted Proxy)
  , IsMaybe y
  ) => GBCS (K1 i c) z y e where
  gbcs y _ =
    fmap K1
      (ifMmap y
        liftGen
        (id :: Proxy c -> Proxy c)
        (baseCaseSearch y (Proxy :: Proxy '(z - 1, e))))

instance (y ~ 'Nothing) => GBCS (K1 i c) 0 y e where
  gbcs _ _ = empty

instance (y ~ 'Just 0) => GBCS U1 z y e where
  gbcs _ _ = pure U1

instance {-# INCOHERENT #-}
  ( TypeError
      (     'Text "Unrecognized Rep: "
      ':<>: 'ShowType f
      ':$$: 'Text "Possible causes:"
      ':$$: 'Text "    Missing ("
      ':<>: 'ShowType (BaseCase e)
      ':<>: 'Text ") constraint"
      ':$$: 'Text "    Missing Generic instance"
    )
  , Alternative (IfM y Weighted Proxy)
  ) => GBCS f z y e where
  gbcs = error "Type error"

class GBaseCaseSearch a z y e where
  gBaseCaseSearch :: prox y -> proxy '(z, e) -> IfM y Gen Proxy a

instance (Generic a, GBCS (Rep a) z y e, IsMaybe y)
  => GBaseCaseSearch a z y e where
  gBaseCaseSearch y z = ifMmap y
    (\(Weighted (Just (g, n))) -> choose (0, n-1) >>= fmap to . g)
    (\Proxy -> Proxy)
    (gbcs y z)
