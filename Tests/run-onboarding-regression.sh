#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
regression_dir="$(mktemp -d /tmp/duotlet-onboarding.XXXXXX)"
trap 'rm -rf "$regression_dir"' EXIT
module_cache="${DUOTLET_MODULE_CACHE:-/tmp/duotlet-swift-cache}"

swiftc -module-cache-path "$module_cache" -emit-library -emit-module \
  -module-name TelemetryDeck Tests/Support/TelemetryDeckSpy.swift \
  -emit-module-path "$regression_dir/TelemetryDeck.swiftmodule" \
  -o "$regression_dir/libTelemetryDeck.dylib"
swiftc -module-cache-path "$module_cache" -I "$regression_dir" -L "$regression_dir" \
  -lTelemetryDeck -Xlinker -rpath -Xlinker "$regression_dir" \
  Sources/Duotlet/Preferences.swift Sources/Duotlet/Analytics.swift \
  Sources/Duotlet/ScreenCapturePermission.swift Tests/OnboardingRegression.swift \
  -o "$regression_dir/OnboardingRegression"
"$regression_dir/OnboardingRegression"
