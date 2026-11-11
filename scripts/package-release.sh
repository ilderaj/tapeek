#!/bin/sh
# Build dist/Tapeek-<version>.{zip,dmg} + SHA256SUMS; --force replaces this version.
# Version comes from project.yml via the built app's Info.plist.
# Default: ad-hoc signed, not notarized.
# SIGN_IDENTITY enables Developer ID re-signing with hardened runtime + timestamp.
# NOTARY_PROFILE enables notarization via a keychain profile (requires SIGN_IDENTITY).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FORCE=0
case "$#" in
  0) ;;
  1) if [ "$1" = "--force" ]; then FORCE=1; else
       echo "usage: $0 [--force]" >&2; exit 1
     fi ;;
  *) echo "usage: $0 [--force]" >&2; exit 1 ;;
esac

IDENTITY="${SIGN_IDENTITY:--}"
if [ "${NOTARY_PROFILE+x}" = x ]; then
  if [ -z "$NOTARY_PROFILE" ] || [ "$IDENTITY" = "-" ]; then
    echo "error: NOTARY_PROFILE requires a nonempty profile and a non-ad-hoc SIGN_IDENTITY" >&2
    exit 1
  fi
fi

DERIVED=".build/DerivedDataRelease"
APP_SRC="$DERIVED/Build/Products/Release/Tapeek.app"
DIST="$ROOT/dist"

./scripts/generate.sh

# Always compile ad-hoc; Developer ID signing is performed explicitly below.
xcodebuild -project Tapeek.xcodeproj -scheme Tapeek -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build

[ -d "$APP_SRC" ] || { echo "error: $APP_SRC not found" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist")"
case "$VERSION" in
  ''|*[!0-9.]*) echo "error: version must have the form digits.digits.digits" >&2; exit 1 ;;
esac
if ! printf '%s\n' "$VERSION" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: version must have the form digits.digits.digits" >&2
  exit 1
fi

ZIP_NAME="Tapeek-$VERSION.zip"
DMG_NAME="Tapeek-$VERSION.dmg"
for name in "$ZIP_NAME" "$DMG_NAME"; do
  if { [ -e "$DIST/$name" ] || [ -L "$DIST/$name" ]; } && [ "$FORCE" -ne 1 ]; then
    echo "error: dist/$name already exists; use --force to replace this version" >&2
    exit 1
  fi
done

echo "Packaging Tapeek $VERSION"
mkdir -p "$ROOT/.build"
STAGE="$(mktemp -d "$ROOT/.build/package-$VERSION.XXXXXX")"
trap 'rm -rf "$STAGE"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$STAGE/dmg"

APP="$STAGE/Tapeek.app"
ditto "$APP_SRC" "$APP"
APPEX="$APP/Contents/PlugIns/TapeekPreview.appex"
[ -d "$APPEX" ] || { echo "error: missing $APPEX" >&2; exit 1; }

if [ "$IDENTITY" != "-" ]; then
  echo "Re-signing with Developer ID (hardened runtime)"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    --entitlements "$ROOT/TapeekPreview/TapeekPreview.entitlements" "$APPEX"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    --entitlements "$ROOT/TapeekApp/TapeekApp.entitlements" "$APP"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Notarizing"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/notarize.zip"
    xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$STAGE/notarize.zip"
  fi
fi

codesign --verify --deep --strict "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  # Preserve the stapled ticket; sequester metadata for Archive Utility/ditto extraction.
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$ZIP_NAME"
  ditto -x -k "$STAGE/$ZIP_NAME" "$STAGE/notarized-check"
  codesign --verify --deep --strict "$STAGE/notarized-check/Tapeek.app"
  xcrun stapler validate "$STAGE/notarized-check/Tapeek.app"
  ditto "$APP" "$STAGE/dmg/Tapeek.app"
else
  # Omit AppleDouble entries that plain unzip would extract as files, breaking the seal.
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP" "$STAGE/$ZIP_NAME"
  ditto --noextattr --noqtn --noacl "$APP" "$STAGE/dmg/Tapeek.app"
fi
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname Tapeek -srcfolder "$STAGE/dmg" -ov -format UDZO "$STAGE/$DMG_NAME"
hdiutil verify "$STAGE/$DMG_NAME"

# Retain checksums for other versions, replacing only this version's entries.
if [ -f "$DIST/SHA256SUMS" ]; then
  LC_ALL=C awk -v zip="$ZIP_NAME" -v dmg="$DMG_NAME" \
    '$2 != zip && $2 != dmg' "$DIST/SHA256SUMS" > "$STAGE/SHA256SUMS"
else
  : > "$STAGE/SHA256SUMS"
fi
(cd "$STAGE" && shasum -a 256 "$ZIP_NAME" "$DMG_NAME" >> SHA256SUMS)

# Publish only after packaging and verification succeed; preserve other dist files.
mkdir -p "$DIST"
mv -f "$STAGE/$ZIP_NAME" "$DIST/$ZIP_NAME"
mv -f "$STAGE/$DMG_NAME" "$DIST/$DMG_NAME"
mv -f "$STAGE/SHA256SUMS" "$DIST/SHA256SUMS"

echo "Done:"
ls -lh "$DIST/$ZIP_NAME" "$DIST/$DMG_NAME" "$DIST/SHA256SUMS"
