{
  description = "Minimal Scotty web application";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
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
        { pkgs, ... }:
        let
          hp = pkgs.haskell.packages.ghc914;
        in
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              hp.ghc
              pkgs.cabal-install
            ];

            buildInputs = [
              pkgs.zlib
            ];
          };
        };
    };
}
