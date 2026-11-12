#!/usr/bin/env bash
# Build the miso frontend with the GHC wasm backend and put the artifacts
# into static/, where the backend serves them.
set -euo pipefail

cd "$(dirname "$0")/.."

project=(--project-file=cabal-wasm.project)

wasm32-wasi-cabal "${project[@]}" build frontend
wasm=$(wasm32-wasi-cabal "${project[@]}" list-bin frontend | tail -n 1)

# Generate the JS glue for the `foreign import javascript` declarations
"$(wasm32-wasi-ghc --print-libdir)/post-link.mjs" --input "$wasm" --output static/ghc_wasm_jsffi.js
cp "$wasm" static/frontend.wasm

echo "frontend built into static/"
