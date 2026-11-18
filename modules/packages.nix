# Every package installed directly by this repository, in one place.
#
# Entries are `{ name = <package>; }`. Set `unfree = true` to add the package to
# the unfree allowlist automatically. This module is shared by the public and
# production targets, so a package listed here reaches the server. Do not
# install packages from the public-only arm of configuration.nix.
#
# Packages built by a service module for its own use (for example the
# 1Password helpers in modules/onepassword-secrets) stay with that module.
{
  lib,
  pkgs,
  self,
}:
let
  entries = with pkgs; [
    # Development and AI tooling
    { name = self.packages.${pkgs.stdenv.hostPlatform.system}.codex; }
    {
      name = claude-code;
      unfree = true;
    }
    { name = compose2nix; }
    # Financial data tooling (not in nixpkgs, see packages/plaid-cli.nix)
    {
      name = pkgs.callPackage ../packages/plaid-cli.nix { };
      unfree = true;
    }

    # General system utilities
    { name = curl; }
    { name = git; }
    { name = jq; }
    { name = tree; }
  ];
in
{
  system = map (entry: entry.name) entries;
  unfree = map (entry: lib.getName entry.name) (lib.filter (entry: entry.unfree or false) entries);
}
