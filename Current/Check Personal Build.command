#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodebuild >/dev/null || ! command -v swift >/dev/null; then
  echo "Run this on your Mac with Xcode installed."
  exit 1
fi
mkdir -p verification
build_temp="$(mktemp -d /private/tmp/tender-personal-check.XXXXXX)"
swift test --scratch-path "$build_temp/core" --disable-sandbox 2>&1 | tee verification/swift-core-tests.txt
xcodebuild -project Tender.xcodeproj -scheme Tender -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_temp/derived" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee verification/simulator-build.txt
echo "Core checks and simulator build completed. Run the UI tests from Xcode on a chosen simulator."
echo "This check does not install on your iPhone or deploy the bank backend."
