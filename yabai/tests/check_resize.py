#!/usr/bin/env python3
"""Opt-in Option-right-drag measurements on disposable windows on each display."""

import argparse
import ctypes as c
import hashlib
import json
import statistics
import subprocess
import tempfile
import time
from itertools import pairwise
from pathlib import Path

from check_drag import ALT, YABAI, Mouse, Point, near, owned_windows, windows, yb


class Usage(c.Structure):
    # rusage_info_v2 from the macOS SDK; CPU times are in nanoseconds.
    _fields_ = [("uuid", c.c_uint8 * 16)] + [
        (name, c.c_uint64)
        for name in (
            "user",
            "system",
            "idle_wakeups",
            "interrupt_wakeups",
            "pageins",
            "wired",
            "resident",
            "footprint",
            "start",
            "exit",
            "child_user",
            "child_system",
            "child_idle",
            "child_interrupt",
            "child_pageins",
            "child_elapsed",
            "disk_read",
            "disk_written",
        )
    ]


class Resources:
    def __init__(self, pid):
        self.pid = pid
        self.lib = c.CDLL("/usr/lib/libproc.dylib")
        self.lib.proc_pid_rusage.argtypes = [c.c_int, c.c_int, c.c_void_p]
        self.lib.proc_pid_rusage.restype = c.c_int

    def sample(self):
        result = Usage()
        if self.lib.proc_pid_rusage(self.pid, 2, c.byref(result)):
            raise RuntimeError("Could not read yabai resource accounting")
        return {
            "time": time.monotonic(),
            "cpu_ns": result.user + result.system,
            "footprint_bytes": result.footprint,
        }

    def idle(self):
        before = self.sample()
        time.sleep(1.5)
        after = self.sample()
        return {
            "cpu_percent": (after["cpu_ns"] - before["cpu_ns"])
            / ((after["time"] - before["time"]) * 1e7),
            "footprint_bytes": after["footprint_bytes"],
        }


class RightMouse(Mouse):
    def post(self, kind, point, flags=0):
        event = self.cg.CGEventCreateMouseEvent(None, kind, point, 1)
        if not event:
            raise RuntimeError("Could not create mouse event")
        self.cg.CGEventSetFlags(event, flags)
        self.cg.CGEventPost(0, event)
        self.cf.CFRelease(event)
        self.position = point
        if kind == 3:
            self.down = True
        elif kind == 4:
            self.down = False

    def restore(self):
        if self.down:
            self.post(4, self.position, ALT)
        self.post(5, self.original)


def native_frames(pid):
    return {
        row["kCGWindowNumber"]: {
            "x": row["kCGWindowBounds"]["X"],
            "y": row["kCGWindowBounds"]["Y"],
            "w": row["kCGWindowBounds"]["Width"],
            "h": row["kCGWindowBounds"]["Height"],
        }
        for row in owned_windows(pid)
    }


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)] if ordered else None


def geometry_signature(rows):
    return sorted(
        (row["id"], row["label"], row["display"], sorted(row["windows"]))
        for row in rows
    )


def check_tiling(rows, gap=10):
    assert all(not row["is-floating"] for row in rows), "A test window left tiling"
    for i, row in enumerate(rows):
        a = row["frame"]
        for other in rows[i + 1 :]:
            b = other["frame"]
            separation = max(
                b["x"] - a["x"] - a["w"],
                a["x"] - b["x"] - b["w"],
                b["y"] - a["y"] - a["h"],
                a["y"] - b["y"] - b["h"],
            )
            assert separation >= gap - 2, ("Tiles overlap or lost their gap", a, b)


