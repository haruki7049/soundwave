{
  description = "soundwave: a shared radio that mixes uploaded sounds";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # GHC WASM backend toolchain (wasm32-wasi-ghc, wasm32-wasi-cabal, ...)
    ghc-wasm-meta.url = "gitlab:haskell-wasm/ghc-wasm-meta?host=gitlab.haskell.org";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, inputs', ... }:
        let
          hp = pkgs.haskell.packages.ghc914;
        in
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              # Native toolchain (used for the backend)
              hp.ghc
              pkgs.cabal-install

              # WASM toolchain (used for the frontend)
              inputs'.ghc-wasm-meta.packages.default

              # post-link.mjs of the wasm toolchain runs on Node.js
              pkgs.nodejs

              # The backend shells out to ffmpeg for decoding uploads
              # and for encoding the MP3 stream
              pkgs.ffmpeg
            ];

            buildInputs = [
              pkgs.zlib
            ];
          };
        };
    };
}
