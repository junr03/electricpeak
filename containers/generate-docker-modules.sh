#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="./containers/source"
ENV_FILE="../.env"
PROJECT="electricpeak"

find "$BASE_DIR" -type d -mindepth 1 -maxdepth 1 | while read -r dir; do
  echo "Generating Nix files for: $dir"
  (
    cd "$dir"
    # Use nix run in order to ensure the environment is set up correctly
    # and the compose2nix tool is available.
    nix run github:aksiksi/compose2nix/v0.3.2 -- \
      --runtime=docker \
      --env_files="$ENV_FILE" \
      --project="$PROJECT"
  )
done
