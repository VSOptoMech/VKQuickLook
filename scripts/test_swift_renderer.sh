#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repo_root/macos/QuickLook/Sources"
build_dir="${TMPDIR:-/tmp}/vkquicklook-swift-tests"
mkdir -p "$build_dir"

sdk="$(xcrun --show-sdk-path)"
arch="$(uname -m)"
target="${arch}-apple-macosx13.0"
binary="$build_dir/VKQuickLookRendererTests"

# Compile the test harness with the production renderer and preview controller.
# This keeps the regression tests independent of Xcode projects.
run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

run swiftc \
  -sdk "$sdk" \
  -target "$target" \
  -module-name VKQuickLookRendererTests \
  -o "$binary" \
  -framework AppKit \
  -framework QuickLookUI \
  "$source_root/Shared/NativeVKRenderer.swift" \
  "$source_root/Shared/RendererService.swift" \
  "$source_root/PreviewExtension/PreviewViewController.swift" \
  "$source_root/Test/VKQuickLookRendererTests.swift"

run "$binary"
