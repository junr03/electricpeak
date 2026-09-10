#!/bin/sh
set -eu

state_dir=/vdirsyncer

if [ ! -f "${state_dir}/enabled" ]; then
  echo "Contact sync is gated. Complete the first-sync runbook, then create /vdirsyncer/enabled."
  exit 1
fi

if grep -q '__[A-Z_]*__' "${state_dir}/config"; then
  echo "Contact sync is gated. Replace the collection ID placeholders in /vdirsyncer/config."
  exit 1
fi

for required_file in \
  google-contacts-token \
  secrets/google-client-id \
  secrets/google-client-secret \
  secrets/icloud-username \
  secrets/icloud-app-password
do
  if [ ! -s "${state_dir}/${required_file}" ]; then
    echo "Contact sync is gated. Missing ${state_dir}/${required_file}."
    exit 1
  fi
done
