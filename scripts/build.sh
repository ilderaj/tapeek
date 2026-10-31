#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project Tapeek.xcodeproj \
  -scheme Tapeek \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
