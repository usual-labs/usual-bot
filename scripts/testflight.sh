#!/bin/sh
# Archives Usual Bot for the Mac and the iPhone, with push, and uploads both to TestFlight.
# Xcode signs them with your team's distribution certificates and profiles, which it makes itself:
# sign in to the team under Xcode › Settings › Accounts first, or give it an App Store Connect API
# key as the TestFlight workflow does. docs/guides/releasing.md has the rest.
#
# Usage: DEVELOPMENT_TEAM=ABCDE12345 scripts/testflight.sh [--check] [mac|iphone]
#   --check   signs and exports into build/TestFlight without uploading
#   mac, iphone  only that one; both by default
# With APP_STORE_CONNECT_KEY_PATH (the .p8 file), APP_STORE_CONNECT_KEY_ID and
# APP_STORE_CONNECT_ISSUER_ID set, Xcode signs in with that key instead of an Xcode account.
set -eu
cd "$(dirname "$0")/.."

destination=upload
if [ "${1:-}" = --check ]; then
    destination=export
    shift
fi
platforms="${1:-mac iphone}"
team="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your team ID.}"
# The bundle ID App Store Connect knows the app by.
prefix="${BUNDLE_ID_PREFIX:-labs.usual}"
version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Shared.xcconfig)
# TestFlight wants a larger build number on every upload; the time gives one.
build=$(date -u +%Y%m%d%H%M)
out=build/TestFlight

# The positional parameters are read; from here they hold the API key's sign-in, if there is one.
if [ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]; then
    set -- -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH" \
        -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID too.}" \
        -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID too.}"
else
    set --
fi

mkdir -p "$out"
cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

for platform in $platforms; do
    case "$platform" in
        mac) generic='generic/platform=macOS' ;;
        iphone) generic='generic/platform=iOS' ;;
        *) echo "Pick mac or iphone, not $platform." >&2; exit 64 ;;
    esac
    echo "Usual Bot $version ($build) for $platform"
    archive="$out/UsualBot-$platform.xcarchive"
    rm -rf "$archive" "$out/$platform"
    xcodebuild archive -quiet -project UsualBot.xcodeproj -scheme UsualBot -configuration Release \
        -destination "$generic" -archivePath "$archive" -allowProvisioningUpdates "$@" \
        DEVELOPMENT_TEAM="$team" BUNDLE_ID_PREFIX="$prefix" USUAL_PUSH=YES \
        MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build"
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/$platform" \
        -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates "$@"
done
