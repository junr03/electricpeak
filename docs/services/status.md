# Status page

A small public page showing whether the server is reachable and healthy:

- **ZeroTier**: the daemon is online and joined to at least one network that
  reports `OK`.
- **Tailscale**: the backend is `Running` and this node is online in the tailnet.
- **SSH (port 22)**: a connection to sshd is accepted and it sends an `SSH-`
  banner. The probe runs on the host against `127.0.0.1:22`, so it proves sshd
  is serving, not that the firewall exposes it on a given interface.
- **Containers**: every Docker container. Ones that are down, restarting,
  unhealthy, paused, or still starting get full-size cards; healthy ones are
  compact chips. A container that exited cleanly and is not meant to run
  continuously (restart policy `no`, for example the Substack job) shows as idle,
  not as a failure.

The page shows state only. It never publishes addresses, network IDs, versions,
or SSH banners.

## How it works

There is deliberately no privileged web service:

1. `electricpeak-status.timer` runs the `electricpeak-status-collector` oneshot
   on the host every 30 seconds. It runs as root (needed for the ZeroTier auth
   token and the Docker socket) with `ProtectSystem=strict`, and writes
   `/var/lib/electricpeak-status/status.json` atomically.
2. The `status` container in `containers/source/utilities/docker-compose.yml`
   is stock `nginx-unprivileged`. It serves the static page and that one JSON
   file, read-only, with a strict CSP. It has no Docker socket, no host network,
   and no capabilities.
3. The page polls `data/status.json` every 15 seconds. If `generated_at` is
   older than 150 seconds it reports that the data is stale, so a dead collector
   or timer is visible instead of showing an old "all green".

If the whole server is down the page is unreachable, which is itself the
signal. It is not an external monitor.

## Why custom

No maintained project covers this. Uptime Kuma and Gatus probe from outside or
need per-monitor setup and cannot ask the local `tailscaled`, `zerotier-one`,
and Docker daemons whether the node is connected. The collector is a small
Rust, std-only crate (`rust/crates/electricpeak-status`) that wraps the
`tailscale`, `zerotier-cli`, and `docker` CLIs, with parser tests. The web
side reuses nginx.

## Deployment

Merging this change deploys the collector, timer, and container. Serving it at
the public hostname needs a change in the private repository, because the
production hostname must not appear here:

- In `junr03/electricpeak-sensitive`, add a DNS record and an Envoy route and
  certificate for the status hostname that forwards to `status:8080` on the
  `electricpeak` Docker network.
- Optionally, scope that route the same way as the other services.

Tools are only added to the collector's `PATH` when `services.tailscale` or
`services.zerotierone` is enabled; otherwise that check reports "not
installed" and the page shows the overall state as degraded.

## Local preview

```sh
nix develop .#rust --command cargo run --manifest-path rust/Cargo.toml \
  -p electricpeak-status -- --stdout
```

`--stdout` prints the snapshot instead of writing it. Set
`ELECTRICPEAK_STATUS_OUTPUT` and `ELECTRICPEAK_STATUS_SSH_ADDRESS` to override
the output path and the SSH probe address.
