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
- This is a public repository. Put production hostnames, private IP addresses,
  hardware/filesystem identifiers, Home Assistant entity or device IDs, and
  other deployment-specific values in `junr03/electricpeak-sensitive`.
- Never commit a `private-config` tree or submodule. The reviewed main-only
  deployment job may assemble `electricpeak-sensitive` into that ignored path.
- Pull-request jobs must run on GitHub-hosted runners and must not declare the
  `production` environment, receive production credentials, check out private
  configuration, or connect to the private network or server.
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
python3 scripts/check-public-boundary.py --history
nix develop .#public --command gitleaks git --redact --no-banner .
```

The public PR workflow also validates example Home Assistant YAML and generated
Compose Nix modules. After those checks pass, pushes to protected `main` deploy
the assembled public and private configuration through the `production`
environment.

## GitHub operations

- Use the connected `@github` connector for repository, branch, issue, and pull
  request operations. Treat it as the default GitHub interface for this repo.
