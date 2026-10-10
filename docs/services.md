# Consuming Electricpeak services

[electricpeak-services](https://github.com/junr03/electricpeak-services) owns
Raw Backup's web application, Rust collector, photo workflow implementation,
and Substack Digest's Rust service and browser/PDF packaging,
contracts, application tests, and package/image release workflows.

Electricpeak owns NixOS and Home Manager configuration, systemd units, timers,
device and mount handling, firewall/proxy rules, secret references, Compose
files, and host configuration helpers. The photo workflow package factory takes
host paths and a Nix-built rename-picture dependency; it never takes secret
values. Program code is installed from the locked input through the Nix store.

The web container uses a digest-pinned GHCR image and retains the existing
read-only status mount, reconciliation mount, network, and restart policy.
There is no application source bind mount from `/etc/nixos`.

## Updating services

1. Choose a services commit with passing package, image, and anonymous pull checks.
2. Update the services revision in `flake.nix`, then run
   `nix flake update electricpeak-services`. Never edit the lock file manually.
3. Set both application images in `containers/source/utilities/docker-compose.yml`
   to their published digests for that same source commit.
4. Run `nix flake check --no-build`,
   `bash .github/scripts/verify-service-images.sh` (Docker and Poppler required),
   and the applicable NixOS build.
5. Open a PR. The existing Compose generation job commits generated Nix modules;
   do not hand-edit them. Deployment occurs only after merging to main.

The integration gate actually pulls images with an empty Docker credential
configuration, checks their source/revision labels against the locked input,
and runs each upstream image smoke test against temporary fixture data. Substack
Digest renders and validates an offline PDF with no network or account access. Missing,
private, incorrectly pinned, mismatched, or unhealthy images fail the gate.
Main deployment depends on this gate; PR checks never access private configuration
or the production server. Source and image
publication do not deploy the server.

Merge the services initialization PR before this repository's extraction PR.
Keep deployed source commits and image digests available for generation rollback.
A rollback does not revert mutable application data.
