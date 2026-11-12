{-# LANGUAGE InterruptibleFFI #-}
{-# LANGUAGE MultilineStrings #-}

-- | Thin bindings to the browser APIs used by the frontend.
--
-- Every snippet is a single browser API call (or a few lines of plumbing);
-- the logic built on top of them lives in Haskell.
--
-- Two restrictions of the GHC 9.14 wasm backend shape these bindings:
--
-- * 'JSString' cannot appear in foreign import types (the C stubs have no
--   @HsJSString@), so strings cross the boundary as 'JSVal' via 'jsStr'.
-- * An interruptible import returning anything but 'JSVal' makes the
--   desugarer panic, so async work returns a Promise that is awaited with
--   'await', the same way miso does it.
module Js
  ( JSVal
  , jsStr
  , fromJSStr
  , await
    -- * DOM
  , getElementById
  , requestAnimationFrame
  , mkCallback
    -- * Canvas
  , getContext2d
  , fitToDisplaySize
  , canvasWidth
  , canvasHeight
  , fade
  , setStrokeStyle
  , setStrokeToCurrentColor
  , setFillStyle
  , setLineWidth
  , beginPath
  , moveTo
  , lineTo
  , stroke
  , fillRect
  ) where

import GHC.Wasm.Prim (JSString (..), JSVal, fromJSString, toJSString)

-- | A Haskell string as a JS string value.
jsStr :: String -> JSVal
jsStr s = let JSString v = toJSString s in v

-- | A JS string value as a Haskell string.
fromJSStr :: JSVal -> String
fromJSStr = fromJSString . JSString

foreign import javascript interruptible "return await $1;"
  await :: JSVal -> IO JSVal

----------------------------------------------------------------------------
-- DOM

foreign import javascript unsafe "return document.getElementById($1);"
  getElementById :: JSVal -> IO JSVal

foreign import javascript unsafe "requestAnimationFrame($1);"
  requestAnimationFrame :: JSVal -> IO ()

foreign import javascript "wrapper"
  mkCallback :: IO () -> IO JSVal

----------------------------------------------------------------------------
-- Canvas

foreign import javascript unsafe "return $1.getContext('2d');"
  getContext2d :: JSVal -> IO JSVal

-- | Match the drawing buffer to the displayed size, for sharp lines on HiDPI screens.
foreign import javascript unsafe
  """
  const ratio = window.devicePixelRatio || 1;
  const w = Math.round($1.clientWidth * ratio);
  const h = Math.round($1.clientHeight * ratio);
  if ($1.width !== w) $1.width = w;
  if ($1.height !== h) $1.height = h;
  """
  fitToDisplaySize :: JSVal -> IO ()

foreign import javascript unsafe "return $1.width;"
  canvasWidth :: JSVal -> IO Double

foreign import javascript unsafe "return $1.height;"
  canvasHeight :: JSVal -> IO Double

-- | Make everything already drawn more transparent by the given amount (0..1).
-- Drawing over a faded frame leaves an afterglow of the previous frames.
foreign import javascript unsafe
  """
  $1.save();
  $1.globalCompositeOperation = 'destination-out';
  $1.fillStyle = 'rgba(0, 0, 0, ' + $4 + ')';
  $1.fillRect(0, 0, $2, $3);
  $1.restore();
  """
  fade :: JSVal -> Double -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.strokeStyle = $2;"
  setStrokeStyle :: JSVal -> JSVal -> IO ()

-- | Use the CSS @color@ of the canvas, so the line follows the theme.
foreign import javascript unsafe "$1.strokeStyle = getComputedStyle($2).color;"
  setStrokeToCurrentColor :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "$1.fillStyle = $2;"
  setFillStyle :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "$1.lineWidth = $2;"
  setLineWidth :: JSVal -> Double -> IO ()

foreign import javascript unsafe "$1.beginPath();"
  beginPath :: JSVal -> IO ()

foreign import javascript unsafe "$1.moveTo($2, $3);"
  moveTo :: JSVal -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.lineTo($2, $3);"
  lineTo :: JSVal -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.stroke();"
  stroke :: JSVal -> IO ()

foreign import javascript unsafe "$1.fillRect($2, $3, $4, $5);"
  fillRect :: JSVal -> Double -> Double -> Double -> Double -> IO ()
