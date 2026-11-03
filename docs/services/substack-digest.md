# Substack Digest deployment

The application implementation, container packaging, offline fixtures, and
[application documentation](https://github.com/junr03/electricpeak-services/tree/main/services/substack-digest)
live in `electricpeak-services`. Electricpeak consumes its published image by
digest; it no longer builds the application on the server.

The service remains disabled by default. Provision the existing 1Password
references and explicitly enable `services.substackDigest.enable` in private
configuration before delivery. The existing timer, retry behavior, non-root
user, read-only root, capabilities, mounts, secret references and Home Manager
configuration mirroring are preserved.

- Schedule: `services.substackDigest.calendar`.
- Public example configuration: `containers/config/substack-digest/config.json`.
- Runtime state: `/var/lib/substack-digest`.
- Credentials: see [secret configuration](../secrets.md) and the application setup guide.

See [service updates](../services.md) for updating the image and source pins.
CI pulls the exact configured image anonymously and validates an offline sample
PDF under the same runtime restrictions, without accessing either real account.
