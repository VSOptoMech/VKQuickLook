# Install VKQuickLook

This guide installs the source-built macOS Quick Look app locally. It also covers the Apple signing certificate setup needed for Finder and Quick Look to trust the extension reliably.

## Prerequisites

- macOS 13 or newer.
- Xcode command line tools or Xcode with `swiftc`, `xcrun`, `codesign`, `pluginkit`, and `qlmanage`.
- An Apple Developer account if you want a trusted Apple Development or Developer ID signature.

## Build And Install Locally

From the repository root:

```bash
scripts/build_macos_quicklook.sh --install
```

The app is copied to:

```text
~/Applications/VKQuickLook.app
```

The build also writes a Swift validation CLI next to the app in the build directory:

```text
build/macos-quicklook/VKQuickLookRender
```

The script refreshes Launch Services, PluginKit, and the Quick Look cache. If Finder still shows generic icons, run:

```bash
qlmanage -r
qlmanage -r cache
killall Finder
```

Then test with your own files:

```bash
build/macos-quicklook/VKQuickLookRender thumbnail path/to/file.vk6 --output /tmp/vk-thumb.png
build/macos-quicklook/VKQuickLookRender preview path/to/file.vk4 --output /tmp/vk-preview.png
qlmanage -t -s 512 -o /tmp path/to/file.vk4
qlmanage -t -s 512 -o /tmp path/to/file.vk6
qlmanage -p path/to/file.vk4
qlmanage -p path/to/file.vk6
```

## Sign With An Apple Development Certificate

Ad-hoc signing is enough to build the app, but a real Apple signing identity is more reliable for local Finder extension registration.

Apple's certificate overview explains that macOS uses different certificate types for development and distribution, and that development certificates belong to individuals. See Apple's current certificate overview: <https://developer.apple.com/help/account/certificates/certificates-overview/>.

To create the certificate manually:

1. Open Keychain Access from `/Applications/Utilities`.
2. Choose Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority.
3. Enter your Apple Developer account email and a common name such as `Your Name VKQuickLook Dev Key`.
4. Leave the CA Email Address field empty.
5. Select `Saved to disk` and save the `.certSigningRequest` file.
6. In Apple Developer > Certificates, Identifiers & Profiles, create an `Apple Development` certificate using that CSR.
7. Download the `.cer` file and double-click it so it appears in Keychain Access under `My Certificates`.

Apple's CSR instructions are here: <https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/>.

Find the installed signing identity:

```bash
security find-identity -v -p codesigning
```

Build and install with that identity:

```bash
scripts/build_macos_quicklook.sh \
  --install \
  --bundle-id-prefix "com.vsoptomech.vkquicklook" \
  --type-id-prefix "com.vsoptomech.keyencevkx" \
  --sign-identity "Apple Development: Your Name (TEAMID)"
```

Use bundle and type identifier prefixes that belong to you for anything you share. The repository defaults use the public `com.vsoptomech...` identifiers; forks should override them.

Verify the installed app:

```bash
codesign --verify --deep --strict --verbose=2 ~/Applications/VKQuickLook.app
pluginkit -m -v | rg VKQuickLook
```

During installation, the script unregisters any previous `VKQuickLook.app`
extensions before replacing the app bundle, then refreshes LaunchServices and
Quick Look caches. This avoids stale extension IDs such as
`Extension ...preview not found` after identifier or plist changes.

## Developer ID For Public Distribution

For release outside the Mac App Store, use a `Developer ID Application` certificate and notarize the final app archive. Apple describes Developer ID as the certificate family for Mac software distributed outside the Mac App Store, and notes that notarization lets Gatekeeper check that the software is not known malware and has not been modified. See:

- Developer ID certificates: <https://developer.apple.com/help/account/certificates/create-developer-id-certificates/>
- Notarizing macOS software: <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>

The source build can be signed with Developer ID:

```bash
scripts/build_macos_quicklook.sh \
  --bundle-id-prefix "com.vsoptomech.vkquicklook" \
  --type-id-prefix "com.vsoptomech.keyencevkx" \
  --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

Notarization packaging is intentionally not automated here yet. Before publishing a binary release, add a release script that archives the app, submits it with `notarytool`, staples the ticket, and verifies Gatekeeper with `spctl`.

## Troubleshooting

- If `pluginkit` does not list the extensions, confirm the app is signed and installed under `~/Applications` or `/Applications`.
- If Finder shows stale Quick Look behavior after reinstalling, run `qlmanage -r`, `qlmanage -r cache`, and reopen Finder.
- If old thumbnails remain, clear Quick Look cache with `qlmanage -r cache`.
- If previews fail for one file, validate the same native renderer with `build/macos-quicklook/VKQuickLookRender preview path/to/file.vk4 --output /tmp/vk-preview.png`.
- Do not commit certificates, private keys, provisioning profiles, notarization credentials, or machine-specific build output.
