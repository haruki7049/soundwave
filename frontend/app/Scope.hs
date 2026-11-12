{-# LANGUAGE BangPatterns #-}

-- | Scope views modelled on Sonic Pi's: each one draws the latest stereo
-- samples from the analysers onto a canvas, once per animation frame.
module Scope
  ( ScopeMode (..)
  , allScopeModes
  , scopeModeLabel
  , Samples (..)
  , drawScope
  ) where

import Control.Monad (forM_)
import Foreign.Ptr (Ptr)
import Foreign.Storable (peekElemOff)

import Js

data ScopeMode
  = ScopeStereo
    -- ^ Left and right waveforms in two lanes
  | ScopeMono
    -- ^ Left and right summed into one waveform
  | ScopeMirrorStereo
    -- ^ Amplitude bars, left upwards and right downwards
  | ScopeLissajous
    -- ^ Left on the x axis against right on the y axis
  | ScopeLevels
    -- ^ Loudness meters per channel
  deriving (Show, Eq, Enum, Bounded)

allScopeModes :: [ScopeMode]
allScopeModes = [minBound .. maxBound]

scopeModeLabel :: ScopeMode -> String
scopeModeLabel = \case
  ScopeStereo -> "Stereo"
  ScopeMono -> "Mono"
  ScopeMirrorStereo -> "Mirror Stereo"
  ScopeLissajous -> "Lissajous"
  ScopeLevels -> "Levels"

-- | The latest frame of samples, one buffer per channel, values in [-1, 1].
data Samples = Samples
  { samplesLength :: Int
  , samplesLeft :: Ptr Float
  , samplesRight :: Ptr Float
  }

leftColor, rightColor, dimColor :: JSVal
leftColor = jsStr "#ec4899"
rightColor = jsStr "#3b82f6"
dimColor = jsStr "rgba(128, 128, 128, 0.15)"

-- | Redraw the canvas for the given mode.
drawScope :: ScopeMode -> JSVal -> JSVal -> Samples -> IO ()
drawScope mode canvas ctx s = do
  fitToDisplaySize canvas
  w <- canvasWidth canvas
  h <- canvasHeight canvas
  -- Keep a fading trace of the previous frames, except for the meters
  fade ctx w h (if mode == ScopeLevels then 1 else 0.35)
  setLineWidth ctx (max 1 (h / 150))
  case mode of
    ScopeStereo -> do
      setStrokeStyle ctx leftColor
      drawWave ctx n left w (h * 0.25) (h * 0.25)
      setStrokeStyle ctx rightColor
      drawWave ctx n right w (h * 0.75) (h * 0.25)
    ScopeMono -> do
      setStrokeToCurrentColor ctx canvas
      drawWave ctx n mono w (h / 2) (h / 2)
    ScopeMirrorStereo -> do
      setStrokeStyle ctx leftColor
      drawBars ctx n left w (h / 2) (h / 2) 1
      setStrokeStyle ctx rightColor
      drawBars ctx n right w (h / 2) (h / 2) (-1)
    ScopeLissajous -> do
      setStrokeToCurrentColor ctx canvas
      drawLissajous ctx s w h
    ScopeLevels -> do
      l <- rms n left
      r <- rms n right
      drawMeter ctx w (h * 0.15) (h * 0.3) leftColor l
      drawMeter ctx w (h * 0.55) (h * 0.3) rightColor r
  where
    n = samplesLength s
    left i = peekElemOff (samplesLeft s) i
    right i = peekElemOff (samplesRight s) i
    mono i = (\l r -> (l + r) / 2) <$> left i <*> right i

-- | Samples covered by pixel column @c@ out of @cols@.
columnRange :: Int -> Int -> Int -> (Int, Int)
columnRange n cols c =
  let from = c * n `div` cols
   in (from, max (from + 1) ((c + 1) * n `div` cols))

-- | Lowest and highest sample in [from, to).
minMax :: (Int -> IO Float) -> (Int, Int) -> IO (Float, Float)
minMax sampleAt (from, to) = go from 1e9 (-1e9)
  where
    go !i !lo !hi
      | i >= to = pure (lo, hi)
      | otherwise = do
          v <- sampleAt i
          go (i + 1) (min lo v) (max hi v)

-- | A waveform squeezed into the canvas width: every pixel column spans the
-- range of the samples it covers, so the whole window stays visible.
drawWave :: JSVal -> Int -> (Int -> IO Float) -> Double -> Double -> Double -> IO ()
drawWave ctx n sampleAt w cy half = do
  let cols = max 1 (floor w)
      y v = cy - realToFrac v * half * 0.9
  beginPath ctx
  forM_ [0 .. cols - 1] $ \c -> do
    (lo, hi) <- minMax sampleAt (columnRange n cols c)
    let x = fromIntegral c + 0.5
    if c == 0 then moveTo ctx x (y hi) else lineTo ctx x (y hi)
    lineTo ctx x (y lo)
  stroke ctx

-- | One bar per pixel column, from the centre line outwards, as long as the
-- peak amplitude in that column. @dir@ is 1 for upwards and -1 for downwards.
drawBars :: JSVal -> Int -> (Int -> IO Float) -> Double -> Double -> Double -> Double -> IO ()
drawBars ctx n sampleAt w cy half dir = do
  let cols = max 1 (floor w)
  beginPath ctx
  forM_ [0 .. cols - 1] $ \c -> do
    (lo, hi) <- minMax sampleAt (columnRange n cols c)
    let peak = realToFrac (max (abs lo) (abs hi))
        x = fromIntegral c + 0.5
    moveTo ctx x cy
    lineTo ctx x (cy - dir * peak * half * 0.95)
  stroke ctx

-- | Left against right in a centred square. A mono signal is a diagonal line,
-- out-of-phase content opens it up.
drawLissajous :: JSVal -> Samples -> Double -> Double -> IO ()
drawLissajous ctx s w h = do
  let n = samplesLength s
      -- At most this many points per frame is plenty for a smooth figure
      step = max 1 (n `div` 2048)
      radius = min w h / 2 * 0.9
      point i = do
        l <- peekElemOff (samplesLeft s) i
        r <- peekElemOff (samplesRight s) i
        pure (w / 2 + realToFrac l * radius, h / 2 - realToFrac r * radius)
  beginPath ctx
  forM_ (zip [0 :: Int ..] [0, step .. n - 1]) $ \(k, i) -> do
    (x, y) <- point i
    if k == 0 then moveTo ctx x y else lineTo ctx x y
  stroke ctx

-- | Root mean square of a channel.
rms :: Int -> (Int -> IO Float) -> IO Double
rms n sampleAt = go 0 0
  where
    go !i !acc
      | i >= n = pure (sqrt (acc / fromIntegral (max 1 n)))
      | otherwise = do
          v <- realToFrac <$> sampleAt i
          go (i + 1) (acc + v * v)

-- | A segmented horizontal meter. The level is shown in decibels from -60 to 0.
drawMeter :: JSVal -> Double -> Double -> Double -> JSVal -> Double -> IO ()
drawMeter ctx w top height color level = do
  let segments = 32 :: Int
      segW = w / fromIntegral segments
      gap = max 1 (segW * 0.15)
      db = 20 * logBase 10 (max 1e-6 level)
      lit = max 0 (min 1 ((db + 60) / 60))
  forM_ [0 .. segments - 1] $ \i -> do
    let on = (fromIntegral i + 0.5) / fromIntegral segments < lit
    setFillStyle ctx (if on then color else dimColor)
    fillRect ctx (fromIntegral i * segW) top (segW - gap) height
