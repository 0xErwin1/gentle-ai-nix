"""Copy a rendered subtree, pointing its cross-references at the copy.

A client that receives another client's harness receives its prose too, and
that prose names the directory it was rendered for: an agent told to read
`~/.claude/skills/_shared/...` reaches back into the source client's tree even
though the same file sits beside it under its own root. Where the assets were
copied precisely because the client refuses to read through a symbolic link,
that reference resolves to a path it cannot open at all.

The replacements are derived from the asset mapping rather than written by
hand, so the most specific one is applied where it exists -- `.claude/CLAUDE.md`
becomes `AGENTS.md` and not `CLAUDE.md` under the new root -- and the source
root itself covers everything the mapping does not name. They are applied in a
single pass, so a rewritten path is never rewritten again.

Only text is rewritten. Anything that is not valid UTF-8 is copied byte for
byte, because a substring that looks like a path inside a binary is not one.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path


def compile_replacements(pairs: list[tuple[str, str]]) -> tuple[re.Pattern | None, dict[str, str]]:
    """One alternation, most specific first, so each position is rewritten once.

    Substituting the patterns one after another would let a later, shorter
    pattern match inside what an earlier one already produced. Ordering by
    descending length is what makes `.claude/CLAUDE.md` win over `.claude/`.
    """
    table = dict(pairs)
    if not table:
        return None, table

    ordered = sorted(table, key=len, reverse=True)

    return re.compile("|".join(re.escape(pattern) for pattern in ordered)), table


def rewrite(data: bytes, pattern: re.Pattern | None, table: dict[str, str]) -> bytes:
    if pattern is None:
        return data

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data

    return pattern.sub(lambda match: table[match.group(0)], text).encode("utf-8")


def copy_tree(source: Path, target: Path, pattern: re.Pattern | None, table: dict[str, str]) -> None:
    """Copy through symbolic links, since the source is a store tree of them."""
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
        for entry in sorted(os.listdir(source)):
            copy_tree(source / entry, target / entry, pattern, table)
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(rewrite(source.read_bytes(), pattern, table))
    shutil.copymode(source, target)
    target.chmod(target.stat().st_mode | 0o200)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="rendered subtree to copy")
    parser.add_argument("--target", required=True, type=Path, help="where the rewritten copy is written")
    parser.add_argument(
        "--replace",
        action="append",
        default=[],
        metavar="FROM=TO",
        help="reference to rewrite, most specific applied first; repeatable",
    )
    arguments = parser.parse_args()

    pairs = []
    for pair in arguments.replace:
        source_reference, separator, target_reference = pair.partition("=")
        if not separator or not source_reference:
            print(f"gentle-ai: --replace expects FROM=TO, got {pair!r}", file=sys.stderr)
            return 1
        pairs.append((source_reference, target_reference))

    pattern, table = compile_replacements(pairs)

    copy_tree(arguments.source, arguments.target, pattern, table)

    return 0


if __name__ == "__main__":
    sys.exit(main())
