# Secrets and private configuration

This repository is intended to be safe to publish. Do not commit resolved
passwords, API keys, OAuth tokens, private keys, service-account material, or
other credentials.

## Private deployment configuration

Deployment-specific configuration lives in a separate private repository. The
private deployment controller checks out reviewed public and private commit
SHAs and places the private tree at `private-config/`. This directory is
ignored by Git. There is no private submodule in the public repository.

Edit and review private deployment files in their own repository. Select the
new private commit through the private deployment workflow. Use a `path:`
flake when evaluating the assembled tree; the production target is absent
from a checkout without private configuration.

The private repository is authoritative for Envoy configuration, Home Assistant
configuration, templates and automations, and deployment settings. Legacy
1Password copies are retained for compatibility with the provisioning module;
editing those copies with `onepassword-config-edit` does not update the private
files mounted in production. Use the private repository's normal review and
deployment process for these non-secret settings.

## Secret handling

Runtime credentials are provisioned by the NixOS secret module from the
configured secret manager. Keep secret references and provisioning logic in
the module, but never replace references with their resolved values.

### 1Password storage rules

1Password custom fields are single-line values. The module uses fields only for
scalar values and uses `kind = "file"` for payloads that are files, such as
YAML, dotenv, and authorized-keys content. File references resolve ordinary
1Password item attachments, not custom fields.

The `electricpeak / nixos` item must contain these attachments with these exact
names:

| Attachment | Used for |
| --- | --- |
| `cloudflare-dns-environment.env` | Cloudflare DNS environment file |
| `deployment.nix` | Deployment configuration edited by `onepassword-config-edit deployment` |
| `envoy-config.yaml` | Envoy configuration |
| `foodlog-google-drive-token.json` | MacroFactor export Google Drive OAuth token |
| `gluetun-environment.txt` | WireGuard private-key file |
| `github-actions-authorized-keys.txt` | GitHub Actions SSH authorized keys |
| `home-assistant-automations.yaml` | Home Assistant automations |
| `home-assistant-templates.yaml` | Home Assistant templates |
| `homarr-environment.env` | Homarr environment file |
| `junr03-authorized-keys.txt` | `junr03` SSH authorized keys |

The remaining references are scalar fields and must not contain newlines:

```text
homarr-secret-encryption-key
internxt-email
internxt-password
lazylibrarian-goodreads-rss-url
lazylibrarian-qbittorrent-pass
lazylibrarian-qbittorrent-user
lazylibrarian-torznab-api-key
lazylibrarian-torznab-url
foodlog-ghcr-token
foodlog-ghcr-username
foodlog-google-drive-folder-id
foodlog-cronometer-password
foodlog-cronometer-username
vdirsyncer-google-client-id
vdirsyncer-google-client-secret
vdirsyncer-icloud-app-password
vdirsyncer-icloud-username
zerotier-network-cidr
zerotier-network-id
```

The `foodlog-sync` container consumes the `foodlog-google-drive-token.json`
attachment and the `foodlog-google-drive-folder-id`,
`foodlog-cronometer-username`, and `foodlog-cronometer-password` fields. The
NixOS secret module materializes these values under
`/run/onepassword-secrets`, mounts them read-only into the container, and
restarts `docker-foodlog-sync` when they change. The
`foodlog-ghcr-username` and `foodlog-ghcr-token` fields are used only by the
root-owned `foodlog-sync-ghcr-login.service` to authenticate Docker before the
private image is pulled.

For example, add an attachment with the CLI using a file assignment:

```bash
op item edit nixos --vault electricpeak \
  'envoy-config\.yaml[file]=/path/to/envoy-config.yaml'
```

The MouseHole host and origin settings are non-secret and are supplied by
the private deployment configuration. There is no `mousehole-environment` 1Password field.

The public repository starts with a fresh, reviewed root commit. Historical
Git objects and production workflow logs remain in the private controller
repository; never push its branches or tags here.
