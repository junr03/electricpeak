#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
git -C "$repo_root" config core.hooksPath .githooks
echo "Installed Electricpeak public-repository hooks from $repo_root/.githooks"
