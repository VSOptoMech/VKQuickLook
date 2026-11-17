#!/usr/bin/env bash
set -euo pipefail

install_scope="user"

usage() {
  cat <<'EOF'
Usage: scripts/uninstall_linux_thumbnailer.sh [--system]

Removes VKQuickLook GNOME thumbnailer files.

Default removes user-local files. Use:
  sudo scripts/uninstall_linux_thumbnailer.sh --system
to remove system files under /usr/local.

Environment:
  XDG_DATA_HOME=PATH        User data directory. Default: ~/.local/share
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      install_scope="system"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$install_scope" == "user" ]]; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "The default uninstaller is user-local; run it without sudo or use --system." >&2
    exit 2
  fi
  data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  bin_dir="$HOME/.local/bin"
else
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "System uninstall requires root. Run: sudo scripts/uninstall_linux_thumbnailer.sh --system" >&2
    exit 2
  fi
  data_home="/usr/local/share"
  bin_dir="/usr/local/bin"
fi
thumbnailer_target="$data_home/thumbnailers/vkquicklook.thumbnailer"
mime_root="$data_home/mime"
install_root="$data_home/vkquicklook/linux-thumbnailer"
mime_target="$mime_root/packages/vsoptomech-keyence-vk.xml"
wrapper_path="$bin_dir/vk-thumbnailer"

rm -f "$wrapper_path" "$mime_target" "$thumbnailer_target"
rm -rf "$install_root"
rmdir "$data_home/vkquicklook" 2>/dev/null || true

if command -v update-mime-database >/dev/null 2>&1 && [[ -d "$mime_root" ]]; then
  update-mime-database "$mime_root"
fi

cat <<EOF
Removed VKQuickLook Linux thumbnailer files ($install_scope).

Clear stale thumbnails with:
  rm -rf ~/.cache/thumbnails/*
Restart Nautilus with:
  nautilus -q
EOF
