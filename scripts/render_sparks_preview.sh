#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
preview_out="$PWD/artifacts/sparks-preview"
mkdir -p "$preview_out/module-cache" "$preview_out/tmp"
export TMPDIR="$preview_out/tmp"
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -swift-version 5 -target x86_64-apple-macosx11.0 \
  -sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" -module-cache-path "$preview_out/module-cache" \
  Sources/Core/ReplaySparks.swift Sources/UI/ReplaySparkPainter.swift Tests/SparksPreview/main.swift -o "$preview_out/preview"
"$preview_out/preview" "$preview_out"
