# LazyLibrarian download pipeline

The container network and mounts use these paths:

| Flow | LazyLibrarian path | Service destination |
| --- | --- | --- |
| Torrent downloads | /data/torrents | qBittorrent's /data (/mnt/data/torrents on the host) |
| qBittorrent books category | /data/books | qBittorrent's /data/books |
| Processed ebooks | /data/incoming/ebooks | copied to Calibre's /autoadd, imported into /library, and sent to Kindle through Gmail API |
| Processed audiobooks | /data/library/audiobooks | Audiobookshelf's /audiobooks |

Calibre owns metadata.db; LazyLibrarian must not write to it directly while
Calibre is running. The calibre-autoadd mount lets Calibre import ebooks and
maintain the database itself.

## Configure the live instance

Create the five lazylibrarian-* fields, the Kindle mailbox, From, and
destination fields, and the GAM7 service-account attachment in the electricpeak/nixos
1Password item as documented in [secrets.md](secrets.md). Deploy the NixOS
change, then restart the secret service to apply a rotation:

    sudo systemctl restart opnix-secrets.service

The lazylibrarian-init container reads runtime-only secrets and idempotently
configures LazyLibrarian before it starts. It registers Goodreads as an ebook
and audiobook wishlist, searches through Prowlarr's native MyAnonamouse
Torznab endpoint, sends results to qBittorrent's books category, hands ebooks
to Calibre Auto Add, and places M4B, MP3, and M4A audiobooks in Audiobookshelf's
library.

LazyLibrarian's built-in Custom download hook invokes the maintained GAM7 CLI
for newly processed EPUB and PDF ebooks. GAM7 sends the attachment through
Gmail's API. Audiobook events are ignored by the hook, and existing library
items are not sent automatically. Attachments over 20,000,000 bytes are
skipped.

Use Config → Providers → Test to test MyAnonamouse and Config →
Downloaders → Test to verify qBittorrent after deployment.

## Google Workspace and Amazon setup

Create a dedicated Google Cloud service account, enable the Gmail API for its
project, and enable domain-wide delegation. Follow GAM7's
[installation](https://github.com/GAM-team/GAM/wiki/How-to-Install-GAM7) and
[authorization](https://github.com/GAM-team/GAM/wiki/Authorization) guidance
to make a limited service-account credential. Select only Gmail API - Send
Messages for the service account. In the Workspace Admin console, authorize
the service account's numeric client ID with this sole OAuth scope:

    https://www.googleapis.com/auth/gmail.send

Store GAM7's resulting limited oauth2service.json as the
kindle-gam-oauth2service.json attachment in 1Password. Set
kindle-mailbox-email to the active Workspace user mailbox that the service
account impersonates. Set kindle-from-email to the visible From address, which
may be a Google Group configured and verified as a Gmail Send mail as address
on that mailbox. Set kindle-to-email to the Kindle's Send to Kindle email
address, and add the visible From address to Amazon's Approved Personal
Document Email List.

Domain-wide delegation is scoped across the Workspace domain: the service
account can impersonate any user in that domain, but with gmail.send it can
send mail only and cannot read or modify mail. No SMTP credentials, SMTP relay
IP allowlist, Amazon password, or Amazon API token are used.
