-- | The station: drives the mixer in real time, encodes the mix to MP3
-- with an ffmpeg child process, and broadcasts the MP3 bytes to every listener.
module Soundwave.Station
  ( Station
  , newStation
  , runStation
  , subscribe
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race_)
import Control.Concurrent.STM
import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Control.Monad (forever, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import GHC.Clock (getMonotonicTime)
import System.IO (Handle, hFlush, hPutStrLn, stderr)
import System.Process.Typed

import Soundwave.Audio (channels, float32Builder, sampleRate)
import Soundwave.Mixer (Mixer, renderBlock)

-- | Broadcast channel of encoded MP3 chunks.
newtype Station = Station (TChan BS.ByteString)

newStation :: IO Station
newStation = Station <$> newBroadcastTChanIO

-- | Start listening. Every chunk encoded from now on is delivered to the
-- returned channel.
subscribe :: Station -> IO (TChan BS.ByteString)
subscribe (Station chan) = atomically (dupTChan chan)

-- | Run forever. If the encoder dies it is restarted after a second;
-- the mixer clock keeps its position across restarts.
runStation :: Mixer -> Station -> IO ()
runStation mixer (Station chan) = forever $ do
  result <- try $ withProcessTerm encoder $ \p ->
    race_ (pumpPcm mixer (getStdin p)) (pumpMp3 (getStdout p) chan)
  case result of
    Left (e :: SomeException)
      | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
      | otherwise -> hPutStrLn stderr ("encoder failed: " <> show e)
    Right () -> hPutStrLn stderr "encoder exited"
  threadDelay 1000000

-- | ffmpeg reading raw float PCM on stdin and writing MP3 on stdout.
encoder :: ProcessConfig Handle Handle ()
encoder =
  setStdin createPipe $
    setStdout createPipe $
      proc
        "ffmpeg"
        [ "-hide_banner"
        , "-loglevel", "warning"
        , "-f", "f32le"
        , "-ar", show sampleRate
        , "-ac", show channels
        , "-i", "pipe:0"
        , "-c:a", "libmp3lame"
        , "-b:a", "128k"
        , "-f", "mp3"
        , "-flush_packets", "1"
        , "pipe:1"
        ]

-- | Frames rendered per block (50 ms).
blockFrames :: Int
blockFrames = sampleRate `quot` 20

-- | How far ahead of real time the mixer may render, in seconds.
-- Absorbs scheduling hiccups (e.g. GC pauses) without audible gaps.
leadSeconds :: Double
leadSeconds = 0.25

-- | Render the mix in real time and feed it to the encoder.
pumpPcm :: Mixer -> Handle -> IO ()
pumpPcm mixer h = do
  t0 <- getMonotonicTime
  let loop rendered = do
        now <- getMonotonicTime
        let ahead = fromIntegral rendered / fromIntegral sampleRate - (now - t0)
        if ahead > leadSeconds
          then do
            threadDelay (ceiling ((ahead - leadSeconds) * 1000000))
            loop rendered
          else do
            block <- renderBlock mixer blockFrames
            BB.hPutBuilder h (float32Builder block)
            hFlush h
            loop (rendered + blockFrames)
  loop (0 :: Int)

-- | Copy encoded MP3 from the encoder to all listeners until the encoder closes stdout.
pumpMp3 :: Handle -> TChan BS.ByteString -> IO ()
pumpMp3 h chan = do
  chunk <- BS.hGetSome h 4096
  unless (BS.null chunk) $ do
    atomically (writeTChan chan chunk)
    pumpMp3 h chan
