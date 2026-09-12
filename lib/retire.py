"""Retire Pi package entries an earlier generation installed under an
identity this one no longer uses.

Pi records an installed package by the exact spelling it was given: a
`git:...@<rev>` source and the same source pinned to a different revision are
two different entries to Pi, and so are an `npm:<name>` spec and a local path
built for the same plugin. Switching a channel is what makes an entry like
that displaced -- still present in Pi's own settings, but no longer what the
current configuration wants installed. Left alone, a displaced entry does not
go away on its own: for a plugin installed by local path, a rebuilt store
path is a new identity to Pi on every generation, so what accumulates is not
one stale entry but one per rebuild, until Pi refuses to load two copies of
the same plugin.

This does not edit settings.json directly. `pi remove` is what actually
updates Pi's own bookkeeping around an entry -- the settings file plus
whatever else installing it touched -- so retiring an entry means asking Pi
to remove it, the same way installing one means asking Pi to install it.

Only entries actually present are ever named to `pi remove`: `pi remove`
exits non-zero on a package it does not have installed, and re-reading
settings.json fresh on every run is what keeps this idempotent without a
stamp of its own -- a converged settings file matches no rule, and nothing
runs.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

# Local entries never carry one of these; matching one of them is what tells
# an npm spec or a git source apart from a filesystem path, which is compared
# a different way (by suffix and, when a rule cares, by where it resolves to)
# rather than by an exact or prefixed spelling.
SCHEME_PREFIXES = ("npm:", "git:", "https://", "ssh://")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", required=True, help="Pi's settings.json")
    parser.add_argument(
        "--displaced",
        action="append",
        default=[],
        metavar="JSON",
        help="a JSON identity rule naming entries this generation no longer wants",
    )
    return parser.parse_args()


def installed_packages(settings_path: str) -> list:
    """Pi's own declared packages, read best-effort: this file is Pi's, not
    this module's, so a state this step cannot make sense of -- missing,
    unreadable, truncated, or shaped unlike Pi's settings -- degrades to "no
    packages" rather than failing the switch that happens to run alongside
    it."""
    try:
        with open(settings_path, encoding="utf-8") as handle:
            settings = json.load(handle)
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as error:
        print(f"gentle-ai: cannot read Pi settings {settings_path}: {error}", file=sys.stderr)
        return []

    if not isinstance(settings, dict):
        print(f"gentle-ai: Pi settings {settings_path} is not a JSON object", file=sys.stderr)
        return []

    packages = settings.get("packages", [])
    if not isinstance(packages, list):
        return []
    return [entry for entry in packages if isinstance(entry, str)]


def matches_npm(entry: str, name: str) -> bool:
    """An npm entry for `name`, bare or at any version."""
    prefix = f"npm:{name}"
    return entry == prefix or entry.startswith(prefix + "@")


def matches_git(entry: str, name: str) -> bool:
    """A git entry for `name`: `git:<host>/<user>/<name>` optionally pinned
    with `@<ref>`, `name` being the last path segment before any pin."""
    return re.match(rf"^git:.*/{re.escape(name)}(@[^/]*)?$", entry) is not None


def matches_local(entry: str, patterns: list, exception, settings_dir: str) -> bool:
    """A local path matching one of `patterns` by suffix, unless it resolves
    (relative to `settings_dir`, the way Pi itself stores one) to `exception`
    -- the one local path this generation still wants kept."""
    if entry.startswith(SCHEME_PREFIXES):
        return False
    if not any(re.search(pattern, entry) for pattern in patterns):
        return False
    if exception is None:
        return True

    resolved = entry if os.path.isabs(entry) else os.path.join(settings_dir, entry)
    return os.path.normpath(resolved) != os.path.normpath(exception)


def npm_package_name(spec: str) -> str:
    """The package name in an npm spec (with its `npm:` prefix already
    stripped), the name possibly itself scoped as `@scope/name`."""
    if spec.startswith("@"):
        slash = spec.find("/")
        if slash == -1:
            return spec
        at = spec.find("@", slash)
        return spec if at == -1 else spec[:at]
    at = spec.find("@")
    return spec if at == -1 else spec[:at]


def repo_package_name(path: str) -> str:
    """The last path segment before an optional `@<ref>` pin, for a git or
    plain URL source with its scheme already stripped."""
    return path.split("@", 1)[0].rstrip("/").rsplit("/", 1)[-1]


def package_name_of(source: str) -> str:
    """The package name a Pi install source names, read from the source
    itself: the name in an npm spec, the repository in a git or plain URL
    source, or the last path component of a local one. This is never the
    attribute-set key the document declared the source under -- a key is
    free-form, and Pi has no notion of it -- only the identity Pi itself
    would derive from installing that exact source."""
    if source.startswith("npm:"):
        return npm_package_name(source[len("npm:"):])
    if source.startswith("git:"):
        return repo_package_name(source[len("git:"):])
    if source.startswith(("https://", "ssh://")):
        return repo_package_name(source.partition("://")[2])
    return os.path.basename(source.rstrip("/"))


def matches_package(entry: str, keep: str) -> bool:
    """An installed entry naming the same package `keep` does -- by the name
    carried inside the source, not by whatever key the document declared it
    under -- but not the exact spelling this generation still wants kept.
    Dropping the package from the declared set entirely is not handled here:
    nothing records what an earlier generation declared, so that case still
    needs a manual `pi remove`."""
    if entry == keep:
        return False
    return package_name_of(entry) == package_name_of(keep)


def matches_rule(entry: str, rule: dict, settings_dir: str) -> bool:
    kind = rule.get("type")
    if kind == "npm":
        return matches_npm(entry, rule["name"])
    if kind == "git":
        return matches_git(entry, rule["name"])
    if kind == "local":
        return matches_local(entry, rule.get("patterns", []), rule.get("except"), settings_dir)
    if kind == "package":
        return matches_package(entry, rule["keep"])
    raise ValueError(f"unknown displaced-package rule type {kind!r}")


def resolved_local(entry: str, settings_dir: str) -> str:
    """Where a local entry points, resolved the way Pi itself stores one:
    relative to `settings_dir` unless it is already absolute."""
    located = entry if os.path.isabs(entry) else os.path.join(settings_dir, entry)
    return os.path.normpath(located)


def replacement_present(wanted: str, packages: list, settings_dir: str) -> bool:
    """Whether `wanted` -- a rule's own replacement spelling -- is already
    among the freshly read packages. A local path is present by location,
    the same comparison `matches_local`'s `except` already makes; every
    other source is present only by the exact spelling Pi would have stored
    it under."""
    if wanted.startswith(SCHEME_PREFIXES):
        return wanted in packages
    target = resolved_local(wanted, settings_dir)
    return any(
        not entry.startswith(SCHEME_PREFIXES) and resolved_local(entry, settings_dir) == target
        for entry in packages
    )


def applicable_rules(rules: list, packages: list, settings_dir: str) -> list:
    """The rules allowed to retire anything this run: a rule whose `wanted`
    replacement is not yet among Pi's own packages retires nothing, because
    retiring the entry it displaces before its replacement exists is what
    would turn a failed install into a missing harness rather than a
    previous, working one left in place."""
    applicable = []
    for rule in rules:
        wanted = rule.get("wanted")
        if wanted is None or replacement_present(wanted, packages, settings_dir):
            applicable.append(rule)
            continue
        for entry in packages:
            if matches_rule(entry, rule, settings_dir):
                print(
                    f"gentle-ai: kept {entry}: replacement {wanted} is not installed",
                    file=sys.stderr,
                )
    return applicable


def displaced_entries(packages: list, rules: list, settings_dir: str) -> list:
    displaced = []
    for entry in packages:
        if any(matches_rule(entry, rule, settings_dir) for rule in rules):
            displaced.append(entry)
    return displaced


def main() -> int:
    arguments = parse_arguments()

    rules = [json.loads(raw) for raw in arguments.displaced]
    if not rules:
        return 0

    packages = installed_packages(arguments.settings)
    if not packages:
        return 0

    settings_dir = os.path.dirname(os.path.abspath(arguments.settings))
    rules = applicable_rules(rules, packages, settings_dir)
    entries = displaced_entries(packages, rules, settings_dir)
    if not entries:
        return 0

    if shutil.which("pi") is None:
        print(
            "gentle-ai: cannot retire displaced Pi packages: pi is not on PATH",
            file=sys.stderr,
        )
        return 0

    # A registry being unreachable already costs only the provisioning step's
    # own packages, never the switch; a `pi remove` Pi itself refuses (a lock
    # held by a running agent, an entry it will not drop) is the same kind of
    # failure and gets the same treatment: log it and keep going, so one
    # unremovable entry cannot leave every other displaced entry, and every
    # later activation step, stuck behind it.
    failed = False
    for entry in entries:
        print(f"gentle-ai: pi remove {entry}", file=sys.stderr)
        result = subprocess.run(["pi", "remove", entry], check=False)
        if result.returncode != 0:
            failed = True
            print(f"gentle-ai: failed to retire displaced package: {entry}", file=sys.stderr)

    if failed:
        print("gentle-ai: some displaced Pi packages could not be retired", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
