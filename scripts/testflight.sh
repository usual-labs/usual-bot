#!/bin/sh
# Archives Usual Bot for the Mac and the iPhone, with push, and uploads both to TestFlight.
#
# On your Mac, Xcode signs with the team's distribution certificates and profiles, which it makes
# itself: sign in to the team under Xcode › Settings › Accounts first. The TestFlight workflow
# instead signs with certificates and profiles a maintainer made beforehand, and uploads with an
# individual App Store Connect API key, so nothing it runs can make or change them.
# docs/guides/releasing.md has the rest.
#
# Usage: DEVELOPMENT_TEAM=ABCDE12345 scripts/testflight.sh [--check] [mac|iphone]
#   --check      signs and exports into build/TestFlight without uploading
#   mac, iphone  only that one; both by default
#
# To sign with profiles made beforehand, as the workflow does, also set:
#   SIGNING_PROFILES  a folder holding ios-app.mobileprovision, ios-notifications.mobileprovision,
#                     macos-app.provisionprofile and macos-notifications.provisionprofile. A keychain
#                     must hold the Apple Distribution and Mac Installer Distribution certificates.
#   APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID
#                     an individual API key (the .p8 file and its ID), for the upload
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
profiles="${SIGNING_PROFILES:-}"
mkdir -p "$out"

fail() {
    echo "$1" >&2
    exit 1
}

# Installs a provisioning profile and prints its name, after checking that it's an App Store
# profile for this bundle ID with at least 30 days left.
install_profile() {
    file="$profiles/$1"
    [ -f "$file" ] || fail "$file is missing."
    plist="$out/profile.plist"
    security cms -D -i "$file" > "$plist"
    # iPhone profiles name the app in application-identifier, Mac ones in
    # com.apple.application-identifier.
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist")
    [ "$identifier" = "$team.$2" ] || fail "$1 is for $identifier, not $team.$2."
    if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist" > /dev/null 2>&1; then
        fail "$1 lists devices, so it's a development or ad hoc profile. Make an App Store one."
    fi
    expires=$(plutil -extract ExpirationDate raw -o - "$plist")
    days=$((($(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) - $(date +%s)) / 86400))
    [ "$days" -ge 30 ] ||
        fail "$1 expires on $expires. Make new profiles; docs/guides/releasing.md says how."
    installed="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    mkdir -p "$installed"
    cp "$file" "$installed/$(plutil -extract UUID raw -o - "$plist").${1##*.}"
    plutil -extract Name raw -o - "$plist"
}

if [ -n "$profiles" ]; then
    # The Mac installer certificate is named either way, depending on when it was made.
    installer=$(security find-identity -v -p basic |
        sed -nE 's/.*"((3rd Party Mac Developer Installer|Mac Installer Distribution): [^"]*)".*/\1/p' |
        head -n 1)
    if [ "$destination" = upload ]; then
        key="${APP_STORE_CONNECT_KEY_PATH:?Set APP_STORE_CONNECT_KEY_PATH to the API key (.p8) file.}"
        key_id="${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID too.}"
        # altool reads the key from a folder, and takes a key whose file name starts with ApiKey_
        # as an individual key.
        keys="$PWD/$out/private_keys"
        trap 'rm -rf "$keys"' EXIT
        mkdir -p "$keys"
        cp "$key" "$keys/ApiKey_$key_id.p8"
    fi
fi

for platform in $platforms; do
    case "$platform" in
        mac) generic='generic/platform=macOS' type=macos ext=provisionprofile ;;
        iphone) generic='generic/platform=iOS' type=ios ext=mobileprovision ;;
        *) echo "Pick mac or iphone, not $platform." >&2; exit 64 ;;
    esac
    options="$out/ExportOptions-$platform.plist"
    cat > "$options" <<EOF
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

    # The positional parameters are read; from here they hold how this platform is signed.
    if [ -n "$profiles" ]; then
        app_profile=$(install_profile "$type-app.$ext" "$prefix.UsualBot")
        notifications_profile=$(install_profile "$type-notifications.$ext" \
            "$prefix.UsualBot.NotificationService")
        # Shared.xcconfig and NotificationService.xcconfig give each target its own profile.
        set -- CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Distribution' \
            "USUAL_APP_PROFILE=$app_profile" "USUAL_NOTIFICATIONS_PROFILE=$notifications_profile"
        plutil -replace destination -string export "$options"
        plutil -replace signingStyle -string manual "$options"
        plutil -insert signingCertificate -string 'Apple Distribution' "$options"
        plutil -insert provisioningProfiles -dictionary "$options"
        # The bundle IDs have dots, which plutil's key paths can't take.
        /usr/libexec/PlistBuddy \
            -c "Add :provisioningProfiles:$prefix.UsualBot string $app_profile" \
            -c "Add :provisioningProfiles:$prefix.UsualBot.NotificationService string $notifications_profile" \
            "$options"
        if [ "$platform" = mac ]; then
            [ -n "$installer" ] || fail "No Mac Installer Distribution certificate is in a keychain."
            plutil -insert installerSigningCertificate -string "$installer" "$options"
        fi
    else
        set -- -allowProvisioningUpdates
    fi

    echo "Usual Bot $version ($build) for $platform"
    archive="$out/UsualBot-$platform.xcarchive"
    rm -rf "$archive" "$out/$platform"
    xcodebuild archive -quiet -project UsualBot.xcodeproj -scheme UsualBot -configuration Release \
        -destination "$generic" -archivePath "$archive" "$@" \
        DEVELOPMENT_TEAM="$team" BUNDLE_ID_PREFIX="$prefix" USUAL_PUSH=YES \
        MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build"
    if [ -n "$profiles" ]; then
        xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/$platform" \
            -exportOptionsPlist "$options"
        if [ "$destination" = upload ]; then
            package=$(find "$out/$platform" -maxdepth 1 \( -name '*.ipa' -o -name '*.pkg' \) | head -n 1)
            [ -n "$package" ] || fail "The export made no .ipa or .pkg."
            # altool wants an issuer ID even for an individual key, and ignores it.
            API_PRIVATE_KEYS_DIR="$keys" xcrun altool --upload-app -f "$package" -t "$type" \
                --api-key "$key_id" --api-issuer 00000000-0000-0000-0000-000000000000
        fi
    else
        xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/$platform" \
            -exportOptionsPlist "$options" -allowProvisioningUpdates
    fi
done
