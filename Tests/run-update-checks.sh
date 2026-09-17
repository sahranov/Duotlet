#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/duotlet-updates.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
"${SWIFTC:-swiftc}" -module-cache-path "${DUOTLET_MODULE_CACHE:-/tmp/duotlet-swift-cache}" \
  Sources/Duotlet/GitHubUpdateChecker.swift Tests/UpdateCheckRegression.swift \
  -o "$scratch/updates"
"$scratch/updates" "$@"
