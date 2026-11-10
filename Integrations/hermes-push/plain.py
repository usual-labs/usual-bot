"""Markdown's words, as a notification shows them: no heading, list, quote, table or code fence
marks, bold and code as plain words, and links by their text.

Usual Bot does the same to the alerts it posts itself (`AgentAlert.plain`). Not for a command to
approve, where a `*` is part of the command.
"""

from __future__ import annotations

import re

_FENCES = ("```", "~~~")
_ONLY_MARKS = re.compile(r"[-*_=|: ]*")  # A rule, a table's divider or the line under a heading.
_BLOCK = re.compile(r"(>\s*)*(#{1,6}\s+|[-*+]\s+)?")
# Code and escaped marks, set aside so the marks in them stay.
_KEPT = re.compile(r"(`+)(.+?)\1|\\([!-/:-@\[-`{-~])")
_PUT_BACK = re.compile("\0(\\d+)\0")
_LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
# Bold before italic, so `***both***` loses all its marks. An underscore inside a word is a name's.
_EMPHASIS = [
    re.compile(pattern)
    for pattern in (
        r"\*\*(?=\S)(.+?)(?<=\S)\*\*",
        r"(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)",
        r"\*(?=\S)(.+?)(?<=\S)\*",
        r"(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)",
        r"~~(?=\S)(.+?)(?<=\S)~~",
    )
]


def plain(markdown: str) -> str:
    lines: list[str] = []
    in_code = False
    for line in markdown.splitlines():
        line = line.strip()
        if line.startswith(_FENCES):
            in_code = not in_code
        elif in_code:
            lines.append(line)
        elif not _ONLY_MARKS.fullmatch(line):
            line = line[_BLOCK.match(line).end() :]
            if line.startswith("|"):
                line = " · ".join(cell.strip() for cell in line.strip("|").split("|"))
            lines.append(_inline(line))
    return " ".join(" ".join(lines).split())


def _inline(line: str) -> str:
    kept: list[str] = []

    def keep(match: re.Match) -> str:
        kept.append(match.group(3) or match.group(2).strip())
        return f"\0{len(kept) - 1}\0"

    line = _LINK.sub(r"\1", _KEPT.sub(keep, line))
    for emphasis in _EMPHASIS:
        line = emphasis.sub(r"\1", line)
    return _PUT_BACK.sub(lambda match: kept[int(match.group(1))], line)
