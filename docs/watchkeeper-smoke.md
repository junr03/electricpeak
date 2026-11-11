# Watchkeeper smoke container

This is a manually started synthetic app-only smoke test using the published
Watchkeeper image pinned in the utilities Compose file:
`ghcr.io/junr03/project-watchkeeper@sha256:5008834cc10afaf6f795baf7892414627b9fa61739545dee20d3fecc69a5c6cd`.
It runs as UID 1000/GID 2000, drops all capabilities, sets
`no-new-privileges`, uses four private secret-file mounts, and joins the
existing `electricpeak` network. The UI publishes only on
`127.0.0.1:8765`. Email uses the local file sink and fixed `.invalid` sender
and recipient addresses. No real account data or external SMTP is used.

The `compose2nix.settings.autoStart=false` label keeps the service out of the
generated autostart target. Before starting it, provision the state directory
and four random local credentials. The checked-in generic setting is
`DOCKERCONFDIR=/var/lib/electricpeak/appdata`; use the value from the active
Compose `.env` if it differs. The credential files stay outside version
control. The provisioning commands require `openssl` on the host.

```sh
export DOCKERCONFDIR=/var/lib/electricpeak/appdata
: "${DOCKERCONFDIR:?Set this to the path configured in Electricpeak Compose}"
sudo install -d -o 1000 -g 2000 -m 0700 "$DOCKERCONFDIR/watchkeeper/state"
sudo install -d -o root -g root -m 0700 "$DOCKERCONFDIR/watchkeeper/secrets"
for name in intake-token reviewer-token ui-username ui-password; do
  path="$DOCKERCONFDIR/watchkeeper/secrets/$name"
  sudo test ! -e "$path" || { echo "Refusing to replace $path" >&2; exit 1; }
  sudo sh -c 'umask 077; openssl rand -hex 32 > "$1"' sh "$path"
done
sudo sh -c 'chown 1000:2000 "$1"/* && chmod 0400 "$1"/*' sh "$DOCKERCONFDIR/watchkeeper/secrets"
```

Provision these files once and preserve them across restarts. Existing files
are never overwritten by the commands above. A missing, empty, or non-private
credential file makes Watchkeeper reject configuration at startup.
Check that all four files exist and are nonempty before starting:

```sh
for name in intake-token reviewer-token ui-username ui-password; do
  sudo test -s "$DOCKERCONFDIR/watchkeeper/secrets/$name" || exit 1
done
```

The service is available after the PR is merged and the normal reviewed
Electricpeak Nix deployment has completed; preparing this PR does not activate
it. Start the generated systemd unit manually and check readiness and
authentication:

```sh
sudo systemctl start docker-watchkeeper
systemctl status docker-watchkeeper
curl -fsS http://127.0.0.1:8765/readyz
curl -i http://127.0.0.1:8765/api/state  # should return 401
```

Read the UI username and password in a private terminal:

```sh
sudo cat "$DOCKERCONFDIR/watchkeeper/secrets/ui-username"
sudo cat "$DOCKERCONFDIR/watchkeeper/secrets/ui-password"
```

To connect from a workstation, use the operator's SSH host alias in place of
`electricpeak-host`:

```sh
ssh -N -L 8765:127.0.0.1:8765 electricpeak-host
```

Open `http://127.0.0.1:8765` and sign in. This app-only instance starts empty;
no collector or reviewer is enabled. The upstream
[container runtime guide](https://github.com/junr03/project-watchkeeper/blob/d9fdc6be15455e0cb471dcbde5beb189640ba60f/docs/container-runtime.md#synthetic-startup-and-acceptance)
covers a separate synthetic test stack and does not seed this instance.

Stop with `sudo systemctl stop docker-watchkeeper`. The generated unit uses a
180-second Docker stop command and a 210-second systemd timeout. It stops the
container while keeping the persistent state bind mount, credentials, database,
privacy journal, and file-sink output. Back up the complete state directory
while stopped; preserve the latest privacy journal when restoring an older
database.

The compose2nix v0.3.2 converter ignores Compose `read_only`, `tmpfs`, and
`stop_grace_period` fields. This synthetic smoke container therefore has a
writable container layer and no declared tmpfs. Non-root execution, dropped
capabilities, `no-new-privileges`, read-only credential mounts, and the
extended stop window are represented by supported Compose fields or labels.
This is not a production deployment and adds no Envoy route or private
network policy.
