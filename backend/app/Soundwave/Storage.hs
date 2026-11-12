-- | Object storage for the original uploaded files, on any S3 compatible server.
module Soundwave.Storage
  ( Storage
  , openStorage
  , putFile
  , getFile
  ) where

import Control.Exception (throwIO)
import Control.Monad (unless)
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as T
import Network.Minio

import Soundwave.Config (S3Config (..))

data Storage = Storage
  { storageConn :: ConnectInfo
  , storageBucket :: Bucket
  }

-- | Connect settings for the configured server, creating the bucket if needed.
openStorage :: S3Config -> IO Storage
openStorage cfg = do
  let creds =
        CredentialValue
          (AccessKey (s3AccessKey cfg))
          (fromString (T.unpack (s3SecretKey cfg)))
          Nothing
      conn = setRegion (s3Region cfg) $ setCreds creds $ fromString (s3Endpoint cfg)
      storage = Storage conn (s3Bucket cfg)
  run storage $ do
    exists <- bucketExists (s3Bucket cfg)
    unless exists $ makeBucket (s3Bucket cfg) Nothing
  pure storage

-- | Upload a local file under the given object key.
putFile :: Storage -> Text -> Maybe Text -> FilePath -> IO ()
putFile storage key contentType path =
  run storage $
    fPutObject (storageBucket storage) key path defaultPutObjectOptions {pooContentType = contentType}

-- | Download an object to a local file.
getFile :: Storage -> Text -> FilePath -> IO ()
getFile storage key path =
  run storage $ fGetObject (storageBucket storage) key path defaultGetObjectOptions

run :: Storage -> Minio a -> IO a
run storage action = runMinio (storageConn storage) action >>= either throwIO pure
