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
run FastCloseRegression Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/DepthGeometry.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/EffectRelease.swift
run GeometryRegression Sources/Duotlet/DepthGeometry.swift
run ClosingOnlyRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run EffectReleaseRegression Sources/Duotlet/EffectRelease.swift Sources/Duotlet/BlurEnvelope.swift Sources/Duotlet/BlurGradient.swift
run AdaptiveLidRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run LidAdjustmentRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run BlurEnvelopeRegression Sources/Duotlet/BlurEnvelope.swift Sources/Duotlet/AdaptiveLidPolicy.swift Sources/Duotlet/BlurGradient.swift
run ClosingAngleRegression Sources/Duotlet/BlurGradient.swift Sources/Duotlet/BlurEnvelope.swift Sources/Duotlet/ClosingDimming.swift Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/EffectRelease.swift
run BackgroundLidReaderRegression Sources/Duotlet/BackgroundLidReader.swift
run DrawablePrefetchRegression Sources/Duotlet/DrawablePrefetch.swift
run WakeEffectRegression Sources/Duotlet/EffectSession.swift Sources/Duotlet/AdaptiveLidPolicy.swift
run ReturnReversalRegression Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/DepthGeometry.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/EffectRelease.swift Sources/Duotlet/PresentationOpacity.swift

run WakePresentationRegression Sources/Duotlet/PresentationReveal.swift Sources/Duotlet/EffectSession.swift
run WakeContinuityRegression Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/DepthGeometry.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/EffectRelease.swift Sources/Duotlet/ClosingDimming.swift
run ClosingResponseRegression Sources/Duotlet/AdaptiveLidPolicy.swift
run ClosingDimmingRegression Sources/Duotlet/ClosingDimming.swift Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/EffectRelease.swift
run ScreenCapturePermissionRegression Sources/Duotlet/ScreenCapturePermission.swift

run OpeningReleaseRegression Sources/Duotlet/OpeningRelease.swift Sources/Duotlet/EffectRelease.swift Sources/Duotlet/CriticallyDampedSpring.swift Sources/Duotlet/AdaptiveLidPolicy.swift Sources/Duotlet/PerspectiveMotion.swift Sources/Duotlet/DepthGeometry.swift

run OpeningJitterRegression Sources/Duotlet/AdaptiveLidPolicy.swift

bash Tests/run-onboarding-regression.sh
