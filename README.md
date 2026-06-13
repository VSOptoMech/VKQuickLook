# VKQuickLook

Native desktop thumbnails and previews for Keyence `.vk4` and `.vk6` measurement files.

VKQuickLook is an independent open-source project and is not affiliated with,
endorsed by, or sponsored by KEYENCE CORPORATION. KEYENCE is used only to
identify the file formats this tool supports.

This repository contains:

- A native Swift Quick Look Thumbnail extension.
- A native Swift Quick Look Preview extension.
- A Swift command-line renderer, `VKQuickLookRender`, built from the same renderer source as the Finder extensions.
- A standalone Python GNOME/Nautilus thumbnailer, `vk-thumbnailer`, for Ubuntu/Linux workstations.
- Build, install, and validation scripts for local development and signed distribution builds.

## Scope

Supported by the Finder extension:

- `.vk4`
- `.vk6`

Not supported by this extension:

- HDF5
- stitched HDF5
- teaching CSVs
- arbitrary raster images

## Architecture

The installed Finder extension renders natively in Swift because Quick Look extensions run in a sandbox and should not depend on external runtimes.

The macOS native path is intentionally narrow:

- VK6 thumbnails/previews use the wrapper BMP preview in the VK6 container.
- VK4 thumbnails use embedded 24-bit thumbnail sections in the VK4 offset table.
- VK4 previews use full 24-bit `color_light`, then `color_peak`, then thumbnail fallbacks.

`VKQuickLookRender` and the Finder extensions share the same native renderer source.

The Linux path is a standalone Python thumbnailer for the freedesktop/GNOME thumbnailer mechanism:

- VK6 thumbnails use the wrapper BMP preview in the VK6 container.
- VK4 thumbnails use embedded 24-bit thumbnail sections in gallery order: color, peak, light, height.
- The thumbnailer writes the PNG output path requested by GNOME and does not modify the source file.

## Install For Local Use

```bash
scripts/build_macos_quicklook.sh --install
```

The default install builds and ad-hoc signs the app locally; users do not need
the maintainer's signing certificate or an Apple Developer account for a source
build. A real Apple signing identity is optional, but can make local extension
registration more reliable.

For a signed local build:

```bash
scripts/build_macos_quicklook.sh \
  --install \
  --bundle-id-prefix "com.vsoptomech.vkquicklook" \
  --type-id-prefix "com.vsoptomech.keyencevkx" \
  --sign-identity "Apple Development: Your Name (TEAMID)"
```

The app is installed to:

```text
~/Applications/VKQuickLook.app
```

## Validate

Swift renderer CLI:

```bash
tmpdir=$(mktemp -d)
scripts/build_macos_quicklook.sh --output-dir "$tmpdir/build" --skip-codesign
"$tmpdir/build/VKQuickLookRender" thumbnail path/to/file.vk6 --output "$tmpdir/thumb.png" --metadata-json "$tmpdir/thumb.json"
file "$tmpdir/thumb.png"
```

Finder thumbnail extension:

```bash
qlmanage -r
qlmanage -r cache
qlmanage -t -s 512 -o /tmp path/to/file.vk6
qlmanage -t -s 512 -o /tmp path/to/file.vk4
```

Quick Look preview extension:

```bash
qlmanage -p path/to/file.vk4
qlmanage -p path/to/file.vk6
```

Project checks:

```bash
scripts/test_swift_renderer.sh
scripts/build_macos_quicklook.sh --skip-codesign
python3 -m pytest
```

## Install On GNOME / Ubuntu

Install the Linux thumbnailer for the current user:

```bash
scripts/install_linux_thumbnailer.sh
```

This creates a private virtualenv under `~/.local/share/vkquicklook/linux-thumbnailer/`,
installs `vk-thumbnailer` through `~/.local/bin/vk-thumbnailer`, registers MIME
types under `~/.local/share/mime/packages/`, installs the thumbnailer descriptor
under `~/.local/share/thumbnailers/`, and runs:

```bash
update-mime-database ~/.local/share/mime
```

Clear stale thumbnails and restart Nautilus after installing or rebuilding:

```bash
rm -rf ~/.cache/thumbnails/*
nautilus -q
```

Direct CLI validation:

```bash
vk-thumbnailer --input path/to/file.vk6 --output /tmp/vk-thumb.png --size 256
file /tmp/vk-thumb.png
```

GNOME integration checks:

```bash
xdg-mime query filetype path/to/file.vk6
which vk-thumbnailer
ls ~/.local/share/thumbnailers/vkquicklook.thumbnailer
```

Open a folder containing `.vk4` or `.vk6` files in GNOME Files/Nautilus and
confirm the icons show measurement imagery instead of generic file icons.

Uninstall:

```bash
scripts/uninstall_linux_thumbnailer.sh
rm -rf ~/.cache/thumbnails/*
nautilus -q
```

## Distribution Notes

For public binary distribution, sign with Developer ID and notarize the app bundle. The source build scripts intentionally avoid a checked-in Xcode project and use `swiftc` directly.

Licensed under the MIT License.

Contact: vitek@vsoptomech.com

## Additional Documentation

- [Install and signing guide](docs/install.md)
- [macOS Quick Look implementation notes](docs/macos_quicklook.md)
- [Linux GNOME thumbnailer guide](docs/linux_thumbnailer.md)
