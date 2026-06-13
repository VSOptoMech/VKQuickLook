# Linux GNOME Thumbnailer

VKQuickLook includes a standalone thumbnailer for Ubuntu/GNOME/Nautilus. It uses
the freedesktop thumbnailer mechanism and installs per user by default.

## Scope

Supported:

- `.vk4`
- `.vk6`

Not supported by this thumbnailer:

- HDF5
- stitched HDF5
- teaching CSVs
- arbitrary raster images

## Rendering Strategy

The Linux thumbnailer intentionally mirrors the macOS thumbnail behavior without
porting the full measurement parser:

- VK6: read the wrapper BMP preview at the start of the file, resize it, and
  write GNOME's requested PNG output.
- VK4: read the offset table and embedded 24-bit thumbnail sections in this
  priority order: `clr_thumb`, `clr_peak_thumb`, `light_thumb`, `height_thumb`.
- The source file is opened read-only and never modified.
- Temporary output is written in the output directory and atomically renamed to
  GNOME's requested output path.

## Install

Install for the current user:

```bash
scripts/install_linux_thumbnailer.sh
```

The installer does not require root and refuses `sudo`. It installs:

```text
~/.local/bin/vk-thumbnailer
~/.local/share/vkquicklook/linux-thumbnailer/venv/
~/.local/share/mime/packages/vsoptomech-keyence-vk.xml
~/.local/share/thumbnailers/vkquicklook.thumbnailer
```

It also refreshes the user MIME database when `update-mime-database` is present:

```bash
update-mime-database ~/.local/share/mime
```

If `update-mime-database` is missing on Ubuntu, install `shared-mime-info`.

## Validate

Run the thumbnailer directly:

```bash
vk-thumbnailer --input path/to/sample.vk6 --output /tmp/vk-thumb.png --size 256
file /tmp/vk-thumb.png
```

Verify the MIME type:

```bash
xdg-mime query filetype path/to/sample.vk6
xdg-mime query filetype path/to/sample.vk4
```

Expected results:

```text
application/x-vsoptomech-keyence-vk6
application/x-vsoptomech-keyence-vk4
```

Refresh Nautilus thumbnails:

```bash
rm -rf ~/.cache/thumbnails/*
nautilus -q
```

Then open a folder containing `.vk4` and `.vk6` files in GNOME Files/Nautilus.
The file icons should show measurement imagery, not generic blank icons.

## Troubleshooting

Check that the executable is visible:

```bash
which vk-thumbnailer
vk-thumbnailer --input path/to/sample.vk4 --output /tmp/vk-thumb.png --size 256
```

Check registration files:

```bash
ls ~/.local/share/mime/packages/vsoptomech-keyence-vk.xml
ls ~/.local/share/thumbnailers/vkquicklook.thumbnailer
cat ~/.local/share/thumbnailers/vkquicklook.thumbnailer
```

Rebuild the MIME database:

```bash
update-mime-database ~/.local/share/mime
```

Clear stale success and failure thumbnails:

```bash
rm -rf ~/.cache/thumbnails/*
nautilus -q
```

If direct CLI rendering fails, inspect the stderr message. The thumbnailer
returns a nonzero exit code for corrupt, unsupported, or incomplete files and
does not show GUI dialogs.

## Uninstall

Remove user-local files:

```bash
scripts/uninstall_linux_thumbnailer.sh
```

Then clear stale thumbnails and restart Nautilus:

```bash
rm -rf ~/.cache/thumbnails/*
nautilus -q
```
