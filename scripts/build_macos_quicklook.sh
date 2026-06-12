#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repo_root/macos/QuickLook/Sources"
output_dir="$repo_root/build/macos-quicklook"
bundle_id_prefix="com.vsoptomech.vkquicklook"
type_id_prefix="com.vsoptomech.keyencevkx"
min_macos="13.0"
sign_identity="-"
install_app=false
skip_codesign=false

usage() {
  cat <<'EOF'
Usage: scripts/build_macos_quicklook.sh [options]

Options:
  --output-dir PATH          Build output directory. Default: build/macos-quicklook
  --install                  Install VKQuickLook.app into ~/Applications
  --bundle-id-prefix VALUE   App and extension bundle identifier prefix
  --type-id-prefix VALUE     VK4/VK6 Uniform Type Identifier prefix
  --min-macos VERSION        Minimum macOS deployment target. Default: 13.0
  --sign-identity VALUE      codesign identity. Default: - for ad-hoc signing
  --skip-codesign            Do not sign the app bundle
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --install)
      install_app=true
      shift
      ;;
    --bundle-id-prefix)
      bundle_id_prefix="$2"
      shift 2
      ;;
    --type-id-prefix)
      type_id_prefix="$2"
      shift 2
      ;;
    --min-macos)
      min_macos="$2"
      shift 2
      ;;
    --sign-identity)
      sign_identity="$2"
      shift 2
      ;;
    --skip-codesign)
      skip_codesign=true
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

if [[ "$type_id_prefix" != *.* ]]; then
  echo "--type-id-prefix must be a reverse-DNS style prefix, such as com.vsoptomech.keyencevkx" >&2
  exit 2
fi

sdk="$(xcrun --show-sdk-path)"
arch="$(uname -m)"
target="${arch}-apple-macosx${min_macos}"
# The containing app imports the Keyence-owned VK file UTIs and declares a
# document type with role "None". That gives LaunchServices a stable mapping
# for .vk4/.vk6 without advertising the container app as a document viewer.
vk4_uti="${type_id_prefix%.}.vk4"
vk6_uti="${type_id_prefix%.}.vk6"
app_path="$output_dir/VKQuickLook.app"
cli_path="$output_dir/VKQuickLookRender"

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

compile_swift() {
  local module_name="$1"
  local output="$2"
  local extension_mode="$3"
  shift 3
  local frameworks=()
  while [[ "$1" != "--" ]]; do
    frameworks+=("$1")
    shift
  done
  shift
  local command=(
    swiftc
    -sdk "$sdk"
    -target "$target"
    -module-name "$module_name"
    -o "$output"
  )
  if [[ "$extension_mode" == "extension" ]]; then
    # Without _NSExtensionMain, swiftc emits a normal executable entry point
    # instead of the extension host entry used by Quick Look.
    command+=(-application-extension -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain)
  fi
  for framework in "${frameworks[@]}"; do
    command+=(-framework "$framework")
  done
  command+=("$@")
  run "${command[@]}"
}

write_app_plist() {
  local plist="$1"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>VKQuickLook</string>
  <key>CFBundleIdentifier</key><string>${bundle_id_prefix}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>VKQuickLook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${min_macos}</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Keyence VK measurement</string>
      <key>CFBundleTypeRole</key><string>None</string>
      <key>LSHandlerRank</key><string>None</string>
      <key>LSItemContentTypes</key>
      <array><string>${vk4_uti}</string><string>${vk6_uti}</string></array>
    </dict>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>${vk4_uti}</string>
      <key>UTTypeDescription</key><string>Keyence VK4 measurement</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>vk4</string></array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>${vk6_uti}</string>
      <key>UTTypeDescription</key><string>Keyence VK6 measurement</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>vk6</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
EOF
}

write_extension_plist() {
  local plist="$1"
  local executable_name="$2"
  local bundle_identifier="$3"
  local principal_class="$4"
  local extension_point="$5"
  local preview_attributes=""
  if [[ "$extension_point" == "com.apple.quicklook.preview" ]]; then
    # Match Xcode's Quick Look preview template for file-URL previews.
    preview_attributes=$'      <key>QLSupportsSearchableItems</key><false/>\n      <key>QLIsDataBasedPreview</key><false/>'
  fi
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>${executable_name}</string>
  <key>CFBundleIdentifier</key><string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${executable_name}</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${min_macos}</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionAttributes</key>
    <dict>
      <key>QLSupportedContentTypes</key>
      <array><string>${vk4_uti}</string><string>${vk6_uti}</string></array>
${preview_attributes}
    </dict>
    <key>NSExtensionPointIdentifier</key><string>${extension_point}</string>
    <key>NSExtensionPrincipalClass</key><string>${principal_class}</string>
  </dict>
</dict>
</plist>
EOF
}

