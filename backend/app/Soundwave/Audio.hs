-- | Audio format of the mix, and decoding uploads into raw samples with ffmpeg.
module Soundwave.Audio
  ( sampleRate
  , channels
  , Samples
  , decodeFile
  , float32Builder
  ) where

import Data.Bits (shiftL, (.|.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.Int (Int16)
import qualified Data.Vector.Storable as VS
import Data.Word (Word16)
import System.Process.Typed (nullStream, proc, readProcessStdout_, setStdin)

-- | Sample rate of the whole pipeline, in frames per second.
sampleRate :: Int
sampleRate = 44100

-- | Number of interleaved channels (stereo).
channels :: Int
channels = 2

-- | Interleaved signed 16-bit samples. Stored as 16-bit rather than
-- 'Float' to halve the memory held by every sound in the mix.
type Samples = VS.Vector Int16

-- | Decode any audio file ffmpeg understands into 'Samples' at the mix format.
--
-- Only the first @maxSeconds@ are kept: a sound has faded out completely
-- after that long, so anything later would never be heard.
--
-- Throws if ffmpeg cannot decode the file (e.g. it is not audio).
decodeFile :: Int -> FilePath -> IO Samples
decodeFile maxSeconds path = do
  out <-
    readProcessStdout_ $
      setStdin nullStream $
        proc
          "ffmpeg"
          [ "-nostdin"
          , "-hide_banner"
          , "-loglevel", "error"
          , "-i", path
          , "-t", show maxSeconds
          , "-vn"
          , "-f", "s16le"
          , "-acodec", "pcm_s16le"
          , "-ac", show channels
          , "-ar", show sampleRate
          , "pipe:1"
          ]
  pure $! fromLittleEndian16 (BL.toStrict out)

-- | Reinterpret little-endian 16-bit PCM bytes as samples.
--
-- Copies byte by byte so that it does not depend on the alignment of the
-- 'BS.ByteString' buffer or on the host endianness.
fromLittleEndian16 :: BS.ByteString -> Samples
fromLittleEndian16 bytes = VS.generate (BS.length bytes `quot` 2) sampleAt
  where
    sampleAt i =
      let lo = fromIntegral (BS.index bytes (2 * i)) :: Word16
          hi = fromIntegral (BS.index bytes (2 * i + 1)) :: Word16
       in fromIntegral (lo .|. (hi `shiftL` 8))

-- | Serialize mixed samples as little-endian 32-bit floats,
-- the raw format fed to the encoder.
float32Builder :: VS.Vector Float -> BB.Builder
float32Builder = VS.foldr (\x acc -> BB.floatLE x <> acc) mempty
