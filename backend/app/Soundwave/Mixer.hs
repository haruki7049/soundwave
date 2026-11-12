-- | The mixer: every uploaded sound loops while its volume falls linearly
-- from 1 to 0 over the fade duration, after which it is dropped.
--
-- Time is measured in frames rendered since the server started, so the
-- mix only advances as fast as 'renderBlock' is called.
module Soundwave.Mixer
  ( Mixer
  , newMixer
  , addVoice
  , renderBlock
  , mixFrames
  , Voice (..)
  ) where

import Control.Concurrent.STM
import qualified Data.Vector.Storable as VS
import Data.Text (Text)

import Soundwave.Audio (Samples, channels)

-- | One sound in the mix.
data Voice = Voice
  { voiceId :: !Text
  , voiceSamples :: !Samples
  , voiceStart :: !Int
    -- ^ Mixer frame at which this voice was at age 0 (full volume, first sample).
    -- May be negative for voices restored after a restart.
  }

data Mixer = Mixer
  { mixerFadeFrames :: !Int
  , mixerVoices :: TVar [Voice]
  , mixerFrame :: TVar Int
    -- ^ Number of frames rendered so far
  }

-- | Create an empty mixer whose voices fade out over the given number of frames.
newMixer :: Int -> IO Mixer
newMixer fadeFrames = Mixer (max 1 fadeFrames) <$> newTVarIO [] <*> newTVarIO 0

-- | Add a sound to the mix.
--
-- The age is how many frames ago the sound entered the mix: 0 for a fresh
-- upload, larger for a sound restored from the database after a restart.
addVoice :: Mixer -> Text -> Int -> Samples -> IO ()
addVoice mixer vid age samples
  | VS.null samples = pure ()
  | otherwise = atomically $ do
      now <- readTVar (mixerFrame mixer)
      modifyTVar' (mixerVoices mixer) (Voice vid samples (now - age) :)

-- | Render the next block of interleaved samples and advance the mixer clock.
-- Voices that have fully faded out are removed.
renderBlock :: Mixer -> Int -> IO (VS.Vector Float)
renderBlock mixer frames = do
  (start, voices) <- atomically $ do
    start <- readTVar (mixerFrame mixer)
    voices <- readTVar (mixerVoices mixer)
    let alive = filter (\v -> start - voiceStart v < mixerFadeFrames mixer) voices
    writeTVar (mixerVoices mixer) alive
    writeTVar (mixerFrame mixer) (start + frames)
    pure (start, alive)
  pure $! mixFrames (mixerFadeFrames mixer) start frames voices

-- | Pure mixing of @frames@ frames starting at mixer frame @start@.
mixFrames :: Int -> Int -> Int -> [Voice] -> VS.Vector Float
mixFrames fadeFrames start frames voices = VS.generate (frames * channels) sampleAt
  where
    sampleAt i =
      let (frame, ch) = i `quotRem` channels
       in softClip (sum (map (voiceSample (start + frame) ch) voices))

    voiceSample t ch v =
      let age = t - voiceStart v
          len = VS.length (voiceSamples v) `quot` channels
       in if age < 0 || age >= fadeFrames || len == 0
            then 0
            else
              let -- Loop the sound for as long as it is audible
                  idx = (age `rem` len) * channels + ch
                  x = fromIntegral (VS.unsafeIndex (voiceSamples v) idx) / 32768
               in gain age * x

    -- Linear fade from 1 at age 0 down to 0 at age fadeFrames
    gain :: Int -> Float
    gain age = 1 - fromIntegral age / fromIntegral fadeFrames

-- | Keep the sum of many voices within [-1, 1] without hard clipping.
softClip :: Float -> Float
softClip = tanh
