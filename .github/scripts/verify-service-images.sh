#!/usr/bin/env bash
set -euo pipefail

# A clean config proves the server can pull without an undeclared registry secret.
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
services_source=$(nix eval --raw .#lib.servicesSource)
services_revision=$(nix eval --raw .#lib.servicesRevision)
compose_json=$(docker compose --project-directory containers/source \
  -f containers/source/utilities/docker-compose.yml config --no-interpolate --format json)
images=$(printf '%s' "$compose_json" | python3 -c '
import json, re, sys
services = json.load(sys.stdin)["services"]
images = {service["image"] for service in services.values()
          if service.get("image", "").startswith("ghcr.io/junr03/electricpeak-services/")}
assert images, "No electricpeak-services images found in deployment Compose"
for name in ("rawbackup", "substack-digest"):
    assert services[name]["image"] in images, f"{name} must consume the published service"
assert not any(v.get("target") == "/app" for v in services["rawbackup"].get("volumes", [])), "Application source must come from the image"
for image in sorted(images):
    assert re.fullmatch(r"ghcr.io/junr03/electricpeak-services/[a-z0-9-]+@sha256:[0-9a-f]{64}", image), image
    print(image)
')
while IFS= read -r image; do
  docker pull --platform linux/amd64 "$image"
  source=$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
  revision=$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
  [[ "$source" == https://github.com/junr03/electricpeak-services ]]
  [[ "$revision" == "$services_revision" ]] || {
    echo "Image revision $revision differs from locked host packages $services_revision" >&2
    exit 1
  }
  case "$image" in
    ghcr.io/junr03/electricpeak-services/rawbackup@*)
      bash "$services_source/scripts/smoke-rawbackup.sh" "$image"
      ;;
    ghcr.io/junr03/electricpeak-services/substack-digest@*)
      bash "$services_source/scripts/smoke-substack-digest.sh" "$image"
      ;;
    *) echo "Add a runtime smoke test for $image before deploying it" >&2; exit 1 ;;
  esac
done <<< "$images"
