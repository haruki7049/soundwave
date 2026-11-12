{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Concurrent.Async (link, withAsync)
import Control.Concurrent.STM (atomically, readTChan)
import Control.Exception (SomeException, try)
import Control.Monad (forM_, forever)
import Data.Aeson (object, (.=))
import qualified Data.ByteString.Builder as BB
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (addUTCTime, diffUTCTime, getCurrentTime)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import Network.HTTP.Types.Status (badRequest400)
import Network.Wai.Middleware.Static (addBase, noDots, staticPolicy, (>->))
import Network.Wai.Parse (FileInfo (..), defaultParseRequestBodyOptions, setMaxRequestFileSize)
import System.FilePath ((</>))
import System.IO (hClose, hPutStrLn, stderr)
import System.IO.Temp (withSystemTempFile)
import System.Process.Typed (ExitCodeException)
import Web.Scotty

import Shared.Api (SoundInfo (..), streamPath, uploadField, uploadPath)
import Soundwave.Audio (decodeFile, sampleRate)
import Soundwave.Config
import Soundwave.Db
import Soundwave.Mixer (Mixer, addVoice, newMixer)
import Soundwave.Station (newStation, runStation, subscribe)
import Soundwave.Storage (Storage, getFile, openStorage, putFile)

main :: IO ()
main = do
  cfg <- loadConfig
  db <- openDb (cfgDatabase cfg)
  storage <- openStorage (cfgS3 cfg)
  mixer <- newMixer (cfgFadeSeconds cfg * sampleRate)
  station <- newStation

  withAsync (runStation mixer station) $ \stationThread -> do
    link stationThread
    -- Bring back sounds that were still audible before a restart,
    -- without delaying the server start
    withAsync (restoreRecent cfg db storage mixer) $ \_ -> do
      putStrLn $ "soundwave listening on http://localhost:" <> show (cfgPort cfg)
      scotty (cfgPort cfg) $ do
        middleware $ staticPolicy (noDots >-> addBase (cfgStaticDir cfg))

        get "/" $ file (cfgStaticDir cfg </> "index.html")

        get (literal (T.unpack streamPath)) $ do
          setHeader "Content-Type" "audio/mpeg"
          setHeader "Cache-Control" "no-cache, no-store"
          chan <- liftIO (subscribe station)
          stream $ \write flush -> forever $ do
            chunk <- atomically (readTChan chan)
            write (BB.byteString chunk)
            flush

        post (literal (T.unpack uploadPath)) $
          filesOpts (setMaxRequestFileSize (fromIntegral (cfgMaxUploadBytes cfg)) defaultParseRequestBodyOptions) $
            \_ uploads -> case lookup uploadField uploads of
              Nothing -> badRequest "missing multipart field \"file\""
              Just upload -> do
                let path = fileContent upload
                decoded <- liftIO $ try (decodeFile (cfgFadeSeconds cfg) path)
                case decoded of
                  Left (_ :: ExitCodeException) -> badRequest "the file could not be decoded as audio"
                  Right samples -> do
                    sid <- liftIO $ UUID.toText <$> nextRandom
                    now <- liftIO getCurrentTime
                    let row =
                          SoundRow
                            { rowId = sid
                            , rowObjectKey = "sounds/" <> sid
                            , rowName = TE.decodeUtf8Lenient (fileName upload)
                            , rowContentType = TE.decodeUtf8Lenient (fileContentType upload)
                            , rowUploadedAt = now
                            }
                    liftIO $ do
                      putFile storage (rowObjectKey row) (Just (rowContentType row)) path
                      insertSound db row
                      addVoice mixer sid 0 samples
                    json
                      SoundInfo
                        { soundId = sid
                        , soundName = rowName row
                        , soundUploadedAt = now
                        }
  where
    badRequest :: Text -> ActionM ()
    badRequest msg = do
      status badRequest400
      json $ object ["error" .= msg]

-- | Re-add every sound that has not fully faded out yet, at its current age.
restoreRecent :: Config -> Db -> Storage -> Mixer -> IO ()
restoreRecent cfg db storage mixer = do
  now <- getCurrentTime
  rows <- soundsSince db (addUTCTime (negate (fromIntegral (cfgFadeSeconds cfg))) now)
  forM_ rows $ \row -> do
    result <- try $ withSystemTempFile "soundwave-restore" $ \tmp h -> do
      hClose h
      getFile storage (rowObjectKey row) tmp
      samples <- decodeFile (cfgFadeSeconds cfg) tmp
      -- Recompute the age after the download so the sound resumes where it should be now
      later <- getCurrentTime
      let ageFrames = floor (realToFrac (diffUTCTime later (rowUploadedAt row)) * fromIntegral sampleRate :: Double)
      addVoice mixer (rowId row) ageFrames samples
    case result of
      Left (e :: SomeException) ->
        hPutStrLn stderr $ "could not restore " <> T.unpack (rowId row) <> ": " <> show e
      Right () -> pure ()
