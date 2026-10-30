#!/bin/sh
# The same checks as CI. `scripts/check.sh --fast` skips the two app builds.
set -eu
cd "$(dirname "$0")/.."

swift format lint --strict --recursive App Packages
scripts/check-test-waits.sh
swift test --package-path Packages/HermesKit
swift test --package-path Packages/UsualUI

if [ "${1:-}" != "--fast" ]; then
    xcodebuild build -quiet -project UsualBot.xcodeproj -scheme UsualBot \
        -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
    xcodebuild build -quiet -project UsualBot.xcodeproj -scheme UsualBot \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
fi
