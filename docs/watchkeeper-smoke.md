# Watchkeeper local smoke container

This module adds an opt-in, single-container smoke test of the public
Watchkeeper app. It pins upstream commit
`7e31ce4aeafca041f25b8262f6d76ba6fbd7966c` and builds its Dockerfile from the
Nix-fetched source with Docker build networking disabled. The local image tag
includes that revision. No image is published to a registry.

This PR only prepares the configuration. The generated Compose Nix bot commit
must be present before merging, and the merged change must then go through the
normal reviewed Electricpeak Nix deployment before the systemd unit exists on
the host. No service was activated by preparing this PR.

The container stays stopped unless an operator starts its systemd unit. Its
service is excluded from the generated Compose root target and has no boot
dependency. On first start, systemd builds the image if missing and creates
four random credentials under `/var/lib/watchkeeper-smoke/secrets`. The
credential initializer preserves existing files on restart. The files are
owned by UID 1000, mode `0400`; the containing secrets directory is root-only.
The app runs as UID 1000/GID 2000 with a read-only root, all capabilities
dropped, `no-new-privileges`, a small `/tmp`, and a separate broker-socket
tmpfs. Persistent data is limited to `/var/lib/watchkeeper-smoke/state`.

The app publishes `127.0.0.1:8765` on its own named, non-internal Docker
bridge, separate from Electricpeak's shared `electricpeak` bridge. The app has
no SMTP configuration or reviewer worker. Delivery uses
Watchkeeper's local file sink with a fixed `.invalid` recipient. The bridge is
not an egress firewall, so this smoke setup must not receive real account data
or credentials.

## Start and inspect

Start the container manually. The first start may take time while Docker builds
the pinned image.

```sh
sudo systemctl start docker-watchkeeper-smoke.service
systemctl status docker-watchkeeper-smoke.service
docker inspect --format '{{.State.Health.Status}}' watchkeeper-smoke
curl -fsS http://127.0.0.1:8765/readyz
```

Retrieve the generated UI username and password from a private terminal when
needed. Keep them out of shell history, tickets, and logs:

```sh
sudo cat /var/lib/watchkeeper-smoke/secrets/ui-username
sudo cat /var/lib/watchkeeper-smoke/secrets/ui-password
```

On a workstation with SSH access, open a tunnel using the operator's normal
SSH host alias in place of `electricpeak-host`:

```sh
ssh -N -L 8765:127.0.0.1:8765 electricpeak-host
```

Then open `http://127.0.0.1:8765` and sign in with the generated credentials.
The app requires Basic authentication. A request without credentials to
`/api/state` should return `401`.

## Seed and exercise the app

The helper uses the checked-in public two-thread fixture, assigns current UTC
timestamps and a fresh cursor, submits it through the authenticated intake
endpoint, and creates one controlled proposal from the returned evidence
revisions. It signs into the UI, performs one CSRF-protected delivery into the
local file sink, and prints readiness, auth, intake, proposal, and capture
counts. It does not read conversation accounts or contact an email server.

```sh
sudo /etc/electricpeak/watchkeeper-smoke/seed-demo.sh
sudo find /var/lib/watchkeeper-smoke/state/email -maxdepth 1 -type f -name '*.eml' -print
```

The seeded `garden-guide` project should appear in the browser. Re-running the
helper creates another synthetic intake cursor, refreshing source liveness.
Fixture message IDs and revisions stay the same, so the repeat does not create
new evidence or revise an existing assessment. User lifecycle choices remain
authoritative and can make the helper's eligibility assertion fail. If that
happens, restore, reopen, or unsnooze the project in the UI before rerunning
the smoke flow. The credentials are read privately by the helper and are not
printed.

## Stop, backup, and rollback

Stop the app and wait for its graceful three-minute shutdown before copying
state:

```sh
sudo systemctl stop docker-watchkeeper-smoke.service
```

Back up the complete state directory as private data while the service is
stopped. It contains the database, privacy journal, and captured synthetic
emails. Preserve the latest privacy journal when restoring an older database;
rolling the journal backward can restore deleted content. The local credential
files are outside the state directory and should be protected separately.

To roll back the app image, restore a previously built revision-specific image
and update both the compose image tag and module pin together. Confirm that the
older app supports the current database schema before starting it. Watchkeeper
does not support rolling back to a binary from before the privacy-journal
schema. External mail cannot be recalled, though this smoke configuration
doesn't send external email.

This is a server smoke test only. It does not configure Envoy, host firewall
rules, private DNS names, production account collection, a reviewer, or SMTP.
