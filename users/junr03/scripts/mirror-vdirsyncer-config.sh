source_path="$1"
state_dir="$2"

# This remains an empty mount point; secret values live only in /run.
mkdir -p "$state_dir/secrets" "$state_dir/status"
cat "$source_path" > "$state_dir/config"
chmod 600 "$state_dir/config"
chmod 700 "$state_dir/secrets"
