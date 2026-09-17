#!/bin/zsh
# Builds a clean Release of Calendar Time Logger and packages it as a DMG.
#
#   scripts/package-dmg.sh            → dist/Calendar-Time-Logger-v<version>.dmg
#
# Steps: clean Release build → verify the app bundle → stage the app, an
# Applications shortcut, and the background → create a read/write image →
# lay out the Finder window → compress → verify → checksum.
#
# Signing: the app is signed with whatever identity the Xcode project uses.
# With a Developer ID Application certificate and notarization credentials,
# sign and notarize the DMG as described in Documentation/Releases/RELEASE.md;
# this script does not notarize.
#
# Laying out the window uses Finder via AppleScript. macOS may ask once to
# allow your terminal to control Finder.
set -euo pipefail

ROOT="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
PROJECT="$ROOT/calender_time_logger/calender_time_logger.xcodeproj"
SCHEME="calender_time_logger"
DERIVED="$ROOT/.build/Package"
DIST="$ROOT/dist"
APP_NAME="Calendar Time Logger"
BUNDLE_ID="abirbarman.calender-time-logger"
VOLUME_NAME="Calendar Time Logger"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ctl-dmg.XXXXXX")"
MOUNT=""

step() { print -P "\n%F{blue}==>%f %B$1%b" }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1 }
trap 'print -P "%F{red}error:%f command failed at line $LINENO" >&2' ZERR
cleanup() {
  if [[ -n "$MOUNT" && -d "$MOUNT" ]]; then hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

[[ -d "/Volumes/$VOLUME_NAME" ]] && fail "/Volumes/$VOLUME_NAME is already mounted. Eject it and try again."

step "Clean Release build"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates clean build > "$WORK/build.log" 2>&1 \
  || { grep -E "error:" "$WORK/build.log" | head -20; fail "Release build failed (log: $WORK/build.log)"; }
grep -E "warning:" "$WORK/build.log" | sort -u || true
print "Release build succeeded."

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"

step "Verify the app bundle"
[[ -d "$APP" ]] || fail "missing $APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$ID" == "$BUNDLE_ID" ]] || fail "unexpected bundle identifier $ID"
codesign --verify --deep --strict "$APP" || fail "code signature is invalid"
[[ "$(strings "$APP/Contents/MacOS/$APP_NAME" | grep -c demoState || true)" == "0" ]] || fail "DEBUG demo code found in the Release binary"
[[ -f "$APP/Contents/Resources/AppIcon.icns" || -f "$APP/Contents/Resources/Assets.car" ]] || fail "app icon missing"
if find "$APP" \( -name "*.dSYM" -o -name "*.swiftmodule" -o -name "*.swiftdoc" \) | grep -q .; then fail "debug artifacts inside the app bundle"; fi
AUTHORITY="$( { codesign -dvv "$APP" 2>&1 || true; } | awk -F= '/^Authority=/ { print $2; exit }')"
print "Bundle: $ID  Version: $VERSION ($BUILD)"
print "Signed by: ${AUTHORITY:-ad hoc}"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  print -P "%F{yellow}note:%f development-signed (get-task-allow present). Distribute outside this Mac only after Developer ID signing and notarization."
fi

DMG_NAME="Calendar-Time-Logger-v$VERSION.dmg"

step "Stage installer contents"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
swift "$ROOT/scripts/dmg/render-background.swift" "$WORK/background" > /dev/null
tiffutil -cathidpicheck "$WORK/background/background.png" "$WORK/background/background@2x.png" -out "$STAGE/.background/background.tiff" > /dev/null 2>&1
# Volume icon, built from the same icon PNGs as the app (the app stores its icon in Assets.car).
ICONSET="$WORK/VolumeIcon.iconset"
ICONS="$ROOT/calender_time_logger/calender_time_logger/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  cp "$ICONS/icon_$size.png" "$ICONSET/icon_${size}x${size}.png"
  cp "$ICONS/icon_$((size * 2)).png" "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns"

step "Create and lay out the disk image"
RW="$WORK/rw.dmg"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 60m "$RW"
MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -Eo '/Volumes/.+$' | tail -1)"
[[ -d "$MOUNT" ]] || fail "could not mount the read/write image"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {180, 220}
    set position of item "Applications" of container window to {480, 220}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# The volume icon goes in after Finder has laid out the window: hdiutil's
# -srcfolder copy and the Finder pass both lose .VolumeIcon.icns. A missing icon
# fails the build instead of shipping a generic disk icon.
cp "$STAGE/.VolumeIcon.icns" "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT" || fail "couldn't set the volume's custom icon (SetFile)"
[[ -f "$MOUNT/.VolumeIcon.icns" ]] || fail "volume icon missing from the image"
rm -rf "$MOUNT/.fseventsd"
sync
sleep 1
[[ -f "$MOUNT/.DS_Store" ]] || fail "Finder didn't save the window layout (.DS_Store missing)"
hdiutil detach "$MOUNT" -quiet
MOUNT=""

step "Compress and verify"
mkdir -p "$DIST"
rm -f "$DIST/$DMG_NAME" "$DIST/$DMG_NAME.sha256"
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DIST/$DMG_NAME"
hdiutil verify -quiet "$DIST/$DMG_NAME" || fail "DMG verification failed"
(cd "$DIST" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")

print ""
print "Created $DIST/$DMG_NAME"
print "  version $VERSION ($BUILD), $(du -h "$DIST/$DMG_NAME" | cut -f1)"
print "  sha256 $(cut -d' ' -f1 "$DIST/$DMG_NAME.sha256")"
