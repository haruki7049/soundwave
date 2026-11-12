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

    # Local development services (S3 compatible storage), run with `nix run .#services`
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.process-compose-flake.flakeModule
      ];

      perSystem =
        { pkgs, inputs', ... }:
        let
          hp = pkgs.haskell.packages.ghc914;
        in
        {
          # `nix run .#services` starts the S3 compatible storage the backend expects.
          # The defaults below match the backend's S3_* defaults.
          process-compose."services" = {
            imports = [
              inputs.services-flake.processComposeModules.default
            ];

            services.minio."s3" = {
              enable = true;
              # MinIO itself is no longer in nixpkgs; silo is a community fork of it
              package = pkgs.silo;
              port = 9000;
              accessKey = "minioadmin";
              secretKey = "minioadmin";
              buckets = [ "soundwave" ];
            };
          };

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
