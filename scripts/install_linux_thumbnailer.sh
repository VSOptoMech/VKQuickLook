#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_cmd="${PYTHON:-python3}"
install_scope="user"
mime_source="$repo_root/linux/mime/vsoptomech-keyence-vk.xml"
thumbnailer_template="$repo_root/linux/thumbnailers/vkquicklook.thumbnailer.in"

usage() {
  cat <<'EOF'
Usage: scripts/install_linux_thumbnailer.sh [--system]

Installs the VKQuickLook GNOME thumbnailer.

Default user-local install:
  ~/.local/bin/vk-thumbnailer
  ~/.local/share/vkquicklook/linux-thumbnailer/venv
  ~/.local/share/mime/packages/
  ~/.local/share/thumbnailers/

System install for GNOME/Nautilus sandbox compatibility:
  sudo scripts/install_linux_thumbnailer.sh --system
  /usr/local/bin/vk-thumbnailer
  /usr/local/share/vkquicklook/linux-thumbnailer/venv
  /usr/local/share/mime/packages/
  /usr/local/share/thumbnailers/

Environment:
  PYTHON=/path/to/python3   Python interpreter used to create the install venv
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
    echo "The default installer is user-local; run it without sudo or use --system." >&2
    exit 2
  fi
  data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  bin_dir="$HOME/.local/bin"
else
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "System install requires root. Run: sudo scripts/install_linux_thumbnailer.sh --system" >&2
    exit 2
  fi
  data_home="/usr/local/share"
  bin_dir="/usr/local/bin"
fi
thumbnailers_dir="$data_home/thumbnailers"
mime_root="$data_home/mime"
install_root="$data_home/vkquicklook/linux-thumbnailer"
venv_dir="$install_root/venv"
mime_packages_dir="$mime_root/packages"
wrapper_path="$bin_dir/vk-thumbnailer"
mime_target="$mime_packages_dir/vsoptomech-keyence-vk.xml"
thumbnailer_target="$thumbnailers_dir/vkquicklook.thumbnailer"

if ! command -v "$python_cmd" >/dev/null 2>&1; then
  echo "Python interpreter not found: $python_cmd" >&2
  exit 1
fi

build_source="$repo_root"
if [[ "$install_scope" == "system" ]]; then
  # pip builds local projects in place. Keep root-owned build files out of the checkout.
  build_source="$(mktemp -d)"
  trap 'rm -rf -- "$build_source"' EXIT
  mkdir "$build_source/src"
  cp "$repo_root/pyproject.toml" "$repo_root/README.md" "$build_source/"
  cp -R "$repo_root/src/vkquicklook_linux" "$build_source/src/"
fi

"$python_cmd" -m venv "$venv_dir"
"$venv_dir/bin/python" -m pip install "$build_source"

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
Installed VKQuickLook Linux thumbnailer ($install_scope).

Executable: $wrapper_path
MIME XML:   $mime_target
Thumbnailer:$thumbnailer_target

Make sure $bin_dir is on PATH for manual vk-thumbnailer commands.
Clear stale thumbnails with:
  rm -rf ~/.cache/thumbnails/*
Restart Nautilus with:
  nautilus -q
EOF

if [[ "$install_scope" == "system" ]]; then
  cat <<'EOF'

If you previously installed VKQuickLook for your user, verify the system
wrapper at /usr/local/bin/vk-thumbnailer, then retire the old installation
as that user (without sudo):
  scripts/uninstall_linux_thumbnailer.sh
Use the same XDG_DATA_HOME as the original user-local install.
EOF
fi
