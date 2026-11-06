#!/bin/sh
# Installs the plugin for every Hermes profile that browses with your real browser profile
# (browser.use_real_profile), and takes it out of profiles that no longer do. Run it where your
# gateway runs, and again after turning real-profile browsing on or off for a Bot.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${HERMES_HOME:-$HOME/.hermes}
name=usual-browser

copy_into() { # profile home, then the arguments that select it for `hermes`
    home=$1
    shift
    rm -rf "$home/plugins/$name"
    mkdir -p "$home/plugins"
    cp -R "$here" "$home/plugins/$name"
    rm -rf "$home/plugins/$name/__pycache__" "$home/plugins/$name/dashboard/__pycache__"
    hermes "$@" plugins enable "$name" >/dev/null
}

sync_profile() { # profile home, "yes" to keep a copy anyway, then the arguments that select it
    home=$1
    keep=$2
    shift 2
    # A folder Hermes doesn't list as a profile is left alone.
    hermes "$@" plugins list >/dev/null 2>&1 || { echo "Skipped $home: not a profile."; return 0; }
    label=${2:-default}
    if [ "$(hermes "$@" config get browser.use_real_profile 2>/dev/null)" = "true" ]; then
        copy_into "$home" "$@"
        echo "Installed for $label."
    elif [ "$keep" = yes ]; then
        # The dashboard shows the live view and loads plugins from the main folder only. This copy
        # changes nothing for the main Bot, whose browser isn't a real profile.
        copy_into "$home" "$@"
        echo "Installed in $home for the dashboard's live view."
    elif [ -d "$home/plugins/$name" ]; then
        # Its browser flags come back out on the Bot's next browser use; remove it only after that,
        # so none are left behind.
        if grep -q -- '"--' "$home/$name/flags.json" 2>/dev/null; then
            echo "Kept for $label until its Bot uses the browser once more; run this again after that."
        else
            hermes "$@" plugins remove "$name" >/dev/null
            echo "Removed from $label: real-profile browsing is off."
        fi
    fi
}

any=no
for home in "$root"/profiles/*/; do
    [ -d "$home" ] || continue
    sync_profile "${home%/}" no -p "$(basename "$home")"
    if [ -d "${home%/}/plugins/$name" ]; then any=yes; fi
done
sync_profile "$root" "$any"
echo "Restart your gateway (hermes gateway restart) and its dashboard."
