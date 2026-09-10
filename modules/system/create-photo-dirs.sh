mkdir -p /mnt/data/photos/raw
mkdir -p /mnt/data/photos/edited
# Only change ownership if directories exist and are accessible
if [ -d /mnt/data/photos ]; then
  chown -R junr03:users /mnt/data/photos 2>/dev/null || true
  chmod -R 755 /mnt/data/photos 2>/dev/null || true
fi
