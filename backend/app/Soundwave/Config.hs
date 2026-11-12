-- | Runtime configuration, read from environment variables.
module Soundwave.Config
  ( Config (..)
  , S3Config (..)
  , loadConfig
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { cfgPort :: Int
  , cfgDatabase :: FilePath
    -- ^ SQLite database file
  , cfgStaticDir :: FilePath
    -- ^ Directory served under @/static@ (index.html, wasm, js, css)
  , cfgFadeSeconds :: Int
    -- ^ Seconds it takes for an uploaded sound to fade from full volume to silence
  , cfgMaxUploadBytes :: Int
  , cfgS3 :: S3Config
  }

data S3Config = S3Config
  { s3Endpoint :: String
    -- ^ e.g. @http://localhost:9000@ for a local S3 compatible server
  , s3Region :: Text
  , s3Bucket :: Text
  , s3AccessKey :: Text
  , s3SecretKey :: Text
  }

-- | Read the configuration. Every variable has a default suited for local development.
loadConfig :: IO Config
loadConfig = do
  port <- readEnv "PORT" 8080
  db <- textEnv "SOUNDWAVE_DATABASE" "soundwave.db"
  staticDir <- textEnv "SOUNDWAVE_STATIC_DIR" "static"
  fade <- readEnv "SOUNDWAVE_FADE_SECONDS" 300
  maxUpload <- readEnv "SOUNDWAVE_MAX_UPLOAD_BYTES" (50 * 1024 * 1024)
  endpoint <- textEnv "S3_ENDPOINT" "http://localhost:9000"
  region <- textEnv "S3_REGION" "us-east-1"
  bucket <- textEnv "S3_BUCKET" "soundwave"
  accessKey <- textEnv "S3_ACCESS_KEY" "minioadmin"
  secretKey <- textEnv "S3_SECRET_KEY" "minioadmin"
  pure
    Config
      { cfgPort = port
      , cfgDatabase = db
      , cfgStaticDir = staticDir
      , cfgFadeSeconds = max 1 fade
      , cfgMaxUploadBytes = maxUpload
      , cfgS3 =
          S3Config
            { s3Endpoint = endpoint
            , s3Region = T.pack region
            , s3Bucket = T.pack bucket
            , s3AccessKey = T.pack accessKey
            , s3SecretKey = T.pack secretKey
            }
      }
  where
    textEnv :: String -> String -> IO String
    textEnv name def = fromMaybe def <$> lookupEnv name

    readEnv :: Read a => String -> a -> IO a
    readEnv name def = fromMaybe def . (>>= readMaybe) <$> lookupEnv name
