-- | SQLite bookkeeping of uploaded sounds.
module Soundwave.Db
  ( Db
  , SoundRow (..)
  , openDb
  , insertSound
  , soundsSince
  ) where

import Control.Concurrent.MVar
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.SQLite.Simple

-- | A connection guarded by a lock, since request handlers run concurrently.
newtype Db = Db (MVar Connection)

data SoundRow = SoundRow
  { rowId :: Text
  , rowObjectKey :: Text
    -- ^ Key of the original file in object storage
  , rowName :: Text
  , rowContentType :: Text
  , rowUploadedAt :: UTCTime
  }

instance FromRow SoundRow where
  fromRow = SoundRow <$> field <*> field <*> field <*> field <*> field

instance ToRow SoundRow where
  toRow (SoundRow a b c d e) = toRow (a, b, c, d, e)

-- | Open (or create) the database and its schema.
openDb :: FilePath -> IO Db
openDb path = do
  conn <- open path
  execute_
    conn
    "CREATE TABLE IF NOT EXISTS sounds (\
    \  id TEXT PRIMARY KEY,\
    \  object_key TEXT NOT NULL,\
    \  original_name TEXT NOT NULL,\
    \  content_type TEXT NOT NULL,\
    \  uploaded_at TEXT NOT NULL\
    \)"
  Db <$> newMVar conn

insertSound :: Db -> SoundRow -> IO ()
insertSound (Db lock) row =
  withMVar lock $ \conn ->
    execute
      conn
      "INSERT INTO sounds (id, object_key, original_name, content_type, uploaded_at) VALUES (?, ?, ?, ?, ?)"
      row

-- | Sounds uploaded at or after the given time, oldest first.
soundsSince :: Db -> UTCTime -> IO [SoundRow]
soundsSince (Db lock) since =
  withMVar lock $ \conn ->
    query
      conn
      "SELECT id, object_key, original_name, content_type, uploaded_at FROM sounds WHERE uploaded_at >= ? ORDER BY uploaded_at"
      (Only since)
