#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Tapeek.app"
DEST="$HOME/Applications/Tapeek.app"
APP_BUNDLE_ID="com.local.Tapeek"
EXTENSION_BUNDLE_ID="com.local.Tapeek.Preview"
APPEX_RELATIVE_PATH="Contents/PlugIns/TapeekPreview.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

run() {
  "$@" || {
    status=$?
    printf 'Command failed (exit %s):' "$status" >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    exit "$status"
  }
}

check_bundle_ids() {
  app_path=$1
  [ -d "$app_path" ] || fail "App bundle not found: $app_path"
  [ -f "$app_path/Contents/Info.plist" ] || fail "Missing app Info.plist: $app_path/Contents/Info.plist"
  [ -f "$app_path/$APPEX_RELATIVE_PATH/Contents/Info.plist" ] || fail "Missing Tapeek preview extension: $app_path/$APPEX_RELATIVE_PATH"

  actual_app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist") || fail "Cannot read app bundle ID: $app_path"
  actual_extension_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/$APPEX_RELATIVE_PATH/Contents/Info.plist") || fail "Cannot read extension bundle ID: $app_path/$APPEX_RELATIVE_PATH"
  [ "$actual_app_id" = "$APP_BUNDLE_ID" ] || fail "Unexpected app bundle ID at $app_path: $actual_app_id (expected $APP_BUNDLE_ID)"
  [ "$actual_extension_id" = "$EXTENSION_BUNDLE_ID" ] || fail "Unexpected extension bundle ID at $app_path/$APPEX_RELATIVE_PATH: $actual_extension_id (expected $EXTENSION_BUNDLE_ID)"
}

[ -d "$APP" ] || fail "Build product not found: $APP. Run ./scripts/build.sh first."
check_bundle_ids "$APP"
run codesign --verify --deep --strict --verbose=2 "$APP"

if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  [ -d "$DEST" ] || fail "Install destination exists and is not an app directory; refusing to replace: $DEST"
  check_bundle_ids "$DEST"
  run codesign --verify --deep --strict --verbose=2 "$DEST"
  [ ! -L "$DEST" ] || fail "Install destination is a symbolic link; refusing to replace: $DEST"
else
  run mkdir -p "$HOME/Applications"
fi

[ -x "$LSREGISTER" ] || fail "lsregister not found or not executable: $LSREGISTER"

# Replace only a verified Tapeek bundle. Keep the old copy recoverable until
# the validated build has been copied and verified at the destination.
if [ -e "$DEST" ]; then
  BACKUP="$HOME/Applications/.Tapeek.app.previous.$$"
  [ ! -e "$BACKUP" ] || fail "Backup path already exists; refusing to continue: $BACKUP"
  run mv "$DEST" "$BACKUP"
fi

if ditto "$APP" "$DEST"; then
  :
else
  status=$?
  printf 'Command failed (exit %s): ditto %s %s\n' "$status" "$APP" "$DEST" >&2
  if [ -e "${BACKUP:-}" ] && [ ! -e "$DEST" ]; then
    mv "$BACKUP" "$DEST" || printf 'Could not restore previous Tapeek app from %s\n' "$BACKUP" >&2
  fi
  exit "$status"
fi
if check_bundle_ids "$DEST" && codesign --verify --deep --strict --verbose=2 "$DEST"; then
  :
else
  status=$?
  printf 'Copied Tapeek app failed validation (exit %s): %s\n' "$status" "$DEST" >&2
  if [ -e "${BACKUP:-}" ]; then
    FAILED="$HOME/Applications/.Tapeek.app.failed.$$"
    if [ -e "$FAILED" ]; then
      printf 'Failed-copy quarantine path already exists: %s\n' "$FAILED" >&2
      exit 1
    fi
    mv "$DEST" "$FAILED" || printf 'Could not move failed copy out of the install path: %s\n' "$DEST" >&2
    mv "$BACKUP" "$DEST" || printf 'Could not restore previous Tapeek app from %s\n' "$BACKUP" >&2
  fi
  exit 1
fi

run "$LSREGISTER" -f "$DEST"
# A previous build may have registered the DerivedData copy under the same
# bundle ID. Remove that stale registration so the installed copy is used.
BUILD_APPEX="$ROOT/.build/DerivedData/Build/Products/Debug/Tapeek.app/$APPEX_RELATIVE_PATH"
if [ -d "$BUILD_APPEX" ]; then
  pluginkit -r "$BUILD_APPEX" >/dev/null 2>&1 || true
fi
run pluginkit -a "$DEST/$APPEX_RELATIVE_PATH"
run open "$DEST"
run qlmanage -r

if [ -n "${BACKUP:-}" ] && [ -e "$BACKUP" ]; then
  run rm -r "$BACKUP"
fi

printf 'Installed: %s\n' "$DEST"
printf 'Next: pluginkit -m -p com.apple.quicklook.preview | grep -F %s\n' "$EXTENSION_BUNDLE_ID"
