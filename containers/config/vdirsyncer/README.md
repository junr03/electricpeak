# Google and iCloud contact sync

The `contact-sync` utility runs [vdirsyncer](https://vdirsyncer.pimutils.org/)
every 15 minutes. It syncs one Google Contacts address book with one iCloud
address book in both directions.

The container starts with a safety gate. Scheduled syncs fail before they read
contacts until you finish the steps below and create `/vdirsyncer/enabled`.

## Why vdirsyncer

Vdirsyncer supports direct server-to-server CardDAV sync and has a dedicated
Google Contacts storage for Google's required OAuth flow. Its successor,
pimsync, does not support Google OAuth yet. The container is pinned to the
signed `bleala/vdirsyncer` 2.6.1 image, which contains vdirsyncer 0.20.0.

Google's CardDAV implementation has two known data limits. Contact groups do
not map to vCard categories, and birthdays without a year do not sync reliably.
Export both address books before the first sync and keep those exports.

## 1. Deploy in gated mode

Deploy the NixOS configuration. Confirm that the container is waiting behind
the gate:

```sh
docker logs contact-sync
```

The persistent directory is deployment-specific on the host and
`/vdirsyncer` in the container.

## 2. Back up and choose the first source

Export all Google contacts and all iCloud contacts as vCard files. Store both
exports outside the server.

Choose one address book as the source for the first sync. If both contain
contacts you need, import and deduplicate them in the chosen source first. Then
empty the other address book. Starting with the same people under different
provider IDs creates duplicates. Do not enable the scheduled sync while both
independent address books are populated.

## 3. Store provider credentials in 1Password

In Google Cloud, enable the CardDAV API and create an OAuth client with the
Desktop application type. Record its client ID and client secret.

For iCloud, create an app-specific password for the Apple Account. Record the
Apple Account username and app-specific password.

Store the four values as concealed fields on the `nixos` item in the
`electricpeak` vault:

- `vdirsyncer-google-client-id`
- `vdirsyncer-google-client-secret`
- `vdirsyncer-icloud-username`
- `vdirsyncer-icloud-app-password`

OpNix fetches these values into `/run/onepassword-secrets`, and the container
bind-mounts them read-only at the paths used by `config`. The Google OAuth token
remains in private vdirsyncer appdata. Follow [the repository secrets guide](../../../docs/secrets.md)
to bootstrap or refresh the service account; never create credential files in
appdata or commit them.

## 4. Authorize Google and discover collection IDs

Run discovery in one terminal:

```sh
docker exec -it contact-sync vdirsyncer -c /vdirsyncer/config discover google_icloud
```

Open the printed Google authorization URL in your browser. Google redirects the
browser to a temporary `127.0.0.1` URL that cannot load on your computer. Copy
that full redirect URL. While discovery is still running, send the URL to the
OAuth listener inside the container from a second terminal:

```sh
docker exec contact-sync curl -fsS 'PASTE_THE_FULL_REDIRECT_URL_HERE'
```

Discovery prints the Google and iCloud collection IDs. Answer `n` if it asks to
create either placeholder collection. Edit the deployed config and replace
`__GOOGLE_COLLECTION_ID__` and `__ICLOUD_COLLECTION_ID__` with the IDs it
printed:

```sh
sudoedit <deployment-appdata>/vdirsyncer/config
```

Run discovery again. It should find the mapped collection without proposing
new collections.

## 5. Run and verify the first sync

Keep the scheduled gate closed. Run one sync manually:

```sh
docker exec -it contact-sync vdirsyncer -c /vdirsyncer/config sync google_icloud
```

Check both provider interfaces. Confirm the contact count and inspect contacts
with multiple phone numbers, addresses, birthdays, and notes. Restore from the
exports if the result is wrong.

Enable the 15-minute schedule only after the manual result is correct:

```sh
docker exec contact-sync touch /vdirsyncer/enabled
```

To stop all scheduled syncs without stopping the container:

```sh
docker exec contact-sync rm /vdirsyncer/enabled
```

Vdirsyncer stops on a contact changed independently in both providers. Check
`docker logs contact-sync`, resolve the conflict manually, and rerun the sync.
