{-# LANGUAGE InterruptibleFFI #-}
{-# LANGUAGE MultilineStrings #-}

-- | Browser side of the radio: playing the live stream through Web Audio,
-- drawing it as an oscilloscope on a canvas, and uploading files.
--
-- The JavaScript snippets are kept to single browser API calls; the
-- playback state and the drawing loop are written in Haskell.
module Player
  ( Player
  , newPlayer
  , startListening
  , stopListening
  , uploadSelectedFile
  ) where

import Control.Monad (forM_)
import Data.IORef
import qualified Data.Text as T
import GHC.Wasm.Prim (JSString (..), JSVal, fromJSString, toJSString)

import Shared.Api (streamPath, uploadField, uploadPath)

-- | Web Audio graph, created on the first click because browsers only
-- allow audio to start from a user gesture.
data Graph = Graph
  { graphContext :: JSVal
  , graphAudio :: JSVal
    -- ^ @<audio>@ element streaming the mix
  , graphAnalyser :: JSVal
  , graphBuffer :: JSVal
    -- ^ @Float32Array@ the analyser writes the waveform into
  , graphBufferLength :: Int
  }

newtype Player = Player (IORef (Maybe Graph))

newPlayer :: IO Player
newPlayer = Player <$> newIORef Nothing

-- | Number of samples shown on the oscilloscope per frame.
analyserSize :: Int
analyserSize = 2048

-- | Start (or restart) playing the live stream and drawing it on the canvas
-- with the given element id.
startListening :: Player -> String -> IO ()
startListening player canvasId = do
  graph <- ensureGraph player canvasId
  _ <- js_await =<< js_resume (graphContext graph)
  -- Reassigning the source reconnects, so playback starts at the live edge
  js_setSrc (graphAudio graph) (jsStr (T.unpack streamPath))
  _ <- js_await =<< js_play (graphAudio graph)
  pure ()

stopListening :: Player -> IO ()
stopListening (Player ref) =
  readIORef ref >>= mapM_ (js_stopAudio . graphAudio)

ensureGraph :: Player -> String -> IO Graph
ensureGraph (Player ref) canvasId =
  readIORef ref >>= \case
    Just graph -> pure graph
    Nothing -> do
      ctx <- js_newAudioContext
      audio <- js_newAudio
      source <- js_createMediaElementSource ctx audio
      analyser <- js_createAnalyser ctx analyserSize
      js_connect source analyser
      js_connect analyser =<< js_destination ctx
      buffer <- js_newFloat32Array analyserSize
      let graph = Graph ctx audio analyser buffer analyserSize
      writeIORef ref (Just graph)
      startDrawing graph canvasId
      pure graph

-- | Redraw the oscilloscope on every animation frame, forever.
-- When nothing is playing the analyser yields silence, i.e. a flat line.
startDrawing :: Graph -> String -> IO ()
startDrawing graph canvasId = do
  canvas <- js_getElementById (jsStr canvasId)
  ctx2d <- js_getContext2d canvas
  callbackRef <- newIORef Nothing
  callback <- js_mkCallback $ do
    drawFrame graph canvas ctx2d
    readIORef callbackRef >>= mapM_ js_requestAnimationFrame
  writeIORef callbackRef (Just callback)
  js_requestAnimationFrame callback

drawFrame :: Graph -> JSVal -> JSVal -> IO ()
drawFrame graph canvas ctx = do
  js_fitToDisplaySize canvas
  w <- js_width canvas
  h <- js_height canvas
  js_getFloatTimeDomainData (graphAnalyser graph) (graphBuffer graph)

  -- One point per horizontal pixel is enough; skip samples beyond that
  let n = graphBufferLength graph
      points = max 2 (min n (floor w))
      step = fromIntegral n / fromIntegral points :: Double
      xAt i = fromIntegral i * w / fromIntegral (points - 1)
      yAt v = h / 2 - v * h / 2 * 0.9

  js_clearRect ctx w h
  js_setStrokeToCurrentColor ctx canvas
  js_setLineWidth ctx 2
  js_beginPath ctx
  forM_ [0 .. points - 1] $ \i -> do
    v <- js_indexFloat32 (graphBuffer graph) (floor (fromIntegral i * step))
    if i == 0
      then js_moveTo ctx (xAt i) (yAt v)
      else js_lineTo ctx (xAt i) (yAt v)
  js_stroke ctx

-- | Upload the file chosen in the @<input type="file">@ with the given id.
-- Returns 'Nothing' on success, or an error message.
uploadSelectedFile :: String -> IO (Maybe String)
uploadSelectedFile inputId = do
  promise <-
    js_uploadSelected
      (jsStr inputId)
      (jsStr (T.unpack uploadField))
      (jsStr (T.unpack uploadPath))
  result <- fromJSString . JSString <$> js_await promise
  pure $ if null result then Nothing else Just result

----------------------------------------------------------------------------
-- Web Audio

foreign import javascript unsafe "return new AudioContext();"
  js_newAudioContext :: IO JSVal

----------------------------------------------------------------------------
-- Promises
--
-- Async work is done by unsafe imports that return a Promise, which is then
-- awaited through the single interruptible import below. This mirrors how
-- miso does it: an interruptible import returning anything other than a
-- JSVal makes GHC 9.14's wasm desugarer panic (stg_messagePromiseJSString).

foreign import javascript interruptible "return await $1;"
  js_await :: JSVal -> IO JSVal

-- | A Haskell string as a JS string value. 'JSString' itself cannot appear
-- in foreign import types on this GHC (no @HsJSString@ in the C stubs), so
-- every import takes and returns plain 'JSVal's and strings are wrapped here.
jsStr :: String -> JSVal
jsStr s = let JSString v = toJSString s in v

----------------------------------------------------------------------------
-- Web Audio (continued)

foreign import javascript unsafe "return $1.resume();"
  js_resume :: JSVal -> IO JSVal

foreign import javascript unsafe "return new Audio();"
  js_newAudio :: IO JSVal

foreign import javascript unsafe "$1.src = $2;"
  js_setSrc :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "return $1.play();"
  js_play :: JSVal -> IO JSVal

-- | Pause and drop the connection, so the server stops sending data.
foreign import javascript unsafe
  """
  $1.pause();
  $1.removeAttribute('src');
  $1.load();
  """
  js_stopAudio :: JSVal -> IO ()

foreign import javascript unsafe "return $1.createMediaElementSource($2);"
  js_createMediaElementSource :: JSVal -> JSVal -> IO JSVal

foreign import javascript unsafe
  """
  const node = $1.createAnalyser();
  node.fftSize = $2;
  return node;
  """
  js_createAnalyser :: JSVal -> Int -> IO JSVal

foreign import javascript unsafe "$1.connect($2);"
  js_connect :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "return $1.destination;"
  js_destination :: JSVal -> IO JSVal

foreign import javascript unsafe "return new Float32Array($1);"
  js_newFloat32Array :: Int -> IO JSVal

foreign import javascript unsafe "$1.getFloatTimeDomainData($2);"
  js_getFloatTimeDomainData :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "return $1[$2];"
  js_indexFloat32 :: JSVal -> Int -> IO Double

----------------------------------------------------------------------------
-- Canvas

foreign import javascript unsafe "return document.getElementById($1);"
  js_getElementById :: JSVal -> IO JSVal

foreign import javascript unsafe "return $1.getContext('2d');"
  js_getContext2d :: JSVal -> IO JSVal

-- | Match the drawing buffer to the displayed size, for sharp lines on HiDPI screens.
foreign import javascript unsafe
  """
  const ratio = window.devicePixelRatio || 1;
  const w = Math.round($1.clientWidth * ratio);
  const h = Math.round($1.clientHeight * ratio);
  if ($1.width !== w) $1.width = w;
  if ($1.height !== h) $1.height = h;
  """
  js_fitToDisplaySize :: JSVal -> IO ()

foreign import javascript unsafe "return $1.width;"
  js_width :: JSVal -> IO Double

foreign import javascript unsafe "return $1.height;"
  js_height :: JSVal -> IO Double

foreign import javascript unsafe "$1.clearRect(0, 0, $2, $3);"
  js_clearRect :: JSVal -> Double -> Double -> IO ()

-- | Use the CSS @color@ of the canvas, so the line follows the theme.
foreign import javascript unsafe "$1.strokeStyle = getComputedStyle($2).color;"
  js_setStrokeToCurrentColor :: JSVal -> JSVal -> IO ()

foreign import javascript unsafe "$1.lineWidth = $2;"
  js_setLineWidth :: JSVal -> Double -> IO ()

foreign import javascript unsafe "$1.beginPath();"
  js_beginPath :: JSVal -> IO ()

foreign import javascript unsafe "$1.moveTo($2, $3);"
  js_moveTo :: JSVal -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.lineTo($2, $3);"
  js_lineTo :: JSVal -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.stroke();"
  js_stroke :: JSVal -> IO ()

foreign import javascript unsafe "requestAnimationFrame($1);"
  js_requestAnimationFrame :: JSVal -> IO ()

foreign import javascript "wrapper"
  js_mkCallback :: IO () -> IO JSVal

----------------------------------------------------------------------------
-- Upload

-- | POST the selected file as multipart form data.
-- Returns a Promise resolving to an empty string on success, or an error message.
foreign import javascript unsafe
  """
  return (async () => {
  const input = document.getElementById($1);
  const file = input && input.files[0];
  if (!file) return 'no file selected';
  const body = new FormData();
  body.append($2, file);
  const res = await fetch($3, { method: 'POST', body });
  if (!res.ok) return 'upload failed (' + res.status + '): ' + (await res.text());
  input.value = '';
  return '';
  })();
  """
  js_uploadSelected :: JSVal -> JSVal -> JSVal -> IO JSVal
