# Electricpeak agent guidance

This repository is the NixOS and Home Manager configuration for the
`electricpeak` home server. Keep changes small, reproducible, and consistent
with the existing Nix modules.

## Container definitions

- Edit the source Docker Compose YAML files under
  `containers/source/<group>/docker-compose.yml`.
- Do not hand-edit generated `docker-compose.nix` files. Run
  `./containers/generate-docker-modules.sh` locally when useful, but for PRs let
  the `compose2nix` GitHub Actions job generate and commit the Nix files.
- When adding a container group, add its generated module to the imports in
  `configuration.nix` after generation.
- Preserve existing networking, volume, restart, and security patterns. In
  particular, do not remove host networking from services that need local
  discovery or Bluetooth without understanding the impact.

## Nix and configuration changes

- Keep flake inputs pinned. Change `flake.nix` and use `nix flake update` when
  updating dependencies; do not edit `flake.lock` by hand.
- Keep secrets out of source files. Add non-secret `op://` references to
  `modules/onepassword-secrets/default.nix`; never put resolved values or
  service-account tokens in Nix expressions, Compose files, or the repository.
- Follow existing Home Manager file-mirroring and `onChange` patterns when
  changing service configuration under `containers/config`.
- Preserve firewall restrictions and overlay-network scoping when adding
  ports or services.

## Validation

Use these checks before opening a PR when applicable:

```bash
nix flake check --no-build
sudo nixos-rebuild build --flake .#electricpeak
```

The PR workflow also validates Home Assistant YAML, regenerates Compose Nix
modules, and builds the configuration on the server. A deployment occurs only
from `main`.

## GitHub operations

- Use the connected `@github` connector for repository, branch, issue, and pull
  request operations. Treat it as the default GitHub interface for this repo.
