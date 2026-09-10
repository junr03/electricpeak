missing=0
for secret in @SECRET_PATHS@; do
  if [ ! -s "$secret" ]; then
    echo "1Password did not materialize required secret: $secret" >&2
    missing=1
  fi
done
exit "$missing"
