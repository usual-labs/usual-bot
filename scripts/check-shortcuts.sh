#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/usualbot-shortcuts.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT
swiftc -swift-version 6 -parse-as-library App/macOS/HotKey.swift App/macOS/QuickMessageShortcut.swift \
    scripts/fixtures/HotKeyCheck.swift \
    -o "$scratch_dir/check-shortcuts"
"$scratch_dir/check-shortcuts"
