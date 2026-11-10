#!/bin/sh
# Prints the changelog entries of the pull requests merged since the last release tag, grouped
# under Added, Changed and Fixed and wrapped for CHANGELOG.md. Entries live in each pull request's
# "## Changelog" section, not in the file: when every pull request added to the same list, each
# merge left the other open ones in conflict.
#
# Usage: scripts/changelog.sh
#   Run it on the commit you're releasing. It needs `gh`, signed in. Pull requests without an
#   entry or "None", text it didn't use, and commits without a pull request are listed on stderr
#   to check by hand.
set -eu
cd "$(dirname "$0")/.."

since=$(git describe --tags --abbrev=0)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git log --first-parent --reverse --format=%s "$since..HEAD" | while IFS= read -r subject; do
    pr=$(printf '%s\n' "$subject" | sed -n \
        -e 's/.*(#\([0-9][0-9]*\))$/\1/p' \
        -e 's/^Merge pull request #\([0-9][0-9]*\) .*/\1/p')
    if [ -z "$pr" ]; then
        printf '  %s\n' "$subject" >> "$work/direct"
        continue
    fi
    body=$(gh pr view "$pr" --json body --jq .body < /dev/null)
    printf '%s\n' "$body" | tr -d '\r' | awk -v pr="$pr" -v dir="$work" '
        # Drops HTML comments, which may span lines: the template explains itself in one.
        function uncommented(s,    out, at) {
            out = ""
            while (1) {
                if (commented) {
                    at = index(s, "-->")
                    if (!at) return out
                    s = substr(s, at + 3)
                    commented = 0
                }
                at = index(s, "<!--")
                if (!at) return out s
                out = out substr(s, 1, at - 1)
                s = substr(s, at + 4)
                commented = 1
            }
        }
        function trimmed(s) {
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            return s
        }
        # GitHub shows a line break in a description as one, so entries arrive as long lines.
        function wrapped(text, indent,    pad, count, words, i, line, out) {
            pad = substr("                    ", 1, indent)
            count = split(text, words, / +/)
            line = pad "- " words[1]
            for (i = 2; i <= count; i++) {
                if (length(line) + 1 + length(words[i]) > 100) {
                    out = out line "\n"
                    line = pad "  " words[i]
                } else {
                    line = line " " words[i]
                }
            }
            return out line "\n"
        }
        function finish_entry() {
            if (entry != "") {
                entries[section] = entries[section] wrapped(entry, indent)
                kept = 1
            }
            entry = ""
        }
        {
            line = uncommented($0)
            if (line ~ /^## /) {
                finish_entry()
                inside = (tolower(trimmed(line)) ~ /^## +changelog$/)
                if (inside) found = 1
                section = ""
                next
            }
            if (!inside) next
            if (line ~ /^### /) {
                finish_entry()
                section = tolower(trimmed(substr(line, 5)))
                if (section != "added" && section != "changed" && section != "fixed") {
                    section = "unused"
                    odd = 1
                }
                next
            }
            if (line ~ /^[ \t]*$/) {
                after_blank = 1
                next
            }
            if (section == "") {
                if (tolower(trimmed(line)) ~ /^(none|n\/a)/) none = 1
                else odd = 1
            } else if (section != "unused" && line ~ /^ *[-*] /) {
                finish_entry()
                indent = match(line, /[-*]/) - 1
                entry = trimmed(substr(line, indent + 3))
            } else if (section != "unused" && entry != "" && (!after_blank || line ~ /^  /)) {
                entry = entry " " trimmed(line)
            } else {
                # Text after the entries, such as a footer below the last section.
                finish_entry()
                section = "unused"
            }
            after_blank = 0
        }
        END {
            finish_entry()
            for (section in entries) {
                if (section != "unused") printf "%s", entries[section] >> (dir "/" section)
            }
            if (!kept && !none) print "#" pr >> (dir "/missing")
            if (odd) print "#" pr >> (dir "/odd")
        }
    '
done

for section in Added Changed Fixed; do
    file=$work/$(printf '%s' "$section" | tr '[:upper:]' '[:lower:]')
    if [ -s "$file" ]; then
        printf '### %s\n\n' "$section"
        cat "$file"
        echo
    fi
done

listed() { tr '\n' ' ' < "$1" | sed 's/ $//'; }
if [ -s "$work/missing" ]; then
    echo "No changelog entry or \"None\": $(listed "$work/missing"). Write one if users would notice." >&2
fi
if [ -s "$work/odd" ]; then
    echo "Changelog text outside ### Added, ### Changed and ### Fixed, left out: $(listed "$work/odd")." >&2
fi
if [ -s "$work/direct" ]; then
    echo "Commits without a pull request:" >&2
    cat "$work/direct" >&2
fi
