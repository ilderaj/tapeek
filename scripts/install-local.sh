#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Tapeek.app"
APPEX="$APP/Contents/PlugIns/TapeekPreview.appex"
DEST="$HOME/Applications/Tapeek.app"

if [ ! -d "$APP" ]; then
  echo "Build product not found: $APP" >&2
  echo "Run ./scripts/build.sh first." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"

codesign --verify --deep --strict --verbose=2 "$DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$DEST"
else
  echo "lsregister not found at $LSREGISTER" >&2
  exit 1
fi

pluginkit -r "$DEST/Contents/PlugIns/TapeekPreview.appex" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/TapeekPreview.appex"

open "$DEST"
qlmanage -r

echo "Installed: $DEST"
echo "Next: pluginkit -m -p com.apple.quicklook.preview | grep com.local.Tapeek.Preview"
