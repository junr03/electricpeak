#!/usr/bin/env bash
# Capture Git output locally so private commit subjects never enter public logs.
set -euo pipefail

if [[ ! ${PRIVATE_REVISION:-} =~ ^[0-9a-f]{40}$ || -z ${GH_TOKEN:-} ]]; then
  echo '::error::Private checkout requires a valid masked revision and repository read token.' >&2
  exit 1
fi
if [[ -e private-config || -L private-config ]]; then
  echo '::error::Private checkout refused an existing private-config path.' >&2
  exit 1
fi

diagnostics_dir=$(mktemp -d)
trap 'rm -rf -- "$diagnostics_dir"' EXIT
checkout_log=$diagnostics_dir/checkout.log

fail() {
  printf '::error::Private configuration checkout failed during %s. %s Raw Git output was omitted.\n' "$1" "$2" >&2
  exit 1
}

git init --quiet private-config > "$checkout_log" 2>&1 \
  || fail initialization 'Check runner filesystem access.'
git -C private-config remote add origin https://github.com/junr03/electricpeak-sensitive.git >> "$checkout_log" 2>&1 \
  || fail 'remote setup' 'Check the private checkout directory.'

# Pass auth only to fetch, through Git's process environment. It is never
# saved to .git/config or placed in command arguments. Disable interactive auth.
authorization=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')
GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $authorization" \
  timeout 120 git -C private-config fetch --no-tags --depth=1 origin "$PRIVATE_REVISION" >> "$checkout_log" 2>&1 \
  || fail fetch 'Check PAT_ELECTRICPEAK repository read access, the selected revision, and GitHub connectivity.'
unset authorization

git -C private-config checkout --quiet --detach FETCH_HEAD >> "$checkout_log" 2>&1 \
  || fail 'working tree setup' 'Check runner filesystem access and the fetched revision.'
if ! actual_revision=$(git -C private-config rev-parse HEAD 2>> "$checkout_log") \
  || [[ $actual_revision != "$PRIVATE_REVISION" ]]; then
  fail 'revision verification' 'The checkout did not match the selected private revision.'
fi

echo 'Private configuration checkout completed; revision and commit metadata omitted.'
