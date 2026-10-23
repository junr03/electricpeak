# Watchkeeper local smoke service

This is an opt-in Electricpeak service that runs the published Watchkeeper app
image with the upstream Compose definition and a small local overlay. It does
not fetch or build the application source on the host. The configuration pins
upstream Compose and the synthetic fixture to revision
`d9fdc6be15455e0cb471dcbde5beb189640ba60f`, and pins the images by digest:

- App: `ghcr.io/junr03/project-watchkeeper@sha256:5008834cc10afaf6f795baf7892414627b9fa61739545dee20d3fecc69a5c6cd`
- Reviewer: `ghcr.io/junr03/project-watchkeeper-reviewer@sha256:d0bbb1246f5539b2c143cc186f43ce53178cc914bced8c01a9a342b7fd27c377`

Only the app service is started. The local overlay removes the upstream demo
credentials, uses generated credential files, binds persistent state to
`/var/lib/watchkeeper-smoke/state`, and replaces the upstream broker volume
with a small socket tmpfs. The upstream read-only root, UID 1000/GID 2000,
capability drop, no-new-privileges setting, and health check remain in effect.
Compose 2.24.4 or newer is required for the overlay's `!reset` and `!override`
tags. The service uses a dedicated non-internal `watchkeeper-smoke` bridge and
publishes only on `127.0.0.1:8765`. The network is separate from Electricpeak's
shared bridge, but it is not an egress firewall.

The app uses Watchkeeper's file email sink and a fixed `.invalid` recipient.
The SMTP sink and reviewer remain unstarted: the systemd unit requests only
`app` with `--no-deps`, and the upstream reviewer profile remains off. Do not
use real account content or credentials in this smoke service.

This PR only prepares the configuration. The generated Compose Nix bot commit
must be present before merging, and the merged change must then go through the
normal reviewed Electricpeak Nix deployment before the systemd unit exists on
the host. Preparing the PR did not activate anything.

## Start and inspect

After that reviewed deployment, start the service manually. The first start
pulls the pinned app image if it is absent and waits for the upstream
readiness health check, with a 180-second health wait.

```sh
sudo systemctl start watchkeeper-smoke.service
systemctl status watchkeeper-smoke.service
docker inspect --format '{{.State.Health.Status}}' watchkeeper-smoke
curl -fsS http://127.0.0.1:8765/readyz
```

The credential initializer creates four random files on first start and
preserves them on subsequent starts. They are owned by UID 1000, mode `0400`,
inside a root-only directory:

```sh
sudo cat /var/lib/watchkeeper-smoke/secrets/ui-username
sudo cat /var/lib/watchkeeper-smoke/secrets/ui-password
```

Keep these values out of shell history, tickets, and logs. To connect from a
workstation, use the operator's normal SSH host alias in place of
`electricpeak-host`:

```sh
ssh -N -L 8765:127.0.0.1:8765 electricpeak-host
```

Open `http://127.0.0.1:8765` and sign in with the generated credentials. Basic
authentication is required; an unauthenticated request to `/api/state` should
return `401`.

## Seed the synthetic project

The installed helper reads the public fixture fetched from the pinned upstream
revision. It refreshes the fixture timestamps, submits authenticated intake,
creates a controlled proposal from current evidence revisions, signs into the
UI, and delivers one digest to the file sink. It also checks readiness,
unauthenticated access, project state, and the captured email count. It does
not read any conversation account or contact an email server.

```sh
sudo /etc/electricpeak/watchkeeper-smoke/seed-demo.sh
sudo find /var/lib/watchkeeper-smoke/state/email -maxdepth 1 -type f -name '*.eml' -print
```

The `garden-guide` project should appear in the browser. Re-running the helper
uses the same fixture message IDs and revisions, so it refreshes source
liveness without replacing stored evidence. User lifecycle choices remain
authoritative and can make the helper's eligibility check fail. Use **Restore**
for an archived project or **Reopen** for a closed or snoozed project before
rerunning the smoke flow.

## Stop, preserve, and roll back

Stop through systemd. Its stop hook runs Compose `down --timeout 180` without
`--volumes`, allowing graceful shutdown while keeping the state bind mount and
generated credentials:

```sh
sudo systemctl stop watchkeeper-smoke.service
```

Back up `/var/lib/watchkeeper-smoke/state` as private data while the service is
stopped. It contains the database, privacy journal, and captured synthetic
emails. Preserve the latest privacy journal when restoring an older database;
rolling the journal backward can restore deleted content. Protect the
credential files separately.

For a rollback, update the app image digest and upstream Compose revision in
the Nix module together, then use the normal reviewed deployment. Confirm that
the selected app image supports the existing database schema. Watchkeeper does
not support rollback to a binary from before the privacy-journal schema. This
file-sink smoke setup sends no external mail.
