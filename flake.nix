{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowBroken = true;
          };
        };
        packageJson = builtins.fromJSON (builtins.readFile ./package.json);
        packageManager = builtins.elemAt (builtins.split "\\+" packageJson.packageManager) 0;
        pnpm-shim = pkgs.writeShellScriptBin "pnpm" ''
          exec ${pkgs.nodejs-slim}/bin/node ${pkgs.nodejs-slim}/bin/corepack pnpm "$@"
        '';
        devShell = pkgs.mkShell {
          shellHook = ''
            corepack install -g ${packageManager}
          '';
          buildInputs = with pkgs; [
            pnpm-shim
            nodejs-slim
            just
          ];
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShell = devShell;
      }
    );
}
