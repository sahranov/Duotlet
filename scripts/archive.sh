#!/usr/bin/env bash
# Native distribution build: Xcode generates WidgetKit/App Intents metadata.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
archive="${DUOTLET_ARCHIVE:-$PWD/build/Duotlet.xcarchive}"
app_group="${DUOTLET_APP_GROUP:-$DEVELOPMENT_TEAM.app.duotlet.shared}"
xcodebuild -project Duotlet.xcodeproj -scheme Duotlet -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" DUOTLET_APP_GROUP="$app_group" archive "$@"
echo "Archive: $archive"
