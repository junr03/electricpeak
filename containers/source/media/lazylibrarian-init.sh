#!/bin/sh
set -eu

config_file=/config/config.ini

read_secret() {
  secret_file="$1"
  attempts=0
  while [ "$attempts" -lt 30 ]; do
    if [ -s "$secret_file" ]; then
      cat "$secret_file"
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  echo "Missing or empty 1Password secret: $secret_file" >&2
  return 1
}

qbit_user="$(read_secret /run/secrets/lazylibrarian-qbittorrent-user)"
qbit_pass="$(read_secret /run/secrets/lazylibrarian-qbittorrent-pass)"
torznab_url="$(read_secret /run/secrets/lazylibrarian-torznab-url)"
torznab_api_key="$(read_secret /run/secrets/lazylibrarian-torznab-api-key)"
goodreads_rss_url="$(read_secret /run/secrets/lazylibrarian-goodreads-rss-url)"

set_ini() {
  section="$1"
  key="$2"
  value="$3"
  temporary_file="$(mktemp "$config_file.XXXXXX")"
  config_mode="$(stat -c '%a' "$config_file")"

  ELECTRICPEAK_INI_VALUE="$value" awk -v target_section="$section" -v target_key="$key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function target_section_matches(line) {
      return tolower(trim(line)) == tolower("[" target_section "]")
    }
    function target_key_matches(line, pair) {
      split(line, pair, "=")
      return tolower(trim(pair[1])) == tolower(target_key)
    }
    /^\[/ {
      if (in_target && !wrote_key) {
        print target_key " = " ENVIRON["ELECTRICPEAK_INI_VALUE"]
        wrote_key = 1
      }
      in_target = target_section_matches($0)
      if (in_target) found_section = 1
    }
    {
      if (in_target && target_key_matches($0)) {
        if (!wrote_key) {
          print target_key " = " ENVIRON["ELECTRICPEAK_INI_VALUE"]
          wrote_key = 1
        }
        next
      }
      print
    }
    END {
      if (in_target && !wrote_key) print target_key " = " ENVIRON["ELECTRICPEAK_INI_VALUE"]
      if (!found_section) {
        print ""
        print "[" target_section "]"
        print target_key " = " ENVIRON["ELECTRICPEAK_INI_VALUE"]
      }
    }
  ' "$config_file" > "$temporary_file"
  chmod "$config_mode" "$temporary_file"
  mv "$temporary_file" "$config_file"
}

if [ -f "$config_file" ]; then
  if grep -q '^[[:space:]]*http_proxy[[:space:]]*=' "$config_file"; then
    sed -i -E 's/^[[:space:]]*http_proxy[[:space:]]*=.*/http_proxy = True/' "$config_file"
  else
    sed -i '/^\[WEBSERVER\]/a http_proxy = True' "$config_file"
  fi
else
  printf '%s\n' '[WEBSERVER]' 'http_proxy = True' > "$config_file"
fi

set_ini General ebook_dir /data/incoming/ebooks
set_ini General download_dir /data/torrents
set_ini General audio_dir /data/library/audiobooks
set_ini General audio_tab 1
set_ini General imp_autoadd /calibre-autoadd
set_ini General imp_autoadd_copy 1
set_ini General imp_calibredb ''
set_ini General calibre_use_server 0
set_ini TORRENT tor_downloader_qbittorrent 1
set_ini QBITTORRENT qbittorrent_host gluetun
set_ini QBITTORRENT qbittorrent_port 8080
set_ini QBITTORRENT qbittorrent_user "$qbit_user"
set_ini QBITTORRENT qbittorrent_pass "$qbit_pass"
set_ini QBITTORRENT qbittorrent_label books
set_ini QBITTORRENT qbittorrent_dir /data/books
set_ini Torznab_0 dispname MyAnonamouse
set_ini Torznab_0 enabled 1
set_ini Torznab_0 host "$torznab_url"
set_ini Torznab_0 api "$torznab_api_key"
set_ini Torznab_0 manual 0
set_ini Torznab_0 dltypes E,A
set_ini RSS_0 dispname 'Goodreads want to read'
set_ini RSS_0 enabled 1
set_ini RSS_0 host "$goodreads_rss_url"
set_ini RSS_0 dlpriority 0
set_ini RSS_0 dltypes E

chown "$PUID:$PGID" "$config_file"
