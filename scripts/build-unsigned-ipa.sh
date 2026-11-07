#!/bin/bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p build artifacts

build_number="${BUILD_NUMBER:-1}"
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
  printf 'Build number must be numeric, got: %s\n' "$build_number" >&2
  exit 1
fi

# The app target is validated with the host Swift toolchain first. This does
# not boot a simulator or run UI automation.
swift test --package-path "$PWD" 2>&1 | tee build/swift-test.log
swift test --package-path "$PWD" --configuration release 2>&1 | tee build/swift-test-release.log
pod install --deployment 2>&1 | tee build/pod-install.log

xcodebuild \
  -workspace PeachTest.xcworkspace -scheme PeachTest -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  COMPILER_INDEX_STORE_ENABLE=NO ENABLE_PREVIEWS=NO \
  DEBUG_INFORMATION_FORMAT=dwarf \
  "CURRENT_PROJECT_VERSION=${build_number}" \
  build 2>&1 | tee build/xcodebuild.log

app="build/DerivedData/Build/Products/Release-iphoneos/PeachTest.app"
test -d "$app"
stage="$(mktemp -d "$PWD/build/ipa-stage.XXXXXX")"
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/PeachTest.app"
ipa="$PWD/artifacts/Peach-iOS-Test-unsigned.ipa"
ditto -c -k --norsrc --keepParent "$stage/Payload" "$ipa"
python3 scripts/verify-ipa.py "$ipa" | tee artifacts/ipa-validation.json
shasum -a 256 "$ipa" > "artifacts/Peach-iOS-Test-unsigned.ipa.sha256"
{
  printf 'variant=peach-test\n'
  printf 'commit=%s\n' "${CM_COMMIT:-local}"
  printf 'build_number=%s\n' "$build_number"
  printf 'ipa=%s\n' "$(basename "$ipa")"
} | tee artifacts/build-summary.txt
