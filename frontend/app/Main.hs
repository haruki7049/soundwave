{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad.State (modify)
import Miso
import Shared.Types (Action (..), Model (..), initialModel)
import Shared.View (appView)

#ifdef WASM
foreign export javascript "hs_start" main :: IO ()
#endif

main :: IO ()
main = startApp defaultEvents app
  where
    app :: App Model Action
    app = component initialModel updateModel appView

    updateModel :: Action -> Effect context props Model Action
    updateModel = \case
      Increment ->
        modify $ \m -> m { counter = counter m + 1 }
      Decrement ->
        modify $ \m -> m { counter = counter m - 1 }
      Reset ->
        modify $ \m -> m { counter = 0 }
      SetUsername name ->
        modify $ \m -> m { username = name }
      FetchStatus ->
        -- In full browser runtime, can issue HTTP fetch to /api/status
        pure ()
      ReceiveStatus st ->
        modify $ \m -> m { statusInfo = st }
      NoOp ->
        pure ()
