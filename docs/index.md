---
title: VKQuickLook — macOS Quick Look previews for Keyence VK4 and VK6 files
description: Native macOS Finder thumbnails and Spacebar Quick Look previews for Keyence .vk4 and .vk6 measurement files from VK-X laser confocal microscopes and 3D profilometers.
---

# VKQuickLook — macOS Quick Look previews for Keyence VK4 and VK6 files

VKQuickLook is a native Swift Quick Look extension for macOS that shows Finder thumbnails and Spacebar previews for Keyence `.vk4` and `.vk6` measurement files.

It is designed for Keyence VK-X series laser confocal microscope and 3D profilometer users who want to visually inspect measurement files on a Mac without launching Keyence desktop software.

## What VKQuickLook does

- Adds Finder thumbnails for `.vk4` and `.vk6` files.
- Adds Spacebar Quick Look previews for supported Keyence measurement files.
- Uses a native Swift renderer suitable for Quick Look extension sandboxing.
- Includes `VKQuickLookRender`, a command-line renderer for validation and debugging.
- Builds locally from source with the included shell scripts.

## Supported file types

VKQuickLook supports:

- Keyence `.vk4` measurement files
- Keyence `.vk6` measurement files

VKQuickLook does not support HDF5, stitched HDF5, teaching CSVs, or arbitrary raster images. Those formats are outside the scope of this Swift-only Finder preview extension.

## Common use cases

Use VKQuickLook when you need to:

- preview Keyence VK4 files on macOS
- preview Keyence VK6 files on macOS
- show Finder thumbnails for Keyence VK-X measurement data
- inspect VK4/VK6 microscopy or profilometry files before opening a full analysis tool
- validate embedded VK4/VK6 preview imagery from the command line

## Installation

From the repository root:

```bash
scripts/build_macos_quicklook.sh --install
```

The local source build installs:

```text
~/Applications/VKQuickLook.app
```

For signing and troubleshooting details, see the [install and signing guide](install.md).

## Validation

After installation, refresh Quick Look and test a sample file:

```bash
qlmanage -r
qlmanage -r cache
qlmanage -t -s 512 -o /tmp path/to/file.vk4
qlmanage -t -s 512 -o /tmp path/to/file.vk6
qlmanage -p path/to/file.vk4
qlmanage -p path/to/file.vk6
```

For implementation details, see the [macOS Quick Look notes](macos_quicklook.md).

## Related search terms

Keyence VK4 Quick Look, Keyence VK6 Quick Look, macOS VK4 viewer, macOS VK6 viewer, Finder thumbnail extension for VK4 files, Finder thumbnail extension for VK6 files, Quick Look extension for Keyence files, Keyence VK-X file preview, laser confocal microscope file preview, 3D profilometer file preview, Swift Quick Look extension.

## Project links

- [Repository README](../README.md)
- [Install and signing guide](install.md)
- [macOS Quick Look implementation notes](macos_quicklook.md)

VKQuickLook is an independent open-source project and is not affiliated with, endorsed by, or sponsored by KEYENCE CORPORATION. KEYENCE is used only to identify the file formats this tool supports.
