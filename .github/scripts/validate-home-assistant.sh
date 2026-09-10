#!/usr/bin/env bash
# Validate with the deployed 2026.6.4 image, including its built-in blueprints.
set -euo pipefail

source_dir=${1:?Home Assistant source directory is required}
image=ghcr.io/home-assistant/home-assistant@sha256:adb3341e31e03e0048e60d8c1cf952e118a381ae258bb921d3da12a3b27bf0c2
config_dir=$(mktemp -d)
trap 'rm -rf -- "$config_dir"' EXIT
cp -R "$source_dir/." "$config_dir/"
printf 'test_secret: dummy_value\n' > "$config_dir/secrets.yaml"

# check_config can exit zero after logging integration/automation errors.
# Treat those diagnostics as failures, in addition to its exit status.
status=0
docker run --rm --network none --user "$(id -u):$(id -g)" \
  --entrypoint /bin/sh \
  -v "$config_dir:/config" \
  "$image" -c '
    set -eu
    mkdir -p /config/blueprints/automation/homeassistant
    if [ ! -f /config/blueprints/automation/homeassistant/motion_light.yaml ]; then
      cp /usr/src/homeassistant/homeassistant/components/automation/blueprints/motion_light.yaml \
        /config/blueprints/automation/homeassistant/motion_light.yaml
    fi
    python -m homeassistant --script check_config --config /config
  ' > "$config_dir/validation.log" 2>&1 || status=$?
cat "$config_dir/validation.log"
if ((status != 0)) || grep -Eq '(^|[[:space:]])ERROR([[:space:]:]|$)|Incorrect config|Failed config' "$config_dir/validation.log"; then
  echo 'Home Assistant validation failed.' >&2
  exit 1
fi
