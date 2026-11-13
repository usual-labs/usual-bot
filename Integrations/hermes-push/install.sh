#!/bin/sh
# Installs the plugin for every Hermes profile on this machine. Run it where your gateway runs.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${HERMES_HOME:-$HOME/.hermes}

install_into() { # profile home, then the arguments that select it for `hermes`
    home=$1
    shift
    # A folder Hermes doesn't list as a profile is left alone.
    hermes "$@" plugins list >/dev/null 2>&1 || { echo "Skipped $home: not a profile."; return 0; }
    rm -rf "$home/plugins/usual-push"
    mkdir -p "$home/plugins"
    cp -R "$here" "$home/plugins/usual-push"
    rm -rf "$home/plugins/usual-push/tests"
    hermes "$@" plugins enable usual-push
}

install_into "$root"
for home in "$root"/profiles/*/; do
    [ -d "$home" ] || continue
    install_into "${home%/}" -p "$(basename "$home")"
done
echo "Installed. Restart your gateway and its dashboard, then open Settings > Notifications in Usual Bot."
