#!/usr/bin/env bash
# Explicit experimental distribution only. Never installs or launches the app.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 0 ]] || { echo 'Usage: bash scripts/package-experimental.sh' >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
python3 - "$version" <<'PY'
import sys
sys.path.insert(0, 'scripts')
from release_metadata import version_tuple
version_tuple(sys.argv[1])
PY
dist="$PWD/output/experimental/$version"
mkdir -p "$dist"
for suffix in dmg zip; do
  [[ ! -e "$dist/Duotlet-$version.$suffix" ]] || {
    echo "Refusing to overwrite $dist/Duotlet-$version.$suffix" >&2; exit 1;
  }
done

swift build -c release --arch arm64 --arch x86_64 --product Duotlet
bin_path="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
staging="$(mktemp -d /tmp/duotlet-experimental.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Duotlet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Duotlet" "$app/Contents/MacOS/Duotlet"
for resource in "$bin_path"/*.bundle; do
  ditto "$resource" "$app/Contents/Resources/$(basename "$resource")"
done
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns LICENSE NOTICE EXPERIMENTAL.md Resources/PrivacyInfo.xcprivacy "$app/Contents/Resources/"
python3 - "$app/Contents/Info.plist" "$version" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(CFBundleIdentifier='app.duotlet.Duotlet', CFBundleVersion=sys.argv[2],
            CFBundleShortVersionString=sys.argv[2], DuotletStandalone=True)
info.pop('DuotletAppGroup', None)
path.write_bytes(plistlib.dumps(info))
PY

# No App Group or sandbox entitlements: this package has no Control Center extension.
codesign --force --sign - --timestamp=none --options runtime "$app"
codesign --verify --deep --strict --all-architectures "$app"
built_archs="$(lipo -archs "$app/Contents/MacOS/Duotlet")"
for architecture in arm64 x86_64; do
  case " $built_archs " in
    *" $architecture "*) ;;
    *) echo "Missing $architecture binary" >&2; exit 1 ;;
  esac
done
[[ ! -d "$app/Contents/PlugIns" ]]
codesign -d --entitlements :- "$app" 2>/dev/null > "$staging/entitlements.plist"
[[ ! -s "$staging/entitlements.plist" ]]

ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/Duotlet-$version.zip"
mkdir "$staging/image"
mv "$app" "$staging/image/Duotlet.app"
ln -s /Applications "$staging/image/Applications"
cp EXPERIMENTAL.md "$staging/image/READ-ME-FIRST.md"
hdiutil create -volname "Duotlet $version Experimental" -srcfolder "$staging/image" \
  -fs HFS+ -format UDZO "$staging/Duotlet-$version.dmg"
hdiutil verify "$staging/Duotlet-$version.dmg"
mv "$staging/Duotlet-$version.zip" "$staging/Duotlet-$version.dmg" "$dist/"
(
  cd "$dist"
  shasum -a 256 "Duotlet-$version.dmg" "Duotlet-$version.zip" > SHA256SUMS.txt
)
echo "Experimental archives: $dist (not installed or launched)"
