"""Copy a subtree, filling missing frontmatter keys in its markdown files.

A borrowed harness speaks the source client's dialect, and a receiving client
may require a frontmatter field the source never writes: agens refuses an
agent definition without `mode:`, while Claude Code has no such field at all.
The receiving client's requirement belongs to the projection, not to the
source files, so the key is inserted while the copy is made.

Only a missing key is filled. A file that already states the key keeps its own
value, whatever it is, because a default that overwrote a stated value would
be a rename wearing a default's name. Files without a frontmatter block are
copied untouched: inventing a block would also invent the required fields the
receiving client checks before this one, and a loud parse failure there beats
a silently half-valid definition here.

Only markdown files are considered, and only text is touched. Anything that is
not valid UTF-8 is copied byte for byte.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path


def fill_frontmatter(text: str, defaults: dict[str, str]) -> str:
    """Insert each missing top-level key just before the closing delimiter."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text

    closing = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            closing = index
            break
    if closing is None:
        return text

    stated = {
        match.group(1)
        for line in lines[1:closing]
        if (match := re.match(r"([A-Za-z0-9_-]+)\s*:", line))
    }

    missing = [key for key in sorted(defaults) if key not in stated]
    if not missing:
        return text

    inserted = [f"{key}: {defaults[key]}" for key in missing]

    return "\n".join(lines[:closing] + inserted + lines[closing:])


def fill(data: bytes, defaults: dict[str, str]) -> bytes:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data

    return fill_frontmatter(text, defaults).encode("utf-8")


def copy_tree(source: Path, target: Path, defaults: dict[str, str]) -> None:
    """Copy through symbolic links, since the source is a store tree of them."""
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
        for entry in sorted(os.listdir(source)):
            copy_tree(source / entry, target / entry, defaults)
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    data = source.read_bytes()
    if source.suffix == ".md":
        data = fill(data, defaults)
    target.write_bytes(data)
    shutil.copymode(source, target)
    target.chmod(target.stat().st_mode | 0o200)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="subtree to copy")
    parser.add_argument("--target", required=True, type=Path, help="where the filled copy is written")
    parser.add_argument(
        "--default",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="frontmatter key filled into markdown files that lack it; repeatable",
    )
    arguments = parser.parse_args()

    defaults = {}
    for pair in arguments.default:
        key, separator, value = pair.partition("=")
        if not separator or not key:
            print(f"gentle-ai: --default expects KEY=VALUE, got {pair!r}", file=sys.stderr)
            return 1
        defaults[key] = value

    copy_tree(arguments.source, arguments.target, defaults)

    return 0


if __name__ == "__main__":
    sys.exit(main())
