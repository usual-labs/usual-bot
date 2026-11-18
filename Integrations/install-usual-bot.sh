#!/bin/sh
# Installs the usual-bot plugin for every Hermes profile on this machine, and takes out the two it
# replaces (usual-push and usual-browser). Run it where your gateway runs, and again after adding a
# profile. It sits outside the plugin's folder: Hermes scans that folder when Usual Bot installs it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)/usual-bot
root=${HERMES_HOME:-$HOME/.hermes}
name=usual-bot

install_into() { # profile home, then the arguments that select it for `hermes`
    home=$1
    shift
    # A folder Hermes doesn't list as a profile is left alone.
    hermes "$@" plugins list >/dev/null 2>&1 || { echo "Skipped $home: not a profile."; return 0; }
    rm -rf "$home/plugins/$name"
    mkdir -p "$home/plugins"
    cp -R "$here" "$home/plugins/$name"
    rm -rf "$home/plugins/$name/tests"
    find "$home/plugins/$name" -name __pycache__ -type d -prune -exec rm -rf {} +
    hermes "$@" plugins enable "$name" >/dev/null
    # Their settings stay where they were, and this plugin reads them from there: your devices,
    # and the browser flags the old plugin wrote, which come back out when a Bot stops using them.
    for old in usual-push usual-browser; do
        if [ -d "$home/plugins/$old" ]; then hermes "$@" plugins remove "$old" >/dev/null || true; fi
    done
    echo "Installed for ${2:-default}."
}

install_into "$root"
for home in "$root"/profiles/*/; do
    [ -d "$home" ] || continue
    install_into "${home%/}" -p "$(basename "$home")"
done
echo "Restart your gateway (hermes gateway restart), and its dashboard if you run one."
