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

The utilities Compose source defines OpenDashboards, a network-isolated
credential initializer, and Postgres 17 on a separate internal Docker network.
Only the app joins `electricpeak` for Envoy. Neither app nor database publishes a
host port. The application image comes from `electricpeak-services` and includes
single-user browser authentication, encrypted connection credentials, and
versioned database migrations. OpenUI Cloud remains hosted by Thesys; generation,
model calls and dashboard/chat storage use its API.

The application container sets `OPENDASHBOARDS_MODEL=google/gemini-3.6-flash-free`
for both the chat agent and dashboard generation, using the existing Thesys API
key. Change that environment value through the normal reviewed deployment process
to select another Gateway model without rebuilding the image. This free route
still consumes Gateway API calls, has usage limits, and may use request data for
training; see [Gateway models](https://www.openui.com/cloud/gateway/models).

`services.opendashboards.enable` defaults to false. Once the API key is
provisioned, the private deployment sets it to true and sets
`services.opendashboards.origin` to the external HTTPS origin. This conditionally
declares `op://electricpeak/nixos/thesys_api_key` in OpNix and starts the app after
secret materialization, credential initialization and PostgreSQL readiness.
The generated systemd units preserve Compose dependency ordering; the deployment
module also waits for database health and supplies the read-only/tmpfs flags that
the pinned Compose generator omits. The private Envoy route forwards to
`opendashboards:3000`, with streaming timeouts disabled and existing network
restrictions unchanged. Production hostnames belong only in the private source.

The first start creates a random login password, database password and encryption
key in `/var/lib/opendashboards/state`, with mode 0600. Login as `admin`; retrieve
the password on the server with
`sudo cat /var/lib/opendashboards/state/admin-password`. No additional 1Password
fields need provisioning. Keep this a single-user installation.

Back up the `opendashboards-postgres` Docker volume together with the state
directory. Losing `encryption-key` makes saved connection credentials unreadable.
Changing `database-password` alone does not update an initialized PostgreSQL role.
To rotate the Thesys key, update its 1Password field and refresh OpNix; its consumer
restart integration restarts the app. Rollback preserves persistent state and
does not reverse migrations or delete hosted artifacts.

The image gate anonymously pulls the pinned image and runs the upstream smoke
test against an isolated PostgreSQL fixture, including login rejection, app and
connections rendering, encrypted storage, migration/credential retention after
restart, and missing-key rejection. It uses a synthetic Thesys key and performs
no billable generation.

### OpenDashboards runtime settings

The published OpenDashboards image reads its private-source authorization file
at startup. Configure `OPENDASHBOARDS_PRIVATE_DESTINATIONS_FILE` and the read-only
mount in `containers/source/utilities/docker-compose.yml`; changing rules needs
a container restart, without rebuilding the application.

Before enabling or upgrading this service, provision the existing Thesys API key
and the `opendashboards-private-destinations.json` attachment on the `nixos` item
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
