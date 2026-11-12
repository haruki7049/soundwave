# soundwave

みんなで同じ音を聴くラジオ。アップロードされた音声はサーバーで混ぜ合わされ、時間とともに音量が下がって最後には消える。ブラウザはその混ざった音をストリーミングで再生し、オシロスコープとして描画する。

## 構成

```
server (backend) ──▶ shared ◀── client (frontend)
```

- **backend**(ネイティブ GHC / Scotty)
  - アップロードを受け取り、元ファイルを S3 互換ストレージに、記録を SQLite に保存する
  - ffmpeg で音声をデコードしてミキサーに加える
  - ミキサーは各音声をループ再生しつつ、音量を一定時間(既定 300 秒)で 1 から 0 へ直線的に下げ、消えた音声は取り除く
  - 混ぜた結果を ffmpeg で MP3 にエンコードし、`/stream` に接続している全員へ配信する
  - 起動時に、まだ消え切っていない音声を DB と S3 から復元する
- **frontend**(GHC wasm バックエンド / miso + miso-ui)
  - `/stream` を Web Audio で再生し、`AnalyserNode` の波形を canvas に描く
  - ファイルを選んで `/api/sounds` にアップロードする
- **shared**: API の型(`SoundInfo`)とパス。ネイティブと wasm の両方でビルドされる

## 開発

```sh
nix develop

# frontend: static/frontend.wasm と static/ghc_wasm_jsffi.js を生成する
./scripts/build-frontend.sh

# backend
cabal run backend
```

S3 互換ストレージ(MinIO など)が `S3_ENDPOINT` で動いている必要がある。バケットがなければ起動時に作る。

## 環境変数

| 変数 | 既定値 | 内容 |
|---|---|---|
| `PORT` | `8080` | 待ち受けポート |
| `SOUNDWAVE_DATABASE` | `soundwave.db` | SQLite のファイル |
| `SOUNDWAVE_STATIC_DIR` | `static` | 配信する静的ファイルのディレクトリ |
| `SOUNDWAVE_FADE_SECONDS` | `300` | 音声が消えるまでの秒数 |
| `SOUNDWAVE_MAX_UPLOAD_BYTES` | `52428800` | アップロードの上限 |
| `S3_ENDPOINT` | `http://localhost:9000` | S3 互換ストレージの URL |
| `S3_REGION` | `us-east-1` | |
| `S3_BUCKET` | `soundwave` | |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | `minioadmin` | |

## HTTP

| メソッド | パス | 内容 |
|---|---|---|
| `GET` | `/` | ページ本体 |
| `GET` | `/stream` | 混ざった音の MP3 ストリーム(終わらない) |
| `POST` | `/api/sounds` | `multipart/form-data` の `file` フィールドで音声を追加。`SoundInfo` を JSON で返す |