write_entitlements() {
  local plist="$1"
  local user_selected="$2"
  local user_selected_key=""
  if [[ "$user_selected" == "true" ]]; then
    # Quick Look extensions need read-only access to user-selected files.
    user_selected_key=$'  <key>com.apple.security.files.user-selected.read-only</key><true/>'
  fi
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
${user_selected_key}
</dict>
</plist>
EOF
}

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/PlugIns" "$app_path/Contents/Resources" "$output_dir"

compile_swift VKQuickLook "$app_path/Contents/MacOS/VKQuickLook" app AppKit -- "$source_root/App/VKQuickLookApp.swift"
write_app_plist "$app_path/Contents/Info.plist"

mkdir -p "$app_path/Contents/PlugIns/VKThumbnailExtension.appex/Contents/MacOS" "$app_path/Contents/PlugIns/VKPreviewExtension.appex/Contents/MacOS"
compile_swift VKThumbnailExtension "$app_path/Contents/PlugIns/VKThumbnailExtension.appex/Contents/MacOS/VKThumbnailExtension" extension AppKit QuickLookThumbnailing -- "$source_root/Shared/NativeVKRenderer.swift" "$source_root/Shared/RendererService.swift" "$source_root/ThumbnailExtension/ThumbnailProvider.swift"
write_extension_plist "$app_path/Contents/PlugIns/VKThumbnailExtension.appex/Contents/Info.plist" VKThumbnailExtension "${bundle_id_prefix}.thumbnail" VKThumbnailExtension.ThumbnailProvider com.apple.quicklook.thumbnail

compile_swift VKPreviewExtension "$app_path/Contents/PlugIns/VKPreviewExtension.appex/Contents/MacOS/VKPreviewExtension" extension AppKit QuickLookUI -- "$source_root/Shared/NativeVKRenderer.swift" "$source_root/Shared/RendererService.swift" "$source_root/PreviewExtension/PreviewViewController.swift"
write_extension_plist "$app_path/Contents/PlugIns/VKPreviewExtension.appex/Contents/Info.plist" VKPreviewExtension "${bundle_id_prefix}.preview" VKPreviewExtension.PreviewViewController com.apple.quicklook.preview

compile_swift VKQuickLookRender "$cli_path" app AppKit -- "$source_root/Shared/NativeVKRenderer.swift" "$source_root/Shared/RendererService.swift" "$source_root/CLI/VKQuickLookRender.swift"

if [[ "$skip_codesign" == "false" ]]; then
  signing_dir="$output_dir/Signing"
  mkdir -p "$signing_dir"
  app_entitlements="$signing_dir/VKQuickLook.entitlements"
  extension_entitlements="$signing_dir/VKQuickLookExtension.entitlements"
  write_entitlements "$app_entitlements" false
  write_entitlements "$extension_entitlements" true
  for appex in "$app_path"/Contents/PlugIns/*.appex; do
    run codesign --force --sign "$sign_identity" --entitlements "$extension_entitlements" "$appex"
  done
  run codesign --force --sign "$sign_identity" --entitlements "$app_entitlements" "$app_path"
fi

if [[ "$install_app" == "true" ]]; then
  install_target="$HOME/Applications/VKQuickLook.app"
  mkdir -p "$HOME/Applications"
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -d "$install_target" ]]; then
    run pkill -f "$install_target/Contents/PlugIns/VK.*Extension\\.appex" || true
    for appex in "$install_target"/Contents/PlugIns/*.appex; do
      [[ -e "$appex" ]] || continue
      run pluginkit -r "$appex" || true
    done
    run pluginkit -r "$install_target" || true
    if [[ -x "$lsregister" ]]; then
      run "$lsregister" -u "$install_target" || true
    fi
  fi
  rm -rf "$install_target"
  cp -R "$app_path" "$install_target"
  if [[ -x "$lsregister" ]]; then
    run "$lsregister" -f -R -trusted "$install_target" || true
  fi
  run pluginkit -a "$install_target" || true
  for appex in "$install_target"/Contents/PlugIns/*.appex; do
    run pluginkit -a "$appex" || true
  done
  run qlmanage -r || true
  run qlmanage -r cache || true
  echo "Installed $install_target"
fi

echo "Built $app_path"
echo "Built validation CLI $cli_path"
