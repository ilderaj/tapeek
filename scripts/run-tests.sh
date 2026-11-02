#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRATCH_PATH="${TAPEEK_SCRATCH_PATH:-.build/agent-perf}"

echo "== Tapeek Core tests =="
TAPEEK_REQUIRE_LARGE=1 swift test --package-path Packages/TapeekCore --scratch-path "$SCRATCH_PATH"

echo "== Fixture manifest check (large samples required) =="
python3 -I scripts/make-fixtures.py --check --require-large

if command -v swiftlint >/dev/null 2>&1; then
    echo "== swiftlint (non-blocking) =="
    swiftlint lint --quiet || true
else
    echo "== swiftlint not installed; skipped =="
fi
