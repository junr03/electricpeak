# Electricpeak NixOS configuration

Reusable NixOS and Home Manager modules for a server running containers and a
photo backup workflow. Deployment configuration and production CI are private;
passwords, API keys, and tokens are supplied by 1Password at runtime.

## Public checks

```sh
nix flake check --no-build
nix develop .#rust --command cargo test --manifest-path rust/Cargo.toml --workspace --locked
```

`electricpeak-public` is an evaluation-only example. Never activate it on a
production machine. `nixos-rebuild test` activates a configuration for the
current boot; use `build` when you only want validation.

## Production configuration

The private deployment runner checks out an exact public commit and an exact
private configuration commit, placing the latter at `private-config/`. This
directory is ignored and is never committed to this repository. The production
`electricpeak` flake target is available only when that configuration exists.
Use a path flake so Nix includes the separately assembled private directory:

```sh
nix flake check --no-build path:.
nixos-rebuild build --flake path:.#electricpeak
```

Production builds, SSH access, activation, and their logs run in the private
deployment repository. Public CI has no production credentials or private
configuration. Publishing or renaming this repository does not activate NixOS.

## Layout

- `configuration.nix`, `modules/`, and `users/`: NixOS and Home Manager modules.
- `containers/source/`: Compose YAML and generated Nix modules.
- `containers/config/`: public configuration examples and file-mirroring helpers.
- `rust/` and `contracts/`: host tooling and the Raw Backup API contract.

Edit Compose YAML, then generate the Nix modules with
`./containers/generate-docker-modules.sh`. Do not hand-edit generated files.
For local generation and checks, use the pinned flake dependencies.
