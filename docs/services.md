# Consuming Electricpeak services

[electricpeak-services](https://github.com/junr03/electricpeak-services) owns
Raw Backup's web application, Rust collector, photo workflow implementation,
Substack Digest's Rust service and browser/PDF packaging, and the status page
collector and static page, with contracts, application tests, and package/image release workflows.
It also packages OpenDashboards and its production login and credential-storage
adapters; this repository only configures deployment.

Electricpeak owns NixOS and Home Manager configuration, systemd units, timers,
device and mount handling, firewall/proxy rules, secret references, Compose
files, and host configuration helpers. The photo workflow package factory takes
host paths and a Nix-built rename-picture dependency; it never takes secret
values. Program code is installed from the locked input through the Nix store.

The web and status containers use digest-pinned GHCR images and retain the existing
read-only status mount, reconciliation mount, network, and restart policy.
There is no application source bind mount from `/etc/nixos`.

## Updating services

1. Choose a services commit with passing package, image, and anonymous pull checks.
2. Update the services revision in `flake.nix`, then run
   `nix flake update electricpeak-services`. Never edit the lock file manually.
3. Set all application images in `containers/source/utilities/docker-compose.yml`
   to their published digests for that same source commit.
4. Run `nix flake check --no-build`,
   `bash .github/scripts/verify-service-images.sh` (Docker and Poppler required),
   and the applicable NixOS build.
5. Open a PR. The existing Compose generation job commits generated Nix modules;
   do not hand-edit them. Wait for that generated commit and its follow-up checks
   to pass before merging. An earlier green PR run validates regenerated files
   but does not guarantee they have been committed; main rejects stale generated
   modules before deployment. Deployment occurs only after merging to main.

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

## Status page

The collector package and page image come from electricpeak-services
(`services/status`). Here, `containers/source/utilities/status/collector.nix`
runs the collector every 30 seconds as a root oneshot (it needs the ZeroTier auth
token and the Docker socket) with `ProtectSystem=strict`, writing
`/var/lib/electricpeak-status/status.json`. The `status` container in the
utilities Compose file serves the page and mounts that directory read-only.
Tailscale and ZeroTier CLIs are only added to the collector's `PATH` when those
services are enabled; otherwise the check reports "not installed".

Serving the page at a public hostname needs a DNS record and an Envoy route and
certificate in `junr03/electricpeak-sensitive` that forward to `status:8080` on
the `electricpeak` Docker network. The hostname must not appear in this
repository.

## OpenDashboards

The utilities Compose source runs the owned OpenDashboards runtime, a network-isolated
credential initializer, and PostgreSQL 17 for application state on an internal network.
The transactions/analytics PostgreSQL container remains separate, with its own volume
and read-only dashboard account. Only the app joins `electricpeak` for Envoy. Neither
app nor database publishes a host port.

The pinned `electricpeak-services` image packages the merged OpenDashboards fork.
Model requests go directly to the configured OpenAI-compatible server. Dashboard
programs/versions and chat history are stored in app PostgreSQL; generated scripts
execute in QuickJS inside the app container. Thesys/OpenUI Cloud is no longer used.

`services.opendashboards.enable` defaults to false. The private Nix configuration
sets the external `origin`. Model and inference settings live in
`containers/source/utilities/docker-compose.yml`: `LLM_BASE_URL` selects the endpoint,
and a YAML anchor shares `qwen3:8b` between `LLM_MODEL` and `OLLAMA_INITIAL_MODELS`.
`OLLAMA_CONTEXT_LENGTH=32768` and `OLLAMA_NUM_PARALLEL=1` configure serving.

The digest-pinned inference image wraps the official Ollama CLI. Its entrypoint
starts Ollama, waits for its API, and downloads only missing configured models.
Health becomes ready after provisioning. Failed downloads stop the container.
The app entrypoint waits for PostgreSQL and its selected models before migrations
and startup. These behaviors work with Compose and NixOS; no host model-download
unit or Nix inference options remain.

Ollama uses the dedicated `opendashboards-inference` network with no host ports,
Envoy route or access to either database network. Its `opendashboards-models` volume
persists weights. The initial download can take time. Inference uses the CPU;
no GPU devices or drivers are configured. Nix handles host state permissions,
service enablement, the private external origin, and compatibility flags omitted
by compose2nix; container settings and readiness belong to Compose and the images.

Configure and validate model serving capacity for the host; the image fixture does
not establish a real model's quality, memory needs or throughput.

The private Envoy route continues forwarding to `opendashboards:3000`, preserving
streaming timeouts and network restrictions. Startup waits for credentials and
PostgreSQL readiness, applies additive migrations, and uses a read-only root filesystem
with the existing tmpfs mounts. The Thesys secret mount and OpNix declaration are removed.

Init retains `database-password`, `admin-password` and `encryption-key` in
`/var/lib/opendashboards/state`, adding only a missing `session-secret`. Files have
mode 0600. Sign in at `/login` using the existing admin password (no username field):
`sudo cat /var/lib/opendashboards/state/admin-password`. Signed sessions expire after
12 hours. Existing data ownership and legacy encrypted credentials are preserved.

Back up `opendashboards-postgres` and the state directory, with a separate encryption-key
backup. Changing the database-password file does not rotate an existing database role.
An older image cannot read newly encrypted credentials, dashboard programs or chat
history. Legacy Cloud dashboards/history require explicit archive/import using the
fork's migration guide; this rollout does not automatically migrate hosted content.

The image gate anonymously pulls the exact pinned digest and runs disposable database
checks for password login, session forgery rejection, app pages, additive migrations,
restart retention, invalid private rules and absent inference configuration. Images
release independently from the locked Nix host packages; each carries its source
repository and commit labels and runs its service-specific smoke check.

### OpenDashboards runtime settings

The published OpenDashboards image reads its private-source authorization file
at startup. Configure `OPENDASHBOARDS_PRIVATE_DESTINATIONS_FILE` and the read-only
mount in `containers/source/utilities/docker-compose.yml`; changing rules needs
a container restart, without rebuilding the application.

Before enabling or upgrading this service, provision the `opendashboards-private-destinations.json` attachment on the `nixos` item
in the `electricpeak` 1Password vault. OpNix supplies the attachment through
`opendashboardsPrivateDestinations`, owned by the app's host user with mode 0400,
and restarts the consuming container when it changes. Store production rules in
1Password. `[]` authorizes no private sources; missing or invalid configured
files prevent startup. The public configuration keeps the service disabled by
default. Existing persistent authentication/encryption state is retained.

The file is an array of the fork's existing private-destination settings, each
with `host`, `port` and `addresses` fields. The private deployment instructions
contain the production configuration to store in 1Password.

Use exact hosts and ports and narrow address bounds for the deployment network.
The existing guarded connectors still require TLS and reject metadata targets.
The analytics source remains separate from the application's metadata database.
Use `onepassword-config-edit opendashboards-private-destinations` for later edits,
then refresh OpNix with `sudo systemctl restart opnix-secrets.service`.
