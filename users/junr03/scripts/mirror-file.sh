source_path="$1"
destination_path="$2"
mode="$3"
create_parent="$4"

if [ "$create_parent" = true ]; then
  mkdir -p "$(dirname "$destination_path")"
fi
cat "$source_path" > "$destination_path"
chmod "$mode" "$destination_path"
