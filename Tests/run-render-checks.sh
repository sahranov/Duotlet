#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
render_dir="$(mktemp -d /tmp/duotlet-render.XXXXXX)"
trap 'rm -rf "$render_dir"' EXIT
for check in BlurRegression RenderBenchmark; do
  swiftc -O -module-cache-path "${DUOTLET_MODULE_CACHE:-/tmp/duotlet-swift-cache}" \
    Sources/Duotlet/DepthUniforms.swift Sources/Duotlet/DepthBlur.swift \
    Sources/Duotlet/DepthShaders.swift "Tests/${check}.swift" -o "$render_dir/$check"
  "$render_dir/$check"
done
