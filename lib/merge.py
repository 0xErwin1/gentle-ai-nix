"""Merge a rendered fragment into a file Gentle AI does not own outright.

Some clients keep the configuration Gentle AI writes in the same file as state
they write themselves: Claude Code's OAuth and project history live in
`.claude.json`, Codex's per-project trust levels in `config.toml`. Replacing
those files with a rendered copy would take that state with it, so the fragment
is merged in and everything it does not mention is left exactly as it was.

Merging is deliberately additive. A server dropped from the document is not
removed from a merged file, because this file is not ours to prune -- the entry
may be one the client or another tool wrote. Removing one is done by hand, in
the file, once.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

PLACEHOLDER = re.compile(r"@([A-Z][A-Z0-9_]*)@")


def deep_merge(base, overlay):
    """Overlay wins, and a mapping is merged rather than replaced.

    Replacing a mapping wholesale would drop sibling keys the client owns, which
    is the whole reason this file is merged instead of written.
    """
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return overlay

    merged = dict(base)
    for key, value in overlay.items():
        merged[key] = deep_merge(base.get(key), value) if key in base else value

    return merged


def substitute(text: str, values: dict[str, str], target: Path) -> str:
    """Replace every @NAME@ whose value was supplied.

    A placeholder with no value is left in place rather than emptied: an empty
    credential reads as a configured one and fails at use, where the untouched
    placeholder says plainly that the secret never arrived.
    """
    missing = set()

    def resolve(match: re.Match) -> str:
        name = match.group(1)
        if name not in values:
            missing.add(name)
            return match.group(0)
        return values[name]

    result = PLACEHOLDER.sub(resolve, text)
    for name in sorted(missing):
        print(f"gentle-ai: {target}: no value for @{name}@, left unresolved", file=sys.stderr)

    return result


def merge_json(fragment: str, existing: str) -> str:
    overlay = json.loads(fragment)
    base = json.loads(existing) if existing.strip() else {}

    return json.dumps(deep_merge(base, overlay), indent=2) + "\n"


def merge_toml(fragment: str, existing: str) -> str:
    # tomlkit round-trips comments, ordering and formatting, so a file a person
    # edits by hand survives being merged into.
    import tomlkit

    overlay = tomlkit.parse(fragment)
    document = tomlkit.parse(existing) if existing.strip() else tomlkit.document()

    def apply(target, source):
        for key, value in source.items():
            if key in target and hasattr(value, "items") and hasattr(target[key], "items"):
                apply(target[key], value)
            else:
                target[key] = value

    apply(document, overlay)

    return tomlkit.dumps(document)


MERGERS = {".json": merge_json, ".toml": merge_toml}


def write_private(target: Path, text: str) -> None:
    """Write through a temporary file so an interrupted run cannot truncate the
    target, and keep the result unreadable by anyone else: it holds a credential.
    """
    target.parent.mkdir(parents=True, exist_ok=True)

    handle, temporary = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
        os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary, target)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fragment", required=True, type=Path, help="rendered content to merge in")
    parser.add_argument("--target", required=True, type=Path, help="file to merge it into")
    parser.add_argument(
        "--secret",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="file holding the value for @NAME@; repeatable",
    )
    arguments = parser.parse_args()

    merge = MERGERS.get(arguments.target.suffix)
    if merge is None:
        supported = ", ".join(sorted(MERGERS))
        print(
            f"gentle-ai: cannot merge {arguments.target}: no merger for {arguments.target.suffix or 'a suffixless file'}; supported: {supported}",
            file=sys.stderr,
        )
        return 1

    values: dict[str, str] = {}
    for pair in arguments.secret:
        name, _, path = pair.partition("=")
        try:
            values[name] = Path(path).read_text().strip()
        except OSError as error:
            print(f"gentle-ai: cannot read the value for @{name}@: {error}", file=sys.stderr)

    existing = arguments.target.read_text() if arguments.target.exists() else ""

    try:
        merged = merge(arguments.fragment.read_text(), existing)
    except Exception as error:
        print(
            f"gentle-ai: cannot merge into {arguments.target}: {error}; the file is unchanged",
            file=sys.stderr,
        )
        return 1

    write_private(arguments.target, substitute(merged, values, arguments.target))

    return 0


if __name__ == "__main__":
    sys.exit(main())
