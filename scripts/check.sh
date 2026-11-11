#!/bin/sh
# The same checks as CI, which runs each part as its own job.
#
# Usage: scripts/check.sh [--fast | macos | ios]
#   (nothing)  everything: lint, the checks, both test suites and both app builds
#   --fast     everything but the two app builds
#   macos, ios only that app build
set -eu
cd "$(dirname "$0")/.."

checks() {
    swift format lint --strict --recursive App NotificationService ShareExtension Packages scripts/fixtures
    scripts/check-test-waits.sh
    scripts/check-shortcuts.sh
    swift test --package-path Packages/HermesKit
    swift test --package-path Packages/UsualUI
}

build() {
    xcodebuild build -quiet -project UsualBot.xcodeproj -scheme UsualBot \
        -destination "generic/platform=$1" CODE_SIGNING_ALLOWED=NO
}

case "${1:-}" in
    '') checks; build macOS; build 'iOS Simulator' ;;
    --fast) checks ;;
    macos) build macOS ;;
    ios) build 'iOS Simulator' ;;
    *) echo "Pick --fast, macos or ios, not $1." >&2; exit 64 ;;
esac
