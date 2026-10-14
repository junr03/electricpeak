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

deployment_dir=""
stage="Read current server state"
launched=false
completed=false
retain=false
# Called by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  # Keep private diagnostics on the server after a failed or uncertain switch.
  if [[ $retain == true || ( $launched == true && $completed != true ) ]]; then
    echo "Private deployment diagnostics retained on the server for $DEPLOYMENT_UNIT."
    return
  fi
  [[ $deployment_dir =~ ^/tmp/electricpeak-deploy\.[A-Za-z0-9]+$ ]] || return 0
  ssh_server "rm -rf -- '$deployment_dir'" || true
}
report() {
  printf '%s\n' "$1" >&2
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf -- '- %s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

phase() {
  stage=$1
  report "Deployment stage: $stage."
}

# Report the phase, never the failed command: it may include private paths.
# shellcheck disable=SC2329
finish() {
  local exit_code=$?
  trap - EXIT
  if ((exit_code != 0)); then
    report "Deployment failed during: $stage (exit $exit_code; elapsed ${SECONDS}s)."
    printf '::error::Deployment failed during: %s (exit %s).\n' "$stage" "$exit_code" >&2
    if [[ $deployment_dir =~ ^/tmp/electricpeak-deploy\.[A-Za-z0-9]+$ ]]; then
      retain=true
      report "Inspect private diagnostics on the server: checkout $deployment_dir; unit $DEPLOYMENT_UNIT."
      report 'Logs, when available: build.log, launch.log, controller.log, runtime-verification.log.'
    else
      report 'No validated deployment checkout is available; no build or activation was started.'
    fi
  else
    report "Deployment completed successfully (elapsed ${SECONDS}s)."
  fi
  cleanup || true
  exit "$exit_code"
}
trap finish EXIT

phase 'Read current server state'
active_before=$(ssh_server 'readlink -f /run/current-system')
containers_before=$(ssh_server "docker ps --no-trunc -q | sort")
phase 'Create deployment checkout'
deployment_dir=$(ssh_server 'mktemp -d /tmp/electricpeak-deploy.XXXXXX')
[[ $deployment_dir =~ ^/tmp/electricpeak-deploy\.[A-Za-z0-9]+$ ]]
phase 'Transfer assembled sources'

rsync -az --exclude='.git' \
  -e "ssh -i $HOME/.ssh/electricpeak -o BatchMode=yes -o StrictHostKeyChecking=yes" \
  "$source_dir/" "$server:$deployment_dir/source/"
rsync -az \
  -e "ssh -i $HOME/.ssh/electricpeak -o BatchMode=yes -o StrictHostKeyChecking=yes" \
  "$controller_dir/.github/scripts/" "$server:$deployment_dir/controller/"

phase 'Production build'
if ! ssh_server "cd '$deployment_dir/source' && sudo -n nixos-rebuild build --no-reexec --flake 'path:$deployment_dir/source#electricpeak' > '$deployment_dir/build.log' 2>&1"; then
  retain=true
  echo 'Production build failed; private diagnostics were not copied to this public log.' >&2
  exit 1
fi
phase 'Verify build output'
candidate=$(ssh_server "readlink -f '$deployment_dir/source/result'")
[[ $candidate == /nix/store/*-nixos-system-* ]]
# A path flake includes untracked files. Remove the build's result symlink so
# a later switch evaluates exactly the same source bytes as this build.
ssh_server "test -L '$deployment_dir/source/result' && rm -- '$deployment_dir/source/result'"
printf 'Public revision %s built successfully with the masked private revision.\n' \
  "$PUBLIC_REVISION"

if [[ $activate == false ]]; then
  phase 'Verify build-only handoff'
  test "$(ssh_server 'readlink -f /run/current-system')" = "$active_before"
  test "$(ssh_server "docker ps --no-trunc -q | sort")" = "$containers_before"
  echo 'Build-only handoff passed; active generation and container IDs are unchanged.'
  exit 0
fi

phase 'Launch activation'
launched=true
ssh_server "systemd-run --user --no-block --unit='$DEPLOYMENT_UNIT' --service-type=oneshot -- '$deployment_dir/controller/nixos-rebuild-deploy.sh' '$deployment_dir/source' > '$deployment_dir/launch.log' 2>&1"
phase 'Wait for activation'
deadline=$((SECONDS + 900))
while ((SECONDS < deadline)); do
  status=$(ssh_server "systemctl --user show '$DEPLOYMENT_UNIT.service' --property=ActiveState --property=ExecMainStatus" 2>/dev/null || true)
  state=$(awk -F= '$1 == "ActiveState" {print $2}' <<< "$status")
  code=$(awk -F= '$1 == "ExecMainStatus" {print $2}' <<< "$status")
  case "$state" in
    active|activating|deactivating|'') sleep 10 ;;
    inactive)
      if [[ $code != 0 ]]; then
        retain=true
        echo 'Production activation failed; private diagnostics were not copied to this public log.' >&2
        exit 1
      fi
      phase 'Verify active generation'
      test "$(ssh_server "cat '$deployment_dir/source/.active-system'")" = "$candidate"
      test "$(ssh_server 'readlink -f /run/current-system')" = "$candidate"
      completed=true
      phase 'Runtime verification'
      for attempt in {1..12}; do
        printf 'Runtime verification attempt %s/12\n' "$attempt"
        if ssh_server "'$deployment_dir/controller/verify-deployment-runtime.sh' >> '$deployment_dir/runtime-verification.log' 2>&1"; then
          exit 0
        fi
        sleep 10
      done
      retain=true
      echo 'Runtime verification failed after stabilization.' >&2
      echo 'Private diagnostics were not copied to this public log.' >&2
      exit 1
      ;;
    *)
      phase 'Unexpected activation state'
      retain=true
      ssh_server "journalctl --no-pager '_SYSTEMD_USER_UNIT=$DEPLOYMENT_UNIT.service' > '$deployment_dir/controller.log' 2>&1" || true
      echo 'Deployment entered an unexpected state; private diagnostics remain on the server.' >&2
      exit 1
      ;;
  esac
done
echo 'Deployment did not finish within 15 minutes.' >&2
exit 1
