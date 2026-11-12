{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (object, (.=))
import qualified Data.ByteString.Lazy as BL
import Network.HTTP.Types.Status (status404)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Web.Scotty

import Miso.Html.Render (toHtml)
import Shared.Types (ServerStatus (..), initialModel)
import Shared.View (appView, pageLayout)

main :: IO ()
main = do
  envPort <- lookupEnv "PORT"
  let port = maybe 8080 id (envPort >>= readMaybe)

  putStrLn $ "Starting Scotty backend server on http://localhost:" ++ show port ++ " ..."
  scotty port $ do
    -- SSR endpoint: Render Miso View to HTML
    get "/" $ do
      setHeader "Content-Type" "text/html; charset=utf-8"
      raw $ toHtml $ pageLayout (appView initialModel)

    -- Static assets
    get "/static/:file" $ do
      filename <- pathParam "file"
      file $ "static/" ++ filename

    -- REST API endpoint: Service status
    get "/api/status" $ do
      json $
        ServerStatus
          { service = "scotty-backend"
          , result = "ok"
          }

    -- REST API endpoint: Initial counter data
    get "/api/counter" $ do
      json $ object [ "counter" .= (0 :: Int) ]

    -- 404 handler
    notFound $ do
      status status404
      json $ object [ "error" .= ("Route not found" :: String) ]
