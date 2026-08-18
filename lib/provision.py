"""Run the package installation a rendered Gentle AI manifest declares.

Some clients keep their harness in packages installed by their own tool rather
than in files. Rendering produces the configuration around such a harness; this
runs the commands that produce the harness itself, reading them from the
manifest so the package list stays Gentle AI's to name.

It is deliberately conservative about when it runs. The commands reach a
network, so repeating them on every activation would make an unrelated switch
depend on a registry being up. A stamp keyed on the commands themselves means
they run when the list changes and not otherwise.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--agent", help="client whose own tool installs its harness")
    group.add_argument("--tool", help="community tool that wires itself into the clients")
    parser.add_argument("--stamp-dir", required=True)
    parser.add_argument(
        "--force",
        action="store_true",
        help="run the commands even when the stamp already records them",
    )
    return parser.parse_args()


def declared_commands(manifest_path: str, field: str, value: str) -> list:
    with open(manifest_path, encoding="utf-8") as handle:
        report = json.load(handle)

    resources = report.get("manifest", {}).get("resources", [])
    commands = []
    for resource in resources:
        if resource.get("selector") != "provision":
            continue
        if resource.get(field) != value:
            continue
        commands.extend(resource.get("commands", []))

    return commands


def digest_of(commands: list) -> str:
    encoded = json.dumps(commands, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def read_stamp(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return ""


def write_stamp(path: str, digest: str) -> None:
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)

    handle, temporary = tempfile.mkstemp(dir=directory)
    with os.fdopen(handle, "w", encoding="utf-8") as stamp:
        stamp.write(digest + "\n")
    os.replace(temporary, path)


def main() -> int:
    arguments = parse_arguments()

    field = "agent" if arguments.agent else "tool"
    name = arguments.agent or arguments.tool

    commands = declared_commands(arguments.manifest, field, name)
    if not commands:
        return 0

    stamp_path = os.path.join(arguments.stamp_dir, f"{field}-{name}.provisioned")
    digest = digest_of(commands)
    if not arguments.force and read_stamp(stamp_path) == digest:
        return 0

    # The client's own binary is a precondition, not something this installs.
    # Failing activation over a client the user has not installed yet would
    # block every unrelated change in the same switch.
    tool = commands[0][0]
    if shutil.which(tool) is None:
        print(
            f"gentle-ai: {name} not provisioned: {tool} is not on PATH",
            file=sys.stderr,
        )
        return 0

    for command in commands:
        print(f"gentle-ai: {' '.join(command)}", file=sys.stderr)
        result = subprocess.run(command, check=False)
        if result.returncode != 0:
            print(
                f"gentle-ai: {name} provisioning failed: {' '.join(command)}",
                file=sys.stderr,
            )
            return result.returncode

    write_stamp(stamp_path, digest)

    return 0


if __name__ == "__main__":
    sys.exit(main())
