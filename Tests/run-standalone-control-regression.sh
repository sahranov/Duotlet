#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/duotlet-standalone-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
python3 - "$scratch/Info.plist" <<'PY'
import plistlib, pathlib, sys, uuid
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'app.duotlet.StandaloneRegression.' + uuid.uuid4().hex,
    'DuotletStandalone': True,
}))
PY
swiftc -module-cache-path /tmp/duotlet-swift-cache \
  Sources/Duotlet/ControlState.swift Tests/StandaloneControlRegression.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$scratch/Info.plist" \
  -o "$scratch/check"
"$scratch/check"
