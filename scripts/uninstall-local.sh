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
    return "$status"
  }
}

if [ ! -e "$APP" ] && [ ! -L "$APP" ]; then
  printf 'Tapeek is not installed at %s\n' "$APP"
  exit 0
fi
[ -d "$APP" ] && [ ! -L "$APP" ] || fail "Install path is not a regular app directory; refusing to remove: $APP"
[ -f "$APP/Contents/Info.plist" ] || fail "Missing app Info.plist; refusing to remove: $APP"
[ -f "$APPEX/Contents/Info.plist" ] || fail "Missing Tapeek extension; refusing to remove: $APP"

actual_app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist") || fail "Cannot read app bundle ID; refusing to remove: $APP"
actual_extension_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Contents/Info.plist") || fail "Cannot read extension bundle ID; refusing to remove: $APPEX"
[ "$actual_app_id" = "$APP_BUNDLE_ID" ] || fail "Unexpected app bundle ID '$actual_app_id'; refusing to remove: $APP"
[ "$actual_extension_id" = "$EXTENSION_BUNDLE_ID" ] || fail "Unexpected extension bundle ID '$actual_extension_id'; refusing to remove: $APP"
run codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signature verification failed; refusing to remove: $APP"

# Removing the app must not alter ignore/use choices for any provider.
# Registry cleanup is scoped to this extension path and is best-effort.
if pluginkit -r "$APPEX"; then
  :
else
  status=$?
  printf 'Command failed (exit %s); continuing uninstall:' "$status" >&2
  printf ' %s' pluginkit -r "$APPEX" >&2
  printf '\n' >&2
fi

run rm -r "$APP" || fail "Could not remove verified Tapeek app: $APP"
run qlmanage -r || fail "Tapeek app was removed, but Quick Look cache refresh failed."
printf 'Uninstalled Tapeek from %s. Extension selection state was left unchanged.\n' "$APP"
