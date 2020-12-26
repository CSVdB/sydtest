{-# LANGUAGE RankNTypes #-}

module Test.Syd.Def.SetupFunc where

import Control.Category as Cat
import Control.Monad.IO.Class

-- | A function that can provide an 'a' given a 'b'.
--
-- You can think of this as a potentially-resource-aware version of 'b -> IO a'.
newtype SetupFunc b a = SetupFunc
  { unSetupFunc :: forall r. (a -> IO r) -> (b -> IO r)
  }

instance Functor (SetupFunc c) where
  fmap f (SetupFunc provideA) = SetupFunc $ \takeB c ->
    let takeA = \a -> takeB $ f a
     in provideA takeA c

instance Applicative (SetupFunc c) where
  pure a = SetupFunc $ \aFunc _ -> aFunc a
  (SetupFunc provideF) <*> (SetupFunc provideA) = SetupFunc $ \takeB c ->
    provideF
      ( \f ->
          provideA
            ( \a ->
                takeB (f a)
            )
            c
      )
      c

instance Monad (SetupFunc c) where
  (SetupFunc provideA) >>= m = SetupFunc $ \takeB c ->
    provideA
      ( \a ->
          let (SetupFunc provideB) = m a
           in provideB (\b -> takeB b) c
      )
      c

instance MonadIO (SetupFunc c) where
  liftIO ioFunc = SetupFunc $ \takeA _ -> do
    ioFunc >>= takeA

instance Category SetupFunc where
  id = SetupFunc Prelude.id
  (.) = composeSetupFunc

-- | Turn a simple provider function into a 'SetupFunc'.
--
-- This works together nicely with most supplier functions.
-- Some examples:
--
-- * [Network.Wai.Handler.Warp.testWithApplication](https://hackage.haskell.org/package/warp-3.3.13/docs/Network-Wai-Handler-Warp.html#v:testWithApplication)
-- * [Path.IO.withSystemTempDir](https://hackage.haskell.org/package/path-io-1.6.2/docs/Path-IO.html#v:withSystemTempDir)
makeSimpleSetupFunc :: (forall r. (a -> IO r) -> IO r) -> SetupFunc () a
makeSimpleSetupFunc provideA = SetupFunc $ \takeA () -> provideA $ \a -> takeA a

-- | Use a 'SetupFunc ()' as a simple provider function.
--
-- This is the opposite of the 'makeSimpleSetupFunc' function
useSimpleSetupFunc :: SetupFunc () a -> (forall r. (a -> IO r) -> IO r)
useSimpleSetupFunc (SetupFunc provideAWithUnit) takeA = provideAWithUnit (\a -> takeA a) ()

-- | Wrap a function that produces a 'SetupFunc' to into a 'SetupFunc'.
--
-- This is useful to combine a given 'SetupFunc b' with other 'SetupFunc ()'s as follows:
--
-- > mySetupFunc :: SetupFunc B A
-- > mySetupFunc = wrapSetupFunc $ \b -> do
-- >   r <- setupSomething
-- >   c <- setupSomethingElse b r
-- >   pure $ somehowCombine c r
-- >
-- > setupSomething :: SetupFunc () R
-- > setupSomething :: B -> R -> SetupFunc () C
-- > somehowCombine :: C -> R -> A
wrapSetupFunc :: (b -> SetupFunc () a) -> SetupFunc b a
wrapSetupFunc bFunc = SetupFunc $ \takeA b ->
  let SetupFunc provideAWithUnit = bFunc b
   in provideAWithUnit (\a -> takeA a) ()

-- | Unwrap a 'SetupFunc' into a function that produces a 'SetupFunc'
--
-- This is the opposite of 'wrapSetupFunc'.
unwrapSetupFunc :: SetupFunc b a -> (b -> SetupFunc () a)
unwrapSetupFunc (SetupFunc provideAWithB) b = SetupFunc $ \takeA () ->
  provideAWithB (\a -> takeA a) b

-- | Compose two setup functions.
--
-- This is basically '(.)' but for 'SetupFunc's
composeSetupFunc :: SetupFunc b a -> SetupFunc c b -> SetupFunc c a
composeSetupFunc (SetupFunc provideAWithB) (SetupFunc provideBWithC) = SetupFunc $ \takeA c ->
  provideBWithC
    ( \b ->
        provideAWithB
          ( \a -> takeA a
          )
          b
    )
    c
