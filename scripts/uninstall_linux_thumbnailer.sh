#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
bin_dir="$HOME/.local/bin"
install_root="$data_home/vkquicklook/linux-thumbnailer"
mime_root="$data_home/mime"
mime_target="$mime_root/packages/vsoptomech-keyence-vk.xml"
thumbnailer_target="$data_home/thumbnailers/vkquicklook.thumbnailer"
wrapper_path="$bin_dir/vk-thumbnailer"

usage() {
  cat <<'EOF'
Usage: scripts/uninstall_linux_thumbnailer.sh

Removes the current user's VKQuickLook GNOME thumbnailer files.
Do not run this script with sudo.

Environment:
  XDG_DATA_HOME=PATH        User data directory. Default: ~/.local/share
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "This uninstaller is user-local; run it without sudo." >&2
  exit 2
fi

rm -f "$wrapper_path" "$mime_target" "$thumbnailer_target"
rm -rf "$install_root"
rmdir "$data_home/vkquicklook" 2>/dev/null || true

if command -v update-mime-database >/dev/null 2>&1 && [[ -d "$mime_root" ]]; then
  update-mime-database "$mime_root"
fi

cat <<EOF
Removed VKQuickLook Linux thumbnailer files.

Clear stale thumbnails with:
  rm -rf ~/.cache/thumbnails/*
Restart Nautilus with:
  nautilus -q
EOF
