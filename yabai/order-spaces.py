#!/usr/bin/env python3
"""Keep managed native Spaces ordered without changing display assignments."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from contextlib import contextmanager

LABELS = tuple(f"ws-{label}" for label in "1234567890a")
RANK = {label: index for index, label in enumerate(LABELS)}


def validate_spaces(raw):
    if not isinstance(raw, list):
        raise ValueError("yabai returned a non-list Space report")
    ids, indices = set(), set()
    for space in raw:
        if not isinstance(space, dict):
            raise ValueError("yabai returned a malformed Space")
        for key in ("id", "index", "display"):
            if type(space.get(key)) is not int or space[key] < 1:
                raise ValueError(f"invalid Space {key}")
        if not isinstance(space.get("label"), str) or type(space.get("is-native-fullscreen")) is not bool:
            raise ValueError("invalid Space label or fullscreen flag")
        if space["id"] in ids or space["index"] in indices:
            raise ValueError("duplicate native Space ID or index")
        ids.add(space["id"])
        indices.add(space["index"])
    return sorted(raw, key=lambda space: space["index"])


def display_orders(spaces):
    for display in sorted({space["display"] for space in spaces}):
        current = [space for space in spaces if space["display"] == display and not space["is-native-fullscreen"]]
        desired = sorted(current, key=lambda space: RANK.get(space["label"], len(RANK)))
        yield display, current, desired


def next_move(spaces):
    for _, current, desired in display_orders(spaces):
        for actual, wanted in zip(current, desired):
            if actual["id"] != wanted["id"]:
                return wanted["id"], actual["id"]
    return None


def topology(spaces):
    return tuple((space["id"], space["index"], space["display"], space["label"], space["is-native-fullscreen"]) for space in spaces)


class Yabai:
    def __init__(self, binary):
        self.binary = binary

    def command(self, *args):
        result = subprocess.run([self.binary, "-m", *map(str, args)], capture_output=True, text=True, timeout=10, check=False)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f"yabai exited {result.returncode}")
        return result.stdout

    def spaces(self):
        return validate_spaces(json.loads(self.command("query", "--spaces")))

    def move(self, source_index, destination_index):
        self.command("space", source_index, "--move", destination_index)


def reconcile(client):
    spaces = client.spaces()
    limit, moved = max(16, len(spaces) * 8), 0
    for _ in range(limit):
        move = next_move(spaces)
        latest = client.spaces()
        if topology(latest) != topology(spaces):
            spaces = latest
            continue
        if move is None:
            return moved
        by_id = {space["id"]: space for space in latest}
        source, destination = (by_id[native_id] for native_id in move)
        if source["display"] != destination["display"] or source["is-native-fullscreen"] or destination["is-native-fullscreen"]:
            raise RuntimeError("Space topology changed; refusing an unsafe move")
        client.move(source["index"], destination["index"])
        moved += 1
        spaces = client.spaces()
    raise RuntimeError("Space ordering did not settle; another client may be rearranging Spaces")


@contextmanager
def order_lock(path):
    # flock releases on exit/crash; the persistent empty file is not a stale lock.
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    acquired = False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            acquired = True
        except BlockingIOError:
            pass
        yield acquired
    finally:
        if acquired:
            fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="exit 1 if ordinary Spaces need ordering; never mutate")
    mode.add_argument("--dry-run", action="store_true", help="show intended per-display order; never mutate")
    args = parser.parse_args(argv)
    client = Yabai(os.environ.get("YABAI_BIN", "/opt/homebrew/bin/yabai"))
    try:
        if args.check or args.dry_run:
            spaces = client.spaces()
            if args.dry_run:
                for display, _, desired in display_orders(spaces):
                    print(f"Display {display}: " + " ".join(f'{space["label"] or "unlabeled"}#{space["id"]}' for space in desired))
                return 0
            return int(next_move(spaces) is not None)
        lock_path = Path(tempfile.gettempdir()) / f"yabai-space-order-{os.getuid()}.lock"
        with order_lock(lock_path) as acquired:
            if not acquired:
                return 0
            moved = reconcile(client)
            if moved:
                print(f"Ordered Spaces on their existing displays ({moved} moves)")
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"Space ordering failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
