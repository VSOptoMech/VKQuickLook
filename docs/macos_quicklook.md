# macOS Quick Look for VK4/VK6

This repository includes source for native macOS Finder thumbnails and Quick Look previews for Keyence `.vk4` and `.vk6` files.

## Scope

Supported:

- `.vk4`
- `.vk6`

Not supported by this Quick Look extension:

- HDF5
- raster images
- teaching CSVs
- stitched outputs

Those formats are outside this Swift-only Quick Look project.

## Architecture

The production Quick Look path is the Swift renderer in `macos/QuickLook/Sources/Shared/NativeVKRenderer.swift`.

The Quick Look implementation is split into three layers:

- `macos/QuickLook` contains a macOS app with:
  - `VKThumbnailExtension.appex`, a `QLThumbnailProvider`.
  - `VKPreviewExtension.appex`, an `NSViewController` implementing `QLPreviewingController`.
- `VKQuickLookRender` is a Swift validation CLI built from the same native renderer source.

The Swift extensions render natively because macOS Quick Look extensions run in a sandbox and should not launch external runtimes. The native path is intentionally narrow:

- VK6 wrapper BMP preview from the container header.
- VK4 offset-table image sections for embedded thumbnails.
- VK4 full 24-bit color image sections for previews when available.

`VKQuickLookRender` is the Swift validation CLI and is built from the same native renderer source as the Finder extensions.

## Rendering Strategy

Thumbnail mode is optimized for Finder grid/list views:

- VK6: decode the wrapper BMP preview first without decompressing the embedded VK4 payload.
- VK4: read only the VK4 offset table and embedded thumbnail sections.
- Fallback priority follows the gallery: color thumbnail, peak thumbnail, light thumbnail, height thumbnail.

Preview mode is optimized for Spacebar Quick Look:

- VK4: render the full 24-bit color light image, then peak color image, then embedded thumbnails as fallback.
- VK6: render the wrapper BMP preview without decompressing the embedded VK4 ZIP payload.
- Resize the PNG to a bounded maximum edge for responsive display.

## Caching

The extension does not keep a persistent cache. macOS Quick Look and Finder maintain their own thumbnail cache. Each request writes temporary PNG/JSON files under the extension process temporary directory.

## Build

Build the containing app and extensions:

```bash
scripts/build_macos_quicklook.sh
```

The built bundle and Swift validation CLI are written to:

```text
build/macos-quicklook/VKQuickLook.app
build/macos-quicklook/VKQuickLookRender
```

The shell build script uses `swiftc` and does not require a checked-in Xcode project or Python runtime. A full Xcode install or an Apple signing identity is still recommended for a redistributable build.

## Install

For local source installs:

```bash
scripts/build_macos_quicklook.sh --install
```

This copies the app to:

```text
~/Applications/VKQuickLook.app
```

It also refreshes Quick Look caches with `qlmanage -r` and `qlmanage -r cache`.

For a trusted distribution build, sign with a real Apple identity:

```bash
scripts/build_macos_quicklook.sh \
  --install \
  --bundle-id-prefix "com.vsoptomech.vkquicklook" \
  --type-id-prefix "com.vsoptomech.keyencevkx" \
  --sign-identity "Apple Development: Your Name (TEAMID)"
```

Maintainers distributing this publicly should use Developer ID signing and notarization.

## Validation

Swift renderer validation:

```bash
scripts/test_swift_renderer.sh
```

Bundle validation:

```bash
scripts/build_macos_quicklook.sh
codesign --verify --deep --strict --verbose=2 build/macos-quicklook/VKQuickLook.app
plutil -p build/macos-quicklook/VKQuickLook.app/Contents/Info.plist
plutil -p build/macos-quicklook/VKQuickLook.app/Contents/PlugIns/VKThumbnailExtension.appex/Contents/Info.plist
plutil -p build/macos-quicklook/VKQuickLook.app/Contents/PlugIns/VKPreviewExtension.appex/Contents/Info.plist
```

The app bundle imports the VK4/VK6 Uniform Type Identifiers and declares the
document type with `CFBundleTypeRole=None` and `LSHandlerRank=None`. This gives
LaunchServices a stable `.vk4`/`.vk6` mapping without advertising the
container app as an "Open With" document viewer.

Finder validation after installation:

```bash
qlmanage -r
qlmanage -r cache
qlmanage -t -s 512 -o /tmp path/to/sample.vk6
qlmanage -t -s 512 -o /tmp path/to/sample.vk4
qlmanage -p path/to/sample.vk4
qlmanage -p path/to/sample.vk6
```

Manual test plan:

1. Open a folder containing `.vk4` and `.vk6` files in Finder.
2. Switch to icon view and increase icon size.
3. Confirm thumbnails show measurement imagery, not generic blank icons.
4. Select a `.vk4` file and press Space.
5. Confirm the preview opens with a rendered measurement image and compact metadata.
6. Repeat with a `.vk6` file.
7. Try a damaged copy of a VK file and confirm Finder/Quick Look does not crash.

## Current Limitations

- This source build can be ad-hoc signed for local development, but macOS may cache old LaunchServices and Quick Look extension state aggressively after plist changes.
- The Swift extension renderer intentionally covers VK4/VK6 image-preview paths only. It does not implement HDF5, stitched outputs, teaching CSVs, or other project formats.
- VK6 Spacebar preview uses the wrapper BMP preview. Full VK6 embedded-VK4 ZIP extraction is intentionally out of scope to keep this project focused on Quick Look behavior.
- Quick Look APIs invoke extensions out-of-process and may cache old results aggressively. Use `qlmanage -r cache` after rebuilding.
