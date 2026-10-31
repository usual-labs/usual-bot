#!/bin/sh
# Fails on a fixed sleep in tests. Waiting for the event is what keeps a test steady on a slow
# runner, so a sleep needs a `// sleep-ok: <why>` comment on the line above it.
cd "$(dirname "$0")/.." || exit 1

find Packages -type f -path '*/Tests/*' -name '*.swift' -not -path '*/.build/*' -exec awk '
    /Task\.sleep|Thread\.sleep|[^.[:alnum:]]usleep\(/ && !(previous ~ /sleep-ok: *[^ ]/) {
        printf "%s:%d: fixed sleep without a // sleep-ok: reason on the line above\n", FILENAME, FNR
        failed = 1
    }
    { previous = $0 }
    END { exit failed }
' {} + || {
    echo "Wait for the event with waitUntil or waitUntilOnMain, or say why a sleep is right here." >&2
    exit 1
}
