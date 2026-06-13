#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_cmd="${PYTHON:-python3}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
bin_dir="$HOME/.local/bin"
install_root="$data_home/vkquicklook/linux-thumbnailer"
venv_dir="$install_root/venv"
mime_root="$data_home/mime"
mime_packages_dir="$mime_root/packages"
thumbnailers_dir="$data_home/thumbnailers"
wrapper_path="$bin_dir/vk-thumbnailer"
mime_source="$repo_root/linux/mime/vsoptomech-keyence-vk.xml"
mime_target="$mime_packages_dir/vsoptomech-keyence-vk.xml"
thumbnailer_template="$repo_root/linux/thumbnailers/vkquicklook.thumbnailer.in"
thumbnailer_target="$thumbnailers_dir/vkquicklook.thumbnailer"

usage() {
  cat <<'EOF'
Usage: scripts/install_linux_thumbnailer.sh

Installs the VKQuickLook GNOME thumbnailer for the current user only.
Do not run this script with sudo.

Environment:
  PYTHON=/path/to/python3   Python interpreter used to create the install venv
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
  echo "This installer is user-local; run it without sudo." >&2
  exit 2
fi

if ! command -v "$python_cmd" >/dev/null 2>&1; then
  echo "Python interpreter not found: $python_cmd" >&2
  exit 1
fi

"$python_cmd" -m venv "$venv_dir"
"$venv_dir/bin/python" -m pip install "$repo_root"

mkdir -p "$bin_dir" "$mime_packages_dir" "$thumbnailers_dir"

cat >"$wrapper_path" <<EOF
#!/usr/bin/env bash
exec "$venv_dir/bin/vk-thumbnailer" "\$@"
EOF
chmod +x "$wrapper_path"

cp "$mime_source" "$mime_target"

"$python_cmd" - "$thumbnailer_template" "$thumbnailer_target" "$wrapper_path" <<'PY'
from pathlib import Path
import sys

template = Path(sys.argv[1]).read_text(encoding="utf-8")
target = Path(sys.argv[2])
target.write_text(template.replace("@VK_THUMBNAILER@", sys.argv[3]), encoding="utf-8")
PY

if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database "$mime_root"
else
  echo "warning: update-mime-database not found; install shared-mime-info and run:" >&2
  echo "  update-mime-database \"$mime_root\"" >&2
fi

cat <<EOF
Installed VKQuickLook Linux thumbnailer.

Executable: $wrapper_path
MIME XML:   $mime_target
Thumbnailer:$thumbnailer_target

Make sure $bin_dir is on PATH for manual vk-thumbnailer commands.
Clear stale thumbnails with:
  rm -rf ~/.cache/thumbnails/*
Restart Nautilus with:
  nautilus -q
EOF
