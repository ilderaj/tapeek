#!/bin/sh
set -eu

APP="$HOME/Applications/Tapeek.app"
APP_BUNDLE_ID="com.local.Tapeek"
EXTENSION_BUNDLE_ID="com.local.Tapeek.Preview"
APPEX="$APP/Contents/PlugIns/TapeekPreview.appex"

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

[ -d "$APP" ] && [ ! -L "$APP" ] || fail "Tapeek app is missing or not a regular app directory: $APP"
[ -f "$APP/Contents/Info.plist" ] || fail "Missing app Info.plist: $APP/Contents/Info.plist"
[ -d "$APPEX" ] && [ ! -L "$APPEX" ] || fail "Tapeek preview extension is missing or not a regular directory: $APPEX"
[ -f "$APPEX/Contents/Info.plist" ] || fail "Missing extension Info.plist: $APPEX/Contents/Info.plist"

actual_app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist") || fail "Cannot read app bundle ID: $APP"
actual_extension_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Contents/Info.plist") || fail "Cannot read extension bundle ID: $APPEX"
[ "$actual_app_id" = "$APP_BUNDLE_ID" ] || fail "Unexpected app bundle ID '$actual_app_id' at $APP"
[ "$actual_extension_id" = "$EXTENSION_BUNDLE_ID" ] || fail "Unexpected extension bundle ID '$actual_extension_id' at $APPEX"

run codesign --verify --deep --strict --verbose=2 "$APP"
printf '%s\n' '--- registered Tapeek extension ---'
registered_extensions=$(pluginkit -m -p com.apple.quicklook.preview) || fail "Command failed (exit $?): pluginkit -m -p com.apple.quicklook.preview"
if ! printf '%s\n' "$registered_extensions" | grep -F "$EXTENSION_BUNDLE_ID"; then
  fail "Tapeek extension is not listed by pluginkit: $EXTENSION_BUNDLE_ID"
fi
printf 'Extension path: %s\n' "$APPEX"
printf '%s\n' '--- extension detail and selection state ---'
run pluginkit -m -v -i "$EXTENSION_BUNDLE_ID"

if [ "$#" -gt 1 ]; then
  fail "Usage: $0 [file-to-preview]"
fi
if [ "$#" -eq 1 ]; then
  [ -f "$1" ] || fail "Preview file not found: $1"
  run qlmanage -p "$1"
fi
