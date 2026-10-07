#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p artifacts/fixtures/module-cache artifacts/fixtures/data
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fixture_swift="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    fixture_sdk="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
else
    fixture_swift=$(xcrun --find swiftc)
    fixture_sdk=$(xcrun --show-sdk-path)
fi
mkdir -p artifacts/fixtures/tmp
export TMPDIR="$PWD/artifacts/fixtures/tmp"
LC_ALL=C /usr/bin/shasum -a 256 Sources/Core/*.swift Tests/main.swift > artifacts/fixtures/fixture-input.SHA256SUMS
"$fixture_swift" -swift-version 5 -target x86_64-apple-macosx11.0 -sdk "$fixture_sdk" -module-cache-path artifacts/fixtures/module-cache \
    Sources/Core/*.swift \
    Tests/main.swift -o artifacts/fixtures/travel-fixtures
artifacts/fixtures/travel-fixtures artifacts/fixtures/data
