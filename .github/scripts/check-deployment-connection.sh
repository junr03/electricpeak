#!/usr/bin/env bash
# Use existing network tools; publish only fixed messages, never raw peer data.
set -euo pipefail

[[ ${SERVER_USER:?} =~ ^[a-z_][a-z0-9_-]*$ ]]
[[ ${TS_SERVER_HOST:?} =~ ^[A-Za-z0-9.:-]+$ ]]

report() {
  printf '%s\n' "$1"
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf -- '- %s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

fail() {
  report "$1"
  printf '::error::%s\n' "$1" >&2
  exit 1
}

for tool in tailscale jq getent nc ssh timeout; do
  command -v "$tool" >/dev/null || fail "Connection check requires $tool on the runner."
done

diagnostics_dir=$(mktemp -d)
trap 'rm -rf -- "$diagnostics_dir"' EXIT

report 'Deployment connection checks (private network details omitted).'
if ! timeout 10 tailscale status --json > "$diagnostics_dir/status.json" 2>/dev/null; then
  fail 'Tailscale runner status unavailable. Check the private-network connection step.'
fi
if ! jq -e '.BackendState == "Running"' "$diagnostics_dir/status.json" >/dev/null 2>&1; then
  fail 'Tailscale runner is not logged in and running. Check OAuth credentials and tag authorization.'
fi
report 'Tailscale runner: running.'
if jq -e '.Self.Online == true' "$diagnostics_dir/status.json" >/dev/null; then
  report 'Tailscale runner: online.'
else
  report 'Tailscale runner: not reported online; checking actual connectivity.'
fi
if jq -e '(.Health // []) | length > 0' "$diagnostics_dir/status.json" >/dev/null; then
  report 'Tailscale runner reports health warnings; inspect them privately on the runner.'
fi

if ! timeout 10 getent ahosts "$TS_SERVER_HOST" > "$diagnostics_dir/addresses" 2>/dev/null \
  || [[ ! -s $diagnostics_dir/addresses ]]; then
  fail 'Target name resolution failed. Check TS_SERVER_HOST and MagicDNS configuration.'
fi
report 'Target name resolution: succeeded.'
addresses=$(awk '{print $1}' "$diagnostics_dir/addresses" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')
peer=$(jq -c --argjson addresses "$addresses" '
  [.Peer[]? | select(any(.TailscaleIPs[]?; . as $ip | $addresses | index($ip)))] | first // null
' "$diagnostics_dir/status.json")
if [[ $peer == null ]]; then
  report 'Target is not visible as a Tailscale peer. Check TS_SERVER_HOST, device sharing, access policy, or subnet routing.'
elif jq -e '.Online == true' <<< "$peer" >/dev/null; then
  report 'Target Tailscale peer: visible and online.'
else
  report 'Target Tailscale peer: visible but offline. Check the server agent and network connection.'
fi

# A discovery ping checks the tunnel, not whether policy allows TCP port 22.
# Treat it as diagnostic: routed targets can still be reachable over SSH.
if timeout 10 tailscale ping --c=1 --timeout=5s --until-direct=false "$TS_SERVER_HOST" >/dev/null 2>&1; then
  report 'Tailscale discovery ping: succeeded; TCP port access is checked separately.'
else
  report 'Tailscale discovery ping: failed; check peer availability or routing if SSH also fails.'
fi

for attempt in {1..3}; do
  report "SSH readiness attempt $attempt/3."
  if timeout 10 nc -z -w 5 "$TS_SERVER_HOST" 22 > "$diagnostics_dir/tcp.log" 2>&1; then
    report 'TCP port 22: reachable.'
    if timeout 15 ssh -i "$HOME/.ssh/electricpeak" \
      -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
      -o ServerAliveInterval=5 -o ServerAliveCountMax=1 \
      "$SERVER_USER@$TS_SERVER_HOST" true > "$diagnostics_dir/ssh.log" 2>&1; then
      report 'SSH authentication and remote command: succeeded. Connection preflight passed.'
      exit 0
    fi
    if grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed|No .* host key is known' "$diagnostics_dir/ssh.log"; then
      fail 'SSH host identity verification failed. Verify SERVER_SSH_KNOWN_HOSTS against the server before updating it.'
    elif grep -Eqi 'Permission denied|Load key .*:|invalid format|error in libcrypto' "$diagnostics_dir/ssh.log"; then
      fail 'SSH authentication failed. Check SERVER_USER, SSH_PRIVATE_KEY, and the server authorized keys.'
    fi
    report 'SSH handshake or remote command failed after TCP connected. Check sshd availability and connection limits.'
  elif grep -qi 'Connection refused' "$diagnostics_dir/tcp.log"; then
    report 'TCP port 22: connection refused. Check that sshd is listening on the target.'
  else
    report 'TCP port 22: unreachable or timed out. Check the target address, routing, server firewall, and access policy for tag:github-actions.'
  fi
  if ((attempt < 3)); then
    sleep 5
  fi
done
fail 'Connection preflight failed after three attempts. No build or activation was started.'
