{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Shared.Types
  ( Model (..)
  , Action (..)
  , ServerStatus (..)
  , initialModel
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Miso.String (MisoString)

-- | Server response representation
data ServerStatus = ServerStatus
  { service :: String
  , result :: String
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Application state
data Model = Model
  { counter :: Int
  , statusInfo :: Maybe ServerStatus
  , username :: MisoString
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Initial application state
initialModel :: Model
initialModel =
  Model
    { counter = 0
    , statusInfo = Nothing
    , username = "World"
    }

-- | Frontend action
data Action
  = Increment
  | Decrement
  | Reset
  | SetUsername MisoString
  | FetchStatus
  | ReceiveStatus (Maybe ServerStatus)
  | NoOp
  deriving stock (Show, Eq)
