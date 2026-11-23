# Sourced by check.sh and testflight.sh, from the repository root. Picks the Xcode in
# .xcode-version: the one CI builds with and TestFlight builds ship from. A different Xcode can
# pass a build CI then fails (Xcode 26 rejected code Xcode 27 took, more than once).
#
# On a runner, where each Xcode is /Applications/Xcode_<version>.app, it selects that one and
# stops if it's missing. On your Mac it uses what's selected and says when that differs.
xcode_wanted=$(cat .xcode-version)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode_$xcode_wanted.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode_$xcode_wanted.app/Contents/Developer"
fi
xcode_found=$(xcodebuild -version | sed -n 's/^Xcode //p')
if [ "$xcode_found" != "$xcode_wanted" ]; then
    if [ -n "${CI:-}" ]; then
        echo "::error::CI needs Xcode $xcode_wanted (.xcode-version) and found $xcode_found." >&2
        exit 1
    fi
    echo "Warning: this is Xcode $xcode_found, and CI and releases use Xcode $xcode_wanted" \
        "(.xcode-version). A build that passes here may fail there." >&2
fi
[ -z "${CI:-}" ] || echo "Xcode $xcode_found, $(swift --version 2>&1 | head -1)"
