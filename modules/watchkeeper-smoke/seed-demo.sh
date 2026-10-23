#!/usr/bin/env bash
set -euo pipefail
umask 077

base=http://127.0.0.1:8765
secret_dir=/var/lib/watchkeeper-smoke/secrets
fixture=/etc/electricpeak/watchkeeper-smoke/codex-two-thread-demo.json
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

intake_token=$(<"$secret_dir/intake-token")
reviewer_token=$(<"$secret_dir/reviewer-token")
username=$(<"$secret_dir/ui-username")
password=$(<"$secret_dir/ui-password")
printf 'Authorization: Bearer %s\n' "$intake_token" > "$temporary_dir/intake.headers"
printf 'Authorization: Bearer %s\n' "$reviewer_token" > "$temporary_dir/reviewer.headers"
printf 'Authorization: Basic %s\n' "$(printf '%s' "$username:$password" | base64 | tr -d '\n')" > "$temporary_dir/ui.headers"
base_timestamp=$(date -u +%s)
cursor="electricpeak-smoke-$(date -u +%Y%m%dT%H%M%S%NZ)"
observation_count=$(jq '.observations | length' "$fixture")

ready=$(curl --silent --show-error --fail "$base/readyz")
printf 'Readiness: %s\n' "$ready"

unauthenticated_status=$(curl --silent --output /dev/null --write-out '%{http_code}' "$base/api/state")
if [ "$unauthenticated_status" != 401 ]; then
  printf 'Expected unauthenticated state request to return 401, got %s\n' "$unauthenticated_status" >&2
  exit 1
fi
printf 'Authentication gate: unauthenticated /api/state returns 401\n'

batch=$(jq --argjson base "$base_timestamp" --arg cursor "$cursor" \
  --argjson count "$observation_count" \
  '.cursor = $cursor | .observations |= (to_entries | map(.value.source_timestamp = (($base - (($count - 1 - .key) * 5)) | todateiso8601) | .value))' "$fixture")
intake_result=$(curl --silent --show-error --fail \
  -H "@$temporary_dir/intake.headers" \
  -H 'Content-Type: application/json' \
  --data "$batch" "$base/api/observations")
printf 'Synthetic intake: %s\n' "$(jq -c '{stored, source_id}' <<<"$intake_result")"

review_input=$(curl --silent --show-error --fail \
  -H "@$temporary_dir/reviewer.headers" "$base/api/review-input")
proposal=$(jq -c --argjson view "$review_input" '
  ($view.observations | map(select(.source_id == "codex-demo-installation"))) as $evidence |
  {
    project_id: "garden-guide",
    outcome: "Publish a garden guide with three tested planting plans",
    next_action: "Choose three planting zones for the garden guide",
    reasoning: "The synthetic source asks for planting zones before testing can finish.",
    evidence_refs: [$evidence[].observation_id],
    evidence_revisions: ([$evidence[] | {key: .observation_id, value: .revision}] | from_entries),
    status: "explicit_request",
    grouping_confidence: "strong"
  }
' <<<"$review_input")
review_result=$(curl --silent --show-error --fail \
  -H "@$temporary_dir/reviewer.headers" \
  -H 'Content-Type: application/json' \
  --data "$proposal" "$base/api/reviews")
if ! jq -e '.project_id == "garden-guide" and .status == "stored" and .eligible == true' <<<"$review_result" >/dev/null; then
  printf 'Expected the controlled garden-guide proposal to be stored and eligible\n' >&2
  exit 1
fi
printf 'Controlled proposal: %s\n' "$(jq -c '{project_id, status}' <<<"$review_result")"

page=$(curl --silent --show-error --fail -H "@$temporary_dir/ui.headers" \
  --cookie-jar "$temporary_dir/cookies" --cookie "$temporary_dir/cookies" "$base/")
csrf=$(sed -n 's/.*const csrf="\([^"]*\)".*/\1/p' <<<"$page")
if [ -z "$csrf" ]; then
  printf 'Could not read the UI CSRF token from the authenticated page\n' >&2
  exit 1
fi
printf 'X-CSRF-Token: %s\nOrigin: %s\n' "$csrf" "$base" > "$temporary_dir/csrf.headers"
delivery=$(curl --silent --show-error --fail \
  -H "@$temporary_dir/ui.headers" \
  --cookie "$temporary_dir/cookies" \
  -H "@$temporary_dir/csrf.headers" \
  --request POST "$base/api/deliver")
state=$(curl --silent --show-error --fail \
  -H "@$temporary_dir/ui.headers" "$base/api/state")
if ! jq -e 'any(.projects[]; .project_id == "garden-guide")' <<<"$state" >/dev/null; then
  printf 'Expected the synthetic garden-guide project in authenticated state\n' >&2
  exit 1
fi
if ! jq -e '(.delivered == 1 or .delivered == 0)' <<<"$delivery" >/dev/null; then
  printf 'Delivery response did not report a completed result\n' >&2
  exit 1
fi
captures=$(find /var/lib/watchkeeper-smoke/state/email -maxdepth 1 -type f -name '*.eml' | wc -l)
if [ "$captures" -lt 1 ]; then
  printf 'Expected at least one captured synthetic email after delivery\n' >&2
  exit 1
fi
printf 'File email sink delivery: %s\n' "$(jq -c '{delivered, emails}' <<<"$delivery")"
printf 'Captured synthetic email files: %s\n' "$captures"
printf 'Project state: garden-guide is present\n'
printf 'Open %s in a browser through the SSH tunnel to inspect the seeded project.\n' "$base"
