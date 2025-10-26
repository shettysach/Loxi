{
  description = "odin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        devShells.default = pkgs.mkShell {
          name = "odin";
          nativeBuildInputs = [pkgs.ols pkgs.miniserve pkgs.wabt pkgs.prettierd];
          buildInputs = [pkgs.odin pkgs.lld];
        };
      }
    );
}
