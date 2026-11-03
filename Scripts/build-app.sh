#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/LastCall.app"
CONTENTS="$APP/Contents"
CONFIGURATION="${1:-release}"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product LastCallApp

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ROOT/.build"
# The SwiftPM product is LastCallApp; the bundle's executable is LastCall.
cp "$ROOT/.build/$CONFIGURATION/LastCallApp" "$CONTENTS/MacOS/LastCall"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# The asset catalog and AppIcon.icon become Contents/Resources/Assets.car plus
# AppIcon.icns. Info.plist names the accent color and the icon, so the partial
# plist actool writes is only for reference.
xcrun actool "$ROOT/Resources/Assets.xcassets" "$ROOT/Resources/AppIcon.icon" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --accent-color AccentColor \
    --output-partial-info-plist "$ROOT/.build/assetcatalog-info.plist" \
    --output-format human-readable-text --errors --warnings --notices

/usr/bin/xattr -cr "$APP"
codesign --force --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
