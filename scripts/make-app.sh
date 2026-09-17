#!/usr/bin/env bash
set -euo pipefail

# Builds a release binary and wraps it in a double-clickable "Seating Chart.app".
cd "$(dirname "$0")/.."

APP_NAME="Seating Chart"
EXECUTABLE="SeatingChart"
BUNDLE_ID="com.ningunosound.seatingchart"
VERSION="1.0"
APP="$APP_NAME.app"
ICON_SOURCE="icon/AppIcon.png"
ICNS="icon/AppIcon.icns"

echo "Building release binary..."
swift build -c release --product "$EXECUTABLE"
BIN_PATH="$(swift build -c release --product "$EXECUTABLE" --show-bin-path)"

# Regenerate the icon whenever the artwork is newer than the .icns.
if [[ -f "$ICON_SOURCE" && ( ! -f "$ICNS" || "$ICON_SOURCE" -nt "$ICNS" ) ]]; then
    ./scripts/make-icon.sh
fi

# Assemble in a temporary directory. A synced Desktop keeps re-adding
# com.apple.FinderInfo to new folders, which codesign refuses to sign over.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/$APP"

echo "Assembling ${APP}..."
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

# ditto without extended attributes, for the same reason.
ditto --norsrc --noextattr --noqtn "$BIN_PATH/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"

# The .lproj folders go straight into Contents/Resources, which is both where
# macOS looks for the app's language and what keeps the bundle signable.
for lproj in Sources/SeatingChart/Resources/*.lproj; do
    ditto --norsrc --noextattr --noqtn "$lproj" "$STAGE/Contents/Resources/$(basename "$lproj")"
done

ICON_PLIST_ENTRY=""
if [[ -f "$ICNS" ]]; then
    ditto --norsrc --noextattr --noqtn "$ICNS" "$STAGE/Contents/Resources/AppIcon.icns"
    ICON_PLIST_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>"
else
    echo "note: no $ICNS — building without an app icon." >&2
fi

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>de</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
$ICON_PLIST_ENTRY
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.education</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Seating Chart Data</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.ningunosound.seatingchart.archive</string>
            </array>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.ningunosound.seatingchart.archive</string>
            <key>UTTypeDescription</key>
            <string>Seating Chart Data</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.content</string>
            </array>
            <key>UTTypeIconFile</key>
            <string>AppIcon</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>seatingchart</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/json</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Runs entirely offline. No data leaves this Mac.</string>
</dict>
</plist>
PLIST

echo 'APPL????' > "$STAGE/Contents/PkgInfo"

# Ad-hoc signature so Gatekeeper is happy with a locally built app.
codesign --force --sign - --timestamp=none "$STAGE"
codesign --verify --strict "$STAGE"

rm -rf "$APP"
ditto --norsrc --noqtn "$STAGE" "$APP"
# Refresh Finder's cached icon for the rebuilt bundle.
touch "$APP"
# LaunchServices does not notice a rebuilt bundle on its own, so double-clicking
# a .seatingchart file would keep using the previous registration.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$APP" || true

echo "Built ./$APP"
