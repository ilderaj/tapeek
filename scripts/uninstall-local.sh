#!/bin/sh
set -eu

DEST="$HOME/Applications/Tapeek.app"

pluginkit -e ignore -i com.local.Tapeek.Preview >/dev/null 2>&1 || true
pluginkit -r "$DEST/Contents/PlugIns/TapeekPreview.appex" >/dev/null 2>&1 || true
rm -rf "$DEST"
qlmanage -r

echo "Uninstalled Tapeek."
