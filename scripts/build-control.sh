#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CONTROL_BUNDLE:?Set CONTROL_BUNDLE to the output .appex path}"
compiler="${SWIFTC:-$(xcrun --find swiftc)}"
sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
mkdir -p "$CONTROL_BUNDLE/Contents/MacOS" "$CONTROL_BUNDLE/Contents/Resources"
cp -R Sources/Duotlet/Resources/*.lproj "$CONTROL_BUNDLE/Contents/Resources/"
cp Resources/PrivacyInfo.xcprivacy "$CONTROL_BUNDLE/Contents/Resources/"
cp Resources/Control/Info.plist "$CONTROL_BUNDLE/Contents/Info.plist"
xcrun actool Resources/Control/Assets.xcassets \
  --compile "$CONTROL_BUNDLE/Contents/Resources" \
  --platform macosx --minimum-deployment-target 26.0 --target-device mac
architectures=("$(uname -m)")
if [[ "${UNIVERSAL:-false}" == true ]]; then architectures=(arm64 x86_64); fi
outputs=()
for arch in "${architectures[@]}"; do
  binary="$CONTROL_BUNDLE/Contents/MacOS/DuotletControl-$arch"
  "$compiler" -O -sdk "$sdk" -target "$arch-apple-macosx26.0" \
    -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/tmp/duotlet-swift-cache}" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -application-extension -parse-as-library -module-name DuotletControl -emit-executable \
    Sources/Duotlet/ControlState.swift Sources/Duotlet/SettingsLanguage.swift Sources/Duotlet/SetDepthEffectIntent.swift \
    Sources/DuotletControl/DuotletControl.swift -o "$binary"
  outputs+=("$binary")
done
if [[ ${#outputs[@]} -eq 1 ]]; then
  mv "${outputs[0]}" "$CONTROL_BUNDLE/Contents/MacOS/DuotletControl"
else
  lipo -create "${outputs[@]}" -output "$CONTROL_BUNDLE/Contents/MacOS/DuotletControl"
  rm "${outputs[@]}"
fi
