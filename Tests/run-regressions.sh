#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Works with Command Line Tools installations that lack Swift Testing.
regression_dir="$(mktemp -d /tmp/duotlet-regressions.XXXXXX)"
trap 'rm -rf "$regression_dir"' EXIT
module_cache="${DUOTLET_MODULE_CACHE:-/tmp/duotlet-swift-cache}"

run() {
  local name="$1"
  shift
  swiftc -module-cache-path "$module_cache" "$@" "Tests/${name}.swift" -o "$regression_dir/$name"
  "$regression_dir/$name"
}

run PerspectiveMotionRegression Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/DepthGeometry.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/EffectRelease.swift
run GeometryRegression Sources/Duotlet/DepthGeometry.swift
run ClosingOnlyRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run EffectReleaseRegression Sources/Duotlet/EffectRelease.swift Sources/Duotlet/BlurEnvelope.swift Sources/Duotlet/BlurGradient.swift
run AdaptiveLidRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run BlurEnvelopeRegression Sources/Duotlet/BlurEnvelope.swift Sources/Duotlet/AdaptiveLidPolicy.swift
run BackgroundLidReaderRegression Sources/Duotlet/BackgroundLidReader.swift
run WakeEffectRegression Sources/Duotlet/WakeEffectRestoration.swift
run ReturnReversalRegression Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/DepthGeometry.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/EffectRelease.swift Sources/Duotlet/PresentationOpacity.swift

run WakePresentationRegression Sources/Duotlet/PresentationReveal.swift Sources/Duotlet/EffectRelease.swift
run ClosingDimmingRegression Sources/Duotlet/ClosingDimming.swift Sources/Duotlet/BlurGradient.swift
run ScreenCapturePermissionRegression Sources/Duotlet/ScreenCapturePermission.swift
