#!/usr/bin/env bash
set -euo pipefail

credential_directory=/var/lib/opnix
credential_file="$credential_directory/service-account-token.cred"
temporary_credential="$credential_file.new"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this command as root: sudo $0" >&2
  exit 1
fi

install -d -m 0700 -o root -g root "$credential_directory"
trap 'rm -f "$temporary_credential"' EXIT

token="$(systemd-ask-password --emoji=no "1Password service account token")"
if [[ -z $token ]]; then
  echo "The token cannot be empty." >&2
  exit 1
fi

printf '%s' "$token" \
  | systemd-creds encrypt --name=service-account-token - "$temporary_credential"
unset token
chmod 0600 "$temporary_credential"
mv -f "$temporary_credential" "$credential_file"

echo "Stored the machine-encrypted service account token in $credential_file."
if systemctl cat opnix-secrets.service >/dev/null 2>&1; then
  systemctl restart opnix-secrets.service
  echo "Refreshed 1Password secrets."
else
  echo "Deploy the NixOS configuration to install and start OpNix."
fi
