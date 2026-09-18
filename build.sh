#!/usr/bin/env bash
#
# Builds Duotlet.app from the SwiftPM package.
#
#   ./build.sh            archive output/Duotlet-build.zip without installing or launching
#   ./build.sh --install  install with a stable Apple signing identity
#   ./build.sh --run      install with a stable identity, then relaunch
#   ./build.sh --universal  include Apple Silicon and Intel
#
# Ad-hoc builds are compile artifacts only. Never replace an authorized app with
# a new ad-hoc build: its cdhash-based identity invalidates Screen Recording access.

set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="Duotlet"
UNIVERSAL=false
export UNIVERSAL

BUILD_ARGS=(-c release)
if [[ -n "${DUOTLET_BUILD_DIR:-}" ]]; then BUILD_ARGS+=(--scratch-path "$DUOTLET_BUILD_DIR"); fi
RUN_APP=false
INSTALL_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) UNIVERSAL=true; BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --install) INSTALL_APP=true ;;
    --run) RUN_APP=true; INSTALL_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

if "$INSTALL_APP"; then
  if [[ "$SIGN_IDENTITY" == - ]]; then
    echo "Installation requires SIGN_IDENTITY for an Apple Development or Developer ID certificate." >&2
    echo "Run ./build.sh without --install/--run to compile only. The installed app is unchanged." >&2
    exit 1
  fi
  BUNDLE="${DUOTLET_BUNDLE:-/Applications/${APP_NAME}.app}"
else
  BUNDLE="$PWD/output/${APP_NAME}.app"
fi
SWIFT="${SWIFT:-$(xcrun --find swift)}"

"$SWIFT" build "${BUILD_ARGS[@]}" --product Duotlet
"$SWIFT" build "${BUILD_ARGS[@]}" --product lidprobe

BIN_PATH="$("$SWIFT" build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/Duotlet"
PROBE="$BIN_PATH/lidprobe"

# Build in the workspace first; only replace an installed app after all builds succeed.
STAGING="$(mktemp -d /tmp/duotlet-package.XXXXXX)/Duotlet.app"
DESTINATION="$BUNDLE"
BUNDLE="$STAGING"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Duotlet"
cp "$PROBE" "$BUNDLE/Contents/MacOS/lidprobe"
# SwiftPM resolves Bundle.module relative to the application bundle.
for resource in "$BIN_PATH"/*.bundle; do
  cp -R "$resource" "$BUNDLE/Contents/Resources/"
done
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp LICENSE NOTICE Resources/PrivacyInfo.xcprivacy "$BUNDLE/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

CONTROL_BUNDLE="$BUNDLE/Contents/PlugIns/DuotletControl.appex" bash scripts/build-control.sh

TIMESTAMP=--timestamp
if [[ "$SIGN_IDENTITY" == - ]]; then
  TIMESTAMP=--timestamp=none
fi
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" \
  "$BUNDLE/Contents/MacOS/lidprobe"
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" \
  --entitlements Resources/Control/DuotletControl.entitlements "$BUNDLE/Contents/PlugIns/DuotletControl.appex"
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" \
  --entitlements Resources/Duotlet.entitlements "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"

if ! "$INSTALL_APP"; then
  mkdir -p output
  ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "output/${APP_NAME}-build.zip"
  rm -rf "$(dirname "$STAGING")"
  echo "built output/${APP_NAME}-build.zip (not installed or launched)"
  exit 0
fi

if "$INSTALL_APP"; then
  python3 scripts/verify-install-identity.py "$BUNDLE" "$DESTINATION"
fi
mkdir -p "$(dirname "$DESTINATION")"
# Keep one recoverable copy when replacing an existing installation.
if [[ -d "$DESTINATION" ]]; then
  mkdir -p output/app-backups
  ditto -c -k --sequesterRsrc --keepParent "$DESTINATION" "output/app-backups/Duotlet-$(date +%Y%m%d-%H%M%S).zip"
fi
rm -rf "$DESTINATION"
ditto "$BUNDLE" "$DESTINATION"
rm -rf "$(dirname "$STAGING")"
BUNDLE="$DESTINATION"
echo "built ${BUNDLE}"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

if "$RUN_APP"; then
  pkill -x Duotlet 2>/dev/null || true
  sleep 0.5
  open "$BUNDLE"
  echo "launched"
fi
