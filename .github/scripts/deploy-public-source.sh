#!/usr/bin/env bash
# Assemble, build, and optionally activate a public revision with its private overlay.
set -euo pipefail

source_dir=${1:?assembled source directory is required}
controller_dir=${2:?private controller directory is required}
activate=${ACTIVATE:-false}
[[ $activate == false || $activate == true ]]
[[ ${PUBLIC_REVISION:?} =~ ^[0-9a-f]{40}$ ]]
[[ ${PRIVATE_REVISION:?} =~ ^[0-9a-f]{40}$ ]]
[[ ${SERVER_USER:?} =~ ^[a-z_][a-z0-9_-]*$ ]]
[[ ${TS_SERVER_HOST:?} =~ ^[A-Za-z0-9.:-]+$ ]]
[[ ${DEPLOYMENT_UNIT:?} =~ ^electricpeak-deploy-[0-9]+-[0-9]+$ ]]
test -s "$source_dir/private-config/configuration.nix"
test -f "$controller_dir/.github/scripts/nixos-rebuild-deploy.sh"
test -f "$controller_dir/.github/scripts/verify-deployment-runtime.sh"

server="$SERVER_USER@$TS_SERVER_HOST"
ssh_server() {
  ssh -i "$HOME/.ssh/electricpeak" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$server" "$@"
}

active_before=$(ssh_server 'readlink -f /run/current-system')
containers_before=$(ssh_server "docker ps --no-trunc -q | sort")
deployment_dir=$(ssh_server 'mktemp -d /tmp/electricpeak-deploy.XXXXXX')
[[ $deployment_dir =~ ^/tmp/electricpeak-deploy\.[A-Za-z0-9]+$ ]]
launched=false
completed=false
# Called by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  # An interrupted controller must leave a running or uncertain switch intact.
  if [[ $launched == true && $completed != true ]]; then
    echo "Retaining deployment files for $DEPLOYMENT_UNIT."
    return
  fi
  ssh_server "rm -rf -- '$deployment_dir'" || true
}
trap cleanup EXIT

rsync -az --exclude='.git' \
  -e "ssh -i $HOME/.ssh/electricpeak -o BatchMode=yes -o StrictHostKeyChecking=yes" \
  "$source_dir/" "$server:$deployment_dir/source/"
rsync -az \
  -e "ssh -i $HOME/.ssh/electricpeak -o BatchMode=yes -o StrictHostKeyChecking=yes" \
  "$controller_dir/.github/scripts/" "$server:$deployment_dir/controller/"

ssh_server "cd '$deployment_dir/source' && sudo -n nixos-rebuild build --no-reexec --flake 'path:$deployment_dir/source#electricpeak'"
candidate=$(ssh_server "readlink -f '$deployment_dir/source/result'")
[[ $candidate == /nix/store/*-nixos-system-* ]]
# A path flake includes untracked files. Remove the build's result symlink so
# a later switch evaluates exactly the same source bytes as this build.
ssh_server "test -L '$deployment_dir/source/result' && rm -- '$deployment_dir/source/result'"
printf 'Public revision: %s\nPrivate revision: %s\nBuilt system: %s\n' \
  "$PUBLIC_REVISION" "$PRIVATE_REVISION" "$candidate"

if [[ $activate == false ]]; then
  test "$(ssh_server 'readlink -f /run/current-system')" = "$active_before"
  test "$(ssh_server "docker ps --no-trunc -q | sort")" = "$containers_before"
  echo 'Build-only handoff passed; active generation and container IDs are unchanged.'
  exit 0
fi

launched=true
ssh_server "systemd-run --user --no-block --unit='$DEPLOYMENT_UNIT' --service-type=oneshot -- '$deployment_dir/controller/nixos-rebuild-deploy.sh' '$deployment_dir/source'"
deadline=$((SECONDS + 900))
while ((SECONDS < deadline)); do
  status=$(ssh_server "systemctl --user show '$DEPLOYMENT_UNIT.service' --property=ActiveState --property=ExecMainStatus" 2>/dev/null || true)
  state=$(awk -F= '$1 == "ActiveState" {print $2}' <<< "$status")
  code=$(awk -F= '$1 == "ExecMainStatus" {print $2}' <<< "$status")
  case "$state" in
    active|activating|deactivating|'') sleep 10 ;;
    inactive)
      [[ $code == 0 ]] || exit 1
      completed=true
      test "$(ssh_server "cat '$deployment_dir/source/.active-system'")" = "$candidate"
      test "$(ssh_server 'readlink -f /run/current-system')" = "$candidate"
      for attempt in {1..12}; do
        printf 'Runtime verification attempt %s/12\n' "$attempt"
        if ssh_server "'$deployment_dir/controller/verify-deployment-runtime.sh'"; then
          exit 0
        fi
        sleep 10
      done
      echo 'Runtime verification failed after stabilization.' >&2
      exit 1
      ;;
    *)
      ssh_server "journalctl --no-pager '_SYSTEMD_USER_UNIT=$DEPLOYMENT_UNIT.service'" || true
      exit 1
      ;;
  esac
done
echo 'Deployment did not finish within 15 minutes.' >&2
exit 1
