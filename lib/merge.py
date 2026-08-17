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


def deep_merge(base, overlay, union_lists=(), path=""):
    """Overlay wins, and a mapping is merged rather than replaced.

    Replacing a mapping wholesale would drop sibling keys the client owns, which
    is the whole reason this file is merged instead of written.

    A list is replaced, because a list the harness owns has to be able to lose
    an entry: appending forever would keep a rule alive after it was removed
    from the declaration. Lists named in union_lists are the exception, for the
    ones the client appends to itself -- there, replacing is what destroys
    state, and the fragment means "these must be present" rather than "these are
    all there is".
    """
    if isinstance(base, list) and isinstance(overlay, list) and path in union_lists:
        return base + [entry for entry in overlay if entry not in base]

    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return overlay

    merged = dict(base)
    for key, value in overlay.items():
        below = f"{path}.{key}" if path else key
        merged[key] = deep_merge(base.get(key), value, union_lists, below) if key in base else value

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


def merge_json(fragment: str, existing: str, union_lists=()) -> str:
    overlay = json.loads(fragment)
    base = json.loads(existing) if existing.strip() else {}

    return json.dumps(deep_merge(base, overlay, union_lists), indent=2) + "\n"


def merge_toml(fragment: str, existing: str, union_lists=()) -> str:
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


def read_env_file(path: Path) -> dict[str, str]:
    """Read NAME=value lines, the shape a shell-sourced secret file already has.

    An unreadable file is reported rather than fatal: the placeholders it would
    have supplied stay unresolved, which says plainly that the secret never
    arrived instead of writing an empty credential.
    """
    values: dict[str, str] = {}
    try:
        content = path.read_text()
    except OSError as error:
        print(f"gentle-ai: cannot read {path}: {error}", file=sys.stderr)
        return values

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, separator, value = line.partition("=")
        if not separator:
            continue
        values[name.strip()] = value.strip().strip("'\"")

    return values


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
    parser.add_argument(
        "--replace",
        action="store_true",
        help="write the fragment over the target instead of merging into it",
    )
    parser.add_argument(
        "--union-list",
        action="append",
        default=[],
        metavar="DOTTED.PATH",
        help="array the client appends to itself, merged by union instead of replaced; repeatable",
    )
    parser.add_argument(
        "--env-file",
        action="append",
        default=[],
        metavar="PATH",
        help="file of NAME=value lines, each supplying a placeholder; repeatable",
    )
    arguments = parser.parse_args()

    merge = (lambda fragment, _existing, _union: fragment) if arguments.replace else MERGERS.get(arguments.target.suffix)
    if merge is None:
        supported = ", ".join(sorted(MERGERS))
        print(
            f"gentle-ai: cannot merge {arguments.target}: no merger for {arguments.target.suffix or 'a suffixless file'}; supported: {supported}",
            file=sys.stderr,
        )
        return 1

    values: dict[str, str] = {}
    for path in arguments.env_file:
        values.update(read_env_file(Path(path)))
    for pair in arguments.secret:
        name, _, path = pair.partition("=")
        try:
            values[name] = Path(path).read_text().strip()
        except OSError as error:
            print(f"gentle-ai: cannot read the value for @{name}@: {error}", file=sys.stderr)

    existing = arguments.target.read_text() if arguments.target.exists() else ""

    try:
        merged = merge(arguments.fragment.read_text(), existing, tuple(arguments.union_list))
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
