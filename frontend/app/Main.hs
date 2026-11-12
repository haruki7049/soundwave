{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Exception (SomeException, try)
import Miso
import Miso.Html.Element as H hiding (button_)
import Miso.Html.Event as E
import Miso.Html.Property as P
import Miso.String (MisoString, ms)
import Miso.UI.Button (ButtonProps (..), button_, defaultButtonProps)
import Miso.UI.Card (CardProps (..), card_, defaultCardProps)
import Miso.UI.Types (Size (Small), Variant (Outline, Primary, Secondary))

import Player (Player, newPlayer, setScopeMode, startListening, stopListening, uploadSelectedFile)
import Scope (ScopeMode (..), allScopeModes, scopeModeLabel)

#ifdef WASM
foreign export javascript "hs_start" main :: IO ()
#endif

data UploadState
  = UploadIdle
  | Uploading
  | UploadDone
  | UploadFailed MisoString
  deriving (Show, Eq)

data Model = Model
  { listening :: Bool
  , playbackError :: Maybe MisoString
  , uploadState :: UploadState
  , scopeMode :: ScopeMode
  }
  deriving (Show, Eq)

data Action
  = Listen
  | ListenFailed MisoString
  | Stop
  | UploadSelected
  | UploadFinished (Maybe MisoString)
    -- ^ 'Nothing' on success, otherwise the error message
  | SetScopeMode ScopeMode
  | NoOp
  deriving (Show, Eq)

initialModel :: Model
initialModel =
  Model
    { listening = False
    , playbackError = Nothing
    , uploadState = UploadIdle
    , scopeMode = ScopeStereo
    }

-- | DOM id of the oscilloscope canvas.
scopeId :: String
scopeId = "scope"

-- | DOM id of the file input.
fileInputId :: String
fileInputId = "sound-file"

main :: IO ()
main = do
  player <- newPlayer (scopeMode initialModel)
  startApp defaultEvents (component initialModel (updateModel player) appView)

updateModel :: Player -> Action -> Effect context props Model Action
updateModel player = \case
  Listen -> do
    modify $ \m -> m {listening = True, playbackError = Nothing}
    io $ do
      result <- try (startListening player scopeId)
      pure $ case result of
        Left (e :: SomeException) -> ListenFailed (ms (show e))
        Right () -> NoOp
  ListenFailed err ->
    modify $ \m -> m {listening = False, playbackError = Just err}
  Stop -> do
    modify $ \m -> m {listening = False}
    io_ (stopListening player)
  UploadSelected -> do
    modify $ \m -> m {uploadState = Uploading}
    io $ UploadFinished . fmap ms <$> uploadSelectedFile fileInputId
  UploadFinished result ->
    modify $ \m -> m {uploadState = maybe UploadDone UploadFailed result}
  SetScopeMode mode -> do
    modify $ \m -> m {scopeMode = mode}
    io_ (setScopeMode player mode)
  NoOp ->
    pure ()

appView :: Model -> View context props Model Action
appView m =
  div_
    [class_ "container mx-auto p-6 max-w-2xl"]
    [ card_
        defaultCardProps
          { cardTitle = Just (h2_ [class_ "text-2xl font-bold"] [text_ ["soundwave"]])
          , cardDescription =
              Just
                ( p_
                    [class_ "text-sm text-muted-foreground"]
                    [text_ ["アップロードされた音声が混ざり合い、時間とともに消えていくラジオ"]]
                )
          , cardClasses = ["shadow-lg", "rounded-xl", "border", "p-4"]
          }
        [ div_
            [class_ "space-y-6 my-4"]
            [ -- The Player draws into this canvas; its CSS color is the line color
              canvas_
                [ id_ (ms scopeId)
                , class_ "block w-full h-48 rounded-lg border text-primary"
                ]
                []
            , -- Scope view switcher, one button per mode
              div_
                [class_ "flex flex-wrap items-center gap-2"]
                (map scopeButton allScopeModes)
            , div_
                [class_ "flex items-center gap-3"]
                ( listenButton
                    : maybe [] (\err -> [p_ [class_ "text-sm text-destructive"] [text_ [err]]]) (playbackError m)
                )
            , div_
                [class_ "flex items-center gap-3"]
                [ input_
                    [ id_ (ms fileInputId)
                    , type_ "file"
                    , accept_ "audio/*"
                    , class_ "input"
                    ]
                , button_
                    defaultButtonProps
                      { buttonVariant = Secondary
                      , buttonDisabled = uploadState m == Uploading
                      , buttonAttrs = [onClick UploadSelected]
                      }
                    [text_ ["アップロード"]]
                ]
            , uploadStatus (uploadState m)
            ]
        ]
    ]
  where
    scopeButton mode =
      button_
        defaultButtonProps
          { buttonVariant = if scopeMode m == mode then Primary else Outline
          , buttonSize = Small
          , buttonAttrs = [onClick (SetScopeMode mode)]
          }
        [text_ [ms (scopeModeLabel mode)]]

    listenButton
      | listening m =
          button_
            defaultButtonProps {buttonVariant = Outline, buttonAttrs = [onClick Stop]}
            [text_ ["停止"]]
      | otherwise =
          button_
            defaultButtonProps {buttonVariant = Primary, buttonAttrs = [onClick Listen]}
            [text_ ["聴く"]]

    uploadStatus = \case
      UploadIdle -> text_ [""]
      Uploading -> p_ [class_ "text-sm text-muted-foreground"] [text_ ["アップロード中…"]]
      UploadDone -> p_ [class_ "text-sm text-muted-foreground"] [text_ ["ミックスに追加された"]]
      UploadFailed err -> p_ [class_ "text-sm text-destructive"] [text_ [err]]
