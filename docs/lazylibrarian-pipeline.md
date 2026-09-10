# LazyLibrarian download pipeline

The container network and mounts use these paths:

| Flow | LazyLibrarian path | Service destination |
| --- | --- | --- |
| Torrent downloads | `/data/torrents` | qBittorrent's `/data` (`/mnt/data/torrents` on the host) |
| qBittorrent `books` category | `/data/books` | qBittorrent's `/data/books` |
| Processed ebooks | `/data/incoming/ebooks` | copied to Calibre's `/autoadd`, then imported into `/library` |
| Processed audiobooks | `/data/library/audiobooks` | Audiobookshelf's `/audiobooks` |

Calibre owns `metadata.db`; LazyLibrarian must not write to it directly while
Calibre is running. The `calibre-autoadd` mount lets Calibre import ebooks and
maintain the database itself.

## Configure the live instance

Create the five `lazylibrarian-*` fields in the `electricpeak/nixos` 1Password
item as documented in [secrets.md](secrets.md). Deploy the NixOS change, then
restart the secret service to apply a rotation:

```bash
sudo systemctl restart opnix-secrets.service
```

The `lazylibrarian-init` container reads those runtime-only secrets and
idempotently configures LazyLibrarian before it starts. It registers Goodreads
as an ebook-only wishlist, searches through Prowlarr's native MyAnonamouse
Torznab endpoint, sends results to qBittorrent's `books` category, hands ebooks
to Calibre Auto Add, and places audiobooks in Audiobookshelf's library.

Use **Config → Providers → Test** to test MyAnonamouse and **Config →
Downloaders → Test** to verify qBittorrent after deployment.
