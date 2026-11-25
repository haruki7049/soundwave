{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The HTTP contract between the backend and the frontend.
module Shared.Api
  ( SoundInfo (..)
  , uploadPath
  , uploadField
  , streamPath
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | A sound that has been uploaded and added to the mix.
data SoundInfo = SoundInfo
  { soundId :: Text
  , soundName :: Text
    -- ^ Original file name given by the uploader
  , soundUploadedAt :: UTCTime
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | @POST@ a @multipart/form-data@ body here to add a sound to the mix.
-- Responds with a 'SoundInfo' as JSON.
uploadPath :: Text
uploadPath = "/api/sounds"

-- | Name of the multipart field that carries the audio file.
uploadField :: Text
uploadField = "file"

-- | @GET@ this to receive the live mix as an endless MP3 stream.
streamPath :: Text
streamPath = "/stream"
