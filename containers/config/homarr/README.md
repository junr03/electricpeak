# Homarr configuration

The Homarr container is declared in
[`containers/source/media/docker-compose.yml`](../../source/media/docker-compose.yml).
The deployment environment is supplied by the private `private-config`
submodule at `private-config/homarr/environment`.

Homarr's current releases do not use YAML for dashboard configuration. Boards,
apps, integrations, users, and settings are stored in the SQLite database at
`/appdata/db/db.sqlite`. That directory is persisted in the host's container
appdata, so the dashboard survives container updates and NixOS rebuilds.

The first deployment requires Homarr's normal browser onboarding flow. The
encryption key is generated once by the NixOS service before the first start
and stored in 1Password; it is intentionally not checked into either Git
repository.
For repeatable dashboard changes, use Homarr's API or export/import backup
feature after onboarding rather than editing the SQLite file directly.
