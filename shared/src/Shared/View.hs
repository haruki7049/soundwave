{-# LANGUAGE OverloadedStrings #-}

module Shared.View
  ( appView
  , pageLayout
  ) where

import Miso
import Miso.Html.Element as H hiding (button_)
import Miso.Html.Event as E
import Miso.Html.Property as P
import Miso.String (ms)

import Miso.UI.Badge (BadgeProps (..), badge_, defaultBadgeProps)
import Miso.UI.Button (ButtonProps (..), button_, defaultButtonProps)
import Miso.UI.Card (CardProps (..), card_, defaultCardProps)
import Miso.UI.Types (Size (..), Variant (..))
import Shared.Types (Action (..), Model (..))

-- | Main application view (Virtual DOM)
appView :: Model -> View context props Model Action
appView m =
  div_
    [ class_ "container mx-auto p-6 max-w-2xl" ]
    [ card_ cardConfig [ cardBody m ] ]
  where
    cardConfig =
      defaultCardProps
        { cardTitle = Just (h2_ [ class_ "text-2xl font-bold" ] [ text_ ["Scotty + Miso Fullstack"] ])
        , cardDescription = Just (p_ [ class_ "text-sm text-gray-500" ] [ text_ ["Haskell Backend (Scotty) & Frontend (Miso + Miso.UI)"] ])
        , cardFooter = Just [ footerContent m ]
        , cardClasses = [ "shadow-lg", "rounded-xl", "border", "p-4" ]
        }

    cardBody cur =
      div_
        [ class_ "space-y-6 my-4" ]
        [ -- Counter Section
          div_
            [ class_ "flex items-center space-x-4 p-4 bg-muted/20 rounded-lg border" ]
            [ span_ [ class_ "text-lg font-semibold" ] [ text_ ["Counter: "] ]
            , badge_
                (defaultBadgeProps { badgeVariant = Secondary, badgeRounded = True })
                [ text_ [ ms (show (counter cur)) ] ]
            , div_
                [ class_ "flex space-x-2 ml-auto" ]
                [ button_
                    (defaultButtonProps
                      { buttonVariant = Outline
                      , buttonSize = Small
                      , buttonAttrs = [ onClick Decrement ]
                      })
                    [ text_ ["-1"] ]
                , button_
                    (defaultButtonProps
                      { buttonVariant = Primary
                      , buttonSize = Small
                      , buttonAttrs = [ onClick Increment ]
                      })
                    [ text_ ["+1"] ]
                , button_
                    (defaultButtonProps
                      { buttonVariant = Ghost
                      , buttonSize = Small
                      , buttonAttrs = [ onClick Reset ]
                      })
                    [ text_ ["Reset"] ]
                ]
            ]
        -- Server Status Section
        , div_
            [ class_ "p-4 rounded-lg border bg-card" ]
            [ div_
                [ class_ "flex items-center justify-between mb-2" ]
                [ span_ [ class_ "font-medium" ] [ text_ ["Backend Service"] ]
                , badge_
                    (defaultBadgeProps { badgeVariant = Primary })
                    [ text_ ["Scotty Web Server"] ]
                ]
            , p_
                [ class_ "text-sm text-gray-600" ]
                [ text_ ["SSR rendered via Miso toHtml, dynamic actions handled via Miso."] ]
            ]
        ]

    footerContent _ =
      div_
        [ class_ "flex justify-between items-center w-full text-xs text-muted-foreground pt-2 border-t" ]
        [ span_ [] [ text_ ["Built with miso.ui (Tailwind / BasecoatCSS)"] ]
        , button_
            (defaultButtonProps
              { buttonVariant = Outline
              , buttonSize = Small
              , buttonAttrs = [ onClick FetchStatus ]
              })
            [ text_ ["Refresh Status"] ]
        ]

-- | HTML shell wrapping the view for SSR
pageLayout :: View () () Model Action -> [View () () Model Action]
pageLayout bodyView =
  [ doctype_
  , html_
      [ lang_ "ja", class_ "dark" ]
      [ head_
          []
          [ meta_ [ charset_ "utf-8" ]
          , meta_ [ name_ "viewport", content_ "width=device-width, initial-scale=1" ]
          , H.title_ [] [ text_ ["Scotty + Miso App"] ]
          , link_
              [ rel_ "stylesheet"
              , href_ "https://cdn.jsdelivr.net/npm/basecoat-css@0.3.6/dist/css/basecoat.min.css"
              ]
          , link_
              [ rel_ "stylesheet"
              , href_ "/static/styles.css"
              ]
          , H.script_
              [ src_ "https://cdn.jsdelivr.net/npm/basecoat-css@0.3.6/dist/js/all.min.js"
              ]
              mempty
          ]
      , body_
          [ class_ "min-h-screen bg-background text-foreground flex flex-col justify-center items-center p-4" ]
          [ bodyView ]
      ]
  ]
