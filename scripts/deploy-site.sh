#!/bin/sh
# Build and deploy the website in website/ to tapeek.paymond.me.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/website"

if ! command -v cf >/dev/null 2>&1; then
  echo "cf CLI not found. Install it first: https://developers.cloudflare.com/workers/wrangler/" >&2
  exit 1
fi

if [ ! -d node_modules ]; then
  npm install
fi

cf deploy "$@"
