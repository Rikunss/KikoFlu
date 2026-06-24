#!/bin/bash
#
# iOS unsigned IPA build script — optimized for GitHub Actions CI
#
# In CI (GITHUB_ACTIONS=true):
#   - Skips flutter clean (clean runner every time)
#   - Skips pod repo update (CI runners have fresh specs)
#   - Uses parallel xcodebuild
#
# Local usage:
#   bash build_ios_xcode.sh

set -e

# ── Detect CI ──
CI_MODE=false
if [ "${GITHUB_ACTIONS}" = "true" ]; then
  CI_MODE=true
fi

# ── Config ──
ARCH=${ARCH:-arm64}
XCODE_WORKSPACE="ios/Runner.xcworkspace"
XCODE_SCHEME="Runner"
XCODE_ARCHIVE="ios/build/Runner.xcarchive"
OUTPUT_IPA="KikoFlu-unsigned.ipa"

log()  { echo "[$1] $2"; }
title(){ echo ""; echo "━━━ $1 ━━━"; echo ""; }

title "iOS unsigned IPA build"
if [ "$CI_MODE" = true ]; then
  echo "  Mode: CI (GitHub Actions)"
else
  echo "  Mode: Local"
fi
echo "  Arch: $ARCH"

# ── Dependencies ──
title "Checking dependencies"
command -v flutter >/dev/null 2>&1 || { echo "ERROR: Flutter not found"; exit 1; }
command -v pod >/dev/null 2>&1     || { echo "ERROR: CocoaPods not found"; exit 1; }
echo "  flutter, pod — OK"

# ── Clean (local only) ──
if [ "$CI_MODE" = false ]; then
  title "Clean"
  flutter clean
  rm -rf ios/Pods ios/Podfile.lock
else
  echo "  (CI: skip clean — fresh environment)"
fi

# ── Flutter dependencies ──
title "Flutter pub get"
flutter pub get

# ── CocoaPods ──
title "Installing CocoaPods"
cd ios
if [ "$CI_MODE" = true ]; then
  # CI: skip repo update — runners have fresh specs, but fallback if not
  pod install --no-repo-update 2>/dev/null || pod install
else
  pod install
fi
cd ..

# ── Xcode build ──
title "Building unsigned archive"
xcodebuild \
  -workspace "$XCODE_WORKSPACE" \
  -scheme "$XCODE_SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -archivePath "$XCODE_ARCHIVE" \
  -arch "$ARCH" \
  -parallelizeTargets \
  -derivedDataPath "ios/build/DerivedData" \
  archive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  PROVISIONING_PROFILE="" \
  ONLY_ACTIVE_ARCH=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  COMPILER_PARALLELIZE_TARGETS=NO

# ── Verify archive ──
if [ ! -d "$XCODE_ARCHIVE" ]; then
  echo "ERROR: Archive not found at $XCODE_ARCHIVE"
  exit 1
fi
echo "  Archive created successfully"

# ── Package IPA ──
title "Packaging unsigned IPA"
rm -rf build/Payload
rm -f "$OUTPUT_IPA"
mkdir -p build/Payload
cp -r "$XCODE_ARCHIVE/Products/Applications/Runner.app" build/Payload/

cd build
zip -qr "$OUTPUT_IPA" Payload
cd ..
mv "build/$OUTPUT_IPA" ./

# ── Verify ──
if [ -f "$OUTPUT_IPA" ]; then
  title "Done"
  echo "  $OUTPUT_IPA"
  ls -lh "$OUTPUT_IPA"
  echo ""
  echo "  Self-sign with: AltStore / Sideloadly / iOS App Signer"
else
  echo "ERROR: IPA packaging failed"
  exit 1
fi
