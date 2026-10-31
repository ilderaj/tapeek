#!/bin/sh
set -eu

APP="$HOME/Applications/Tapeek.app"

if [ ! -d "$APP" ]; then
  echo "Tapeek is not installed at $APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

echo "--- registered extension ---"
pluginkit -m -p com.apple.quicklook.preview | grep -F "com.local.Tapeek.Preview"

echo "--- extension detail ---"
pluginkit -m -v -i com.local.Tapeek.Preview
