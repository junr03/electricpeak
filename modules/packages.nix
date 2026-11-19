# Every package installed directly by this repository, listed alphabetically.
#
# Entries are `{ name = <package>; }`. Set `unfree = true` to allow the package
# automatically. This module is shared by the public and production targets, so
# a package listed here reaches the server. Do not install packages from the
# public-only arm of configuration.nix.
#
# Modules that install or enable an unfree package for their own use add its
# name to `electricpeak.unfreePackages` next to that use, instead of editing
# this file.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  entries = with pkgs; [
    {
      name = claude-code;
      unfree = true;
    }
    { name = self.packages.${pkgs.stdenv.hostPlatform.system}.codex; }
    { name = compose2nix; }
    { name = curl; }
    { name = git; }
    { name = jq; }
    # Not in nixpkgs; see packages/plaid-cli.nix.
    {
      name = pkgs.callPackage ../packages/plaid-cli.nix { };
      unfree = true;
    }
    { name = tree; }
  ];
in
{
  options.electricpeak.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Names of unfree packages that may be built and installed.";
  };

  config = {
    electricpeak.unfreePackages = map (entry: lib.getName entry.name) (
      lib.filter (entry: entry.unfree or false) entries
    );

    nixpkgs.config.allowUnfreePredicate =
      pkg: builtins.elem (lib.getName pkg) config.electricpeak.unfreePackages;

    environment.systemPackages = map (entry: entry.name) entries;
  };
}
