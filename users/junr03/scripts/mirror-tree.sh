source_path="$1"
destination_path="$2"

mkdir -p "$destination_path"
find "$destination_path" -type l -delete
cp -Lr "$source_path/." "$destination_path/"
