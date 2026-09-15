# Electricpeak NixOS configuration

Reusable NixOS and Home Manager modules for a server running containers and a
photo backup workflow. Deployment-specific configuration remains private;
passwords, API keys, and tokens are supplied by GitHub environments or
1Password at runtime.

## Public checks

```sh
nix flake check --no-build
nix develop .#rust --command cargo test --manifest-path rust/Cargo.toml --workspace --locked
python3 scripts/check-public-boundary.py --history
nix develop .#public --command gitleaks git --redact --no-banner .
```

Install the repository's pre-push protection once in each clone:

```sh
./scripts/install-public-hooks.sh
```

The hook rejects private topology, hardware and Home Assistant identifiers,
production hostnames, credential-shaped files, and detected secrets. Put those
changes in the private `junr03/electricpeak-sensitive` repository instead.

`electricpeak-public` is an evaluation-only example. Never activate it on a
production machine. The production target exists only after the private
configuration has been assembled at `private-config/`.

## Production configuration

After all GitHub-hosted checks pass, a push to protected `main` checks out the
tip of `junr03/electricpeak-sensitive` at `private-config/`, builds the exact
assembled source on the server, and activates that build. The private directory
is ignored and is never committed to this repository. The production
`electricpeak` flake target is available only when that configuration exists.
Use a path flake so Nix includes the separately assembled private directory:

```sh
nix flake check --no-build path:.
nixos-rebuild build --flake path:.#electricpeak
```

Pull-request jobs run only on GitHub-hosted runners and never declare the
`production` environment, check out the private repository, or receive
deployment credentials. Only the main-only deploy job can use that environment.
Manual runs default to build-only; select `activate` to perform a manual switch.

Configure these as environment secrets on `production`, not as repository
secrets:

- `PAT_ELECTRICPEAK`: fine-grained token restricted to read-only Contents access
  on `junr03/electricpeak-sensitive`.
- `SERVER_USER`: the server account allowed to perform the bounded deployment.
- `SSH_PRIVATE_KEY`: that account's private deployment key.
- `SERVER_SSH_KNOWN_HOSTS`: a pinned `known_hosts` entry for the server; do not
  generate it with `ssh-keyscan` during CI.
- `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET`: Tailscale OAuth credentials allowed
  to create a tagged ephemeral CI node.
- `TS_SERVER_HOST`: the server's Tailscale hostname or address.

The environment must permit deployments only from `main`. Runtime application
secrets remain in 1Password and are never copied into GitHub.

## Layout

- `configuration.nix`, `modules/`, and `users/`: NixOS and Home Manager modules.
- `containers/source/`: Compose YAML and generated Nix modules.
- `containers/config/`: public configuration examples and file-mirroring helpers.
- `rust/` and `contracts/`: host tooling and the Raw Backup API contract.

Edit Compose YAML, then generate the Nix modules with
`./containers/generate-docker-modules.sh`. Do not hand-edit generated files.
For local generation and checks, use the pinned flake dependencies.