def measure(mouse, fixture, source, dx, dy, resources):
    frame = source["frame"]
    start = Point(frame["x"] + frame["w"] * 0.75, frame["y"] + frame["h"] * 0.75)
    end = Point(start.x + dx, start.y + dy)
    samples = []

    def sample():
        samples.append({"time": time.monotonic(), "frames": native_frames(fixture.pid)})

    mouse.post(5, start)
    time.sleep(0.08)
    mouse.post(3, start, ALT)
    time.sleep(0.08)
    before = resources.sample()
    began = time.monotonic()
    # Generate a bounded ~120 Hz stream; observe native bounds, not yabai's AX cache.
    for step in range(1, 181):
        deadline = began + step / 120
        delay = deadline - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        t = step / 180
        mouse.post(7, Point(start.x + dx * t, start.y + dy * t), ALT)
        sample()
    mouse.post(4, end, ALT)
    released = time.monotonic()
    # Retain a full second of post-release samples to expose delayed updates.
    until = released + 1.0
    while time.monotonic() < until:
        sample()
        time.sleep(1 / 120)
    after = resources.sample()
    changes = []
    previous = None
    for row in samples:
        current = row["frames"].get(source["id"])
        if current is not None and previous is not None and current != previous:
            changes.append(row["time"])
        previous = current
    during = [stamp for stamp in changes if stamp < released]
    intervals = [(b - a) * 1000 for a, b in pairwise(during)]
    post = [stamp for stamp in changes if stamp >= released]
    return {
        "window": source["id"],
        "dx": dx,
        "dy": dy,
        "duration_s": released - began,
        "observed_changes": len(during),
        "observed_changes_per_s": len(during) / (released - began),
        "interval_median_ms": statistics.median(intervals) if intervals else None,
        "interval_p95_ms": percentile(intervals, 0.95),
        "interval_max_ms": max(intervals) if intervals else None,
        "last_post_release_change_ms": (post[-1] - released) * 1000 if post else 0,
        "changes_after_250ms": sum(stamp > released + 0.25 for stamp in post),
        "daemon_cpu_ms": (after["cpu_ns"] - before["cpu_ns"]) / 1e6,
        "samples": samples,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--live", action="store_true", help="temporarily use the pointer"
    )
    parser.add_argument(
        "--label", default="baseline", help="report label (not a pass claim)"
    )
    args = parser.parse_args()
    if not args.live:
        parser.print_help()
        return

    baseline = windows()
    spaces = json.loads(yb("query", "--spaces"))
    displays = json.loads(yb("query", "--displays"))
    focused = next((row for row in baseline if row["has-focus"]), None)
    visible = [row["id"] for row in spaces if row["is-visible"]]
    targets = []
    for display in displays:
        target = next(
            (
                row
                for row in spaces
                if row["display"] == display["index"]
                and not row["windows"]
                and not row["is-native-fullscreen"]
                and row["type"] == "bsp"
            ),
            None,
        )
        if target is None:
            raise RuntimeError(f"No empty BSP Space on display {display['index']}")
        targets.append((display, target["id"]))

    root = Path(tempfile.mkdtemp(prefix="wm-resize-check-", dir="/private/tmp"))
    executable = root / "resize-windows"
    subprocess.run(
        [
            "clang",
            "-O2",
            "-framework",
            "Cocoa",
            str(Path(__file__).with_name("drag_windows.m")),
            "-o",
            str(executable),
        ],
        check=True,
        timeout=30,
    )
    mouse = RightMouse()
    daemon_pid = int(
        subprocess.check_output(["pgrep", "-x", "yabai"], text=True).split()[0]
    )
    resources = Resources(daemon_pid)
    report = {
        "label": args.label,
        "binary_sha256": hashlib.sha256(Path(YABAI).read_bytes()).hexdigest(),
        "daemon_pid": daemon_pid,
        "displays": displays,
        "baseline_windows": baseline,
        "baseline_spaces": spaces,
        "idle_before": resources.idle(),
        "checks": [],
        "restored": False,
    }
    fixture = None

    def focus_space(space_id):
        current = json.loads(yb("query", "--spaces"))
        index = next(row["index"] for row in current if row["id"] == space_id)
        yb("space", "--focus", index)
        time.sleep(0.35)

    def cards():
        return sorted(
            (row for row in windows() if fixture and row["pid"] == fixture.pid),
            key=lambda row: row["title"],
        )

    def settled():
        previous = None
        for _ in range(30):
            current = cards()
            if (
                len(current) == 3
                and previous
                and all(near(a["frame"], b["frame"]) for a, b in zip(current, previous))
            ):
                check_tiling(current)
                return current
            previous = current
            time.sleep(0.15)
        raise AssertionError("Fixture windows did not settle")

    try:
        for display, target in targets:
            focus_space(target)
            fixture = subprocess.Popen(
                [str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            rows = settled()
            target_index = next(
                s["index"]
                for s in json.loads(yb("query", "--spaces"))
                if s["id"] == target
            )
            # Unbundled AppKit fixtures can initially open on the main display.
            for row in rows:
                if row["space"] != target_index:
                    yb("window", row["id"], "--space", target_index)
            yb("window", rows[0]["id"], "--focus")
            time.sleep(0.3)
            rows = settled()
            assert all(row["space"] == target_index for row in rows), (
                "Test windows did not reach their dedicated Space"
            )
            # A horizontal split fence is available from the leftmost test tile.
            source = min(rows, key=lambda row: (row["frame"]["x"], row["frame"]["y"]))
            for dx in (120, -100, 80):
                source = next(row for row in settled() if row["id"] == source["id"])
                result = measure(mouse, fixture, source, dx, 0, resources)
                result["display"] = display["index"]
                result["after"] = settled()
                report["checks"].append(result)
                print(
                    f"Display {display['index']}, dx={dx}: "
                    f"{result['observed_changes_per_s']:.1f} observed changes/s, "
                    f"p95 interval {result['interval_p95_ms']} ms, "
                    f"last post-release change {result['last_post_release_change_ms']:.1f} ms",
                    flush=True,
                )
            fixture.terminate()
            fixture.wait(timeout=5)
            fixture = None
            time.sleep(0.25)
        report["idle_after"] = resources.idle()
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        try:
            if mouse.down:
                mouse.post(4, mouse.position, ALT)
            if fixture:
                fixture.terminate()
                fixture.wait(timeout=5)
            time.sleep(0.4)
            for space_id in visible:
                focus_space(space_id)
            if focused:
                yb("window", focused["id"], "--focus")
            mouse.restore()
            current = {row["id"]: row for row in windows()}
            for original in baseline:
                actual = current[original["id"]]
                assert actual["space"] == original["space"] and near(
                    actual["frame"], original["frame"]
                ), "Original desktop layout changed"
            after_spaces = json.loads(yb("query", "--spaces"))
            assert geometry_signature(after_spaces) == geometry_signature(spaces), (
                "Space identities, labels, display assignments or membership changed"
            )
            assert {row["id"] for row in after_spaces if row["is-visible"]} == set(
                visible
            )
            if focused:
                assert (
                    next(row["id"] for row in current.values() if row["has-focus"])
                    == focused["id"]
                )
            report["restored"] = True
        finally:
            (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(
                "Evidence:", root, "Desktop restored:", report["restored"], flush=True
            )


if __name__ == "__main__":
    main()
