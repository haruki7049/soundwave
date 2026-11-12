{-# LANGUAGE MultilineStrings #-}

-- | Browser side of the radio: playing the live stream through Web Audio,
-- feeding the scope, and uploading files.
module Player
  ( Player
  , newPlayer
  , startListening
  , stopListening
  , setScopeMode
  , uploadSelectedFile
  ) where

import Data.IORef
import qualified Data.Text as T
import Foreign.Marshal.Array (mallocArray)
import Foreign.Ptr (Ptr)

import Js
import Scope (Samples (..), ScopeMode, drawScope)
import Shared.Api (streamPath, uploadField, uploadPath)

-- | Web Audio graph, created on the first click because browsers only
-- allow audio to start from a user gesture.
--
-- > <audio> -> source -> destination
-- >                  \-> splitter -> analyser (left)
-- >                              \-> analyser (right)
data Graph = Graph
  { graphContext :: JSVal
  , graphAudio :: JSVal
    -- ^ @<audio>@ element streaming the mix
  , graphAnalyserLeft :: JSVal
  , graphAnalyserRight :: JSVal
  , graphSamples :: Samples
    -- ^ Buffers in wasm memory that the analysers are copied into every frame
  }

data Player = Player
  { playerGraph :: IORef (Maybe Graph)
  , playerMode :: IORef ScopeMode
  }

newPlayer :: ScopeMode -> IO Player
newPlayer mode = Player <$> newIORef Nothing <*> newIORef mode

setScopeMode :: Player -> ScopeMode -> IO ()
setScopeMode player = writeIORef (playerMode player)

-- | Samples per channel shown per frame. The analyser size must be a power of
-- two; 8192 is about 170 ms at 48 kHz, wide enough that the trace does not
-- jump around from frame to frame.
analyserSize :: Int
analyserSize = 8192

-- | Start (or restart) playing the live stream and drawing it on the canvas
-- with the given element id.
startListening :: Player -> String -> IO ()
startListening player canvasId = do
  graph <- ensureGraph player canvasId
  _ <- await =<< js_resume (graphContext graph)
  -- Reassigning the source reconnects, so playback starts at the live edge
  js_setSrc (graphAudio graph) (jsStr (T.unpack streamPath))
  _ <- await =<< js_play (graphAudio graph)
  pure ()

stopListening :: Player -> IO ()
stopListening player =
  readIORef (playerGraph player) >>= mapM_ (js_stopAudio . graphAudio)

ensureGraph :: Player -> String -> IO Graph
ensureGraph player canvasId =
  readIORef (playerGraph player) >>= \case
    Just graph -> pure graph
    Nothing -> do
      ctx <- js_newAudioContext
      audio <- js_newAudio
      source <- js_createMediaElementSource ctx audio
      js_connect source =<< js_destination ctx

      splitter <- js_createChannelSplitter ctx 2
      js_connect source splitter
      analyserLeft <- js_createAnalyser ctx analyserSize
      analyserRight <- js_createAnalyser ctx analyserSize
      js_connectOutput splitter analyserLeft 0
      js_connectOutput splitter analyserRight 1

      left <- mallocArray analyserSize
      right <- mallocArray analyserSize
      let graph =
            Graph
              { graphContext = ctx
              , graphAudio = audio
              , graphAnalyserLeft = analyserLeft
              , graphAnalyserRight = analyserRight
              , graphSamples = Samples analyserSize left right
              }
      writeIORef (playerGraph player) (Just graph)
      startDrawing player graph canvasId
      pure graph

-- | Redraw the scope on every animation frame, forever.
-- When nothing is playing the analysers yield silence.
startDrawing :: Player -> Graph -> String -> IO ()
startDrawing player graph canvasId = do
  canvas <- getElementById (jsStr canvasId)
  ctx2d <- getContext2d canvas
  callbackRef <- newIORef Nothing
  callback <- mkCallback $ do
    let samples = graphSamples graph
    js_readTimeDomain (graphAnalyserLeft graph) (samplesLeft samples) (samplesLength samples)
    js_readTimeDomain (graphAnalyserRight graph) (samplesRight samples) (samplesLength samples)
    mode <- readIORef (playerMode player)
    drawScope mode canvas ctx2d samples
    readIORef callbackRef >>= mapM_ requestAnimationFrame
  writeIORef callbackRef (Just callback)
  requestAnimationFrame callback

-- | Upload the file chosen in the @<input type="file">@ with the given id.
-- Returns 'Nothing' on success, or an error message.
uploadSelectedFile :: String -> IO (Maybe String)
uploadSelectedFile inputId = do
  promise <-
    js_uploadSelected
      (jsStr inputId)
      (jsStr (T.unpack uploadField))
      (jsStr (T.unpack uploadPath))
  result <- fromJSStr <$> await promise
  pure $ if null result then Nothing else Just result

----------------------------------------------------------------------------
-- Web Audio

foreign import javascript unsafe "return new AudioContext();"
  js_newAudioContext :: IO JSVal

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

foreign import javascript unsafe "return $1.createChannelSplitter($2);"
  js_createChannelSplitter :: JSVal -> Int -> IO JSVal

foreign import javascript unsafe
  """
  const node = $1.createAnalyser();
  node.fftSize = $2;
  return node;
  """
  js_createAnalyser :: JSVal -> Int -> IO JSVal

foreign import javascript unsafe "$1.connect($2);"
  js_connect :: JSVal -> JSVal -> IO ()

-- | Connect one output of a multi-output node (e.g. a channel of a splitter).
foreign import javascript unsafe "$1.connect($2, $3);"
  js_connectOutput :: JSVal -> JSVal -> Int -> IO ()

foreign import javascript unsafe "return $1.destination;"
  js_destination :: JSVal -> IO JSVal

-- | Copy the analyser's current waveform straight into a buffer in wasm
-- memory, so Haskell reads it with 'peekElemOff' instead of one FFI call per
-- sample. The view is created on every call because the memory buffer is
-- replaced whenever the wasm memory grows.
foreign import javascript unsafe
  "$1.getFloatTimeDomainData(new Float32Array(__exports.memory.buffer, $2, $3));"
  js_readTimeDomain :: JSVal -> Ptr Float -> Int -> IO ()

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
