#!/usr/bin/env python3
"""Opt-in live Option-drag checks using three disposable AppKit windows."""

import argparse
import ctypes as c
import json
import plistlib
import subprocess
import tempfile
import time
from pathlib import Path

YABAI = "/opt/homebrew/bin/yabai"
ALT = 1 << 19


class Point(c.Structure):
    _fields_ = [("x", c.c_double), ("y", c.c_double)]


def yb(*args):
    return subprocess.check_output([YABAI, "-m", *map(str, args)], text=True, timeout=5)


def windows():
    return json.loads(yb("query", "--windows"))


def near(a, b):
    return all(abs(a[key] - b[key]) <= 2 for key in ("x", "y", "w", "h"))


class Mouse:
    def __init__(self):
        self.cg = c.CDLL(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        )
        self.cf = c.CDLL(
            "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        )
        self.cg.CGPreflightPostEventAccess.restype = c.c_bool
        if not self.cg.CGPreflightPostEventAccess():
            raise RuntimeError("Desktop event posting is unavailable")
        self.cg.CGEventCreate.argtypes = [c.c_void_p]
        self.cg.CGEventCreate.restype = c.c_void_p
        self.cg.CGEventGetLocation.argtypes = [c.c_void_p]
        self.cg.CGEventGetLocation.restype = Point
        self.cg.CGEventCreateMouseEvent.argtypes = [
            c.c_void_p,
            c.c_uint32,
            Point,
            c.c_uint32,
        ]
        self.cg.CGEventCreateMouseEvent.restype = c.c_void_p
        self.cg.CGEventSetFlags.argtypes = [c.c_void_p, c.c_uint64]
        self.cg.CGEventPost.argtypes = [c.c_uint32, c.c_void_p]
        self.cf.CFRelease.argtypes = [c.c_void_p]
        event = self.cg.CGEventCreate(None)
        self.original = self.cg.CGEventGetLocation(event)
        self.cf.CFRelease(event)
        self.position = self.original
        self.down = False

    def post(self, kind, point, flags=0):
        event = self.cg.CGEventCreateMouseEvent(None, kind, point, 0)
        self.cg.CGEventSetFlags(event, flags)
        self.cg.CGEventPost(0, event)
        self.cf.CFRelease(event)
        self.position = point
        if kind == 1:
            self.down = True
        elif kind == 2:
            self.down = False

    def restore(self):
        if self.down:
            self.post(2, self.position, ALT)
        self.post(5, self.original)


def owned_windows(pid):
    """Read native overlay bounds without querying or modifying yabai."""
    cg = c.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    cf = c.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    cg.CGWindowListCopyWindowInfo.argtypes = [c.c_uint32, c.c_uint32]
    cg.CGWindowListCopyWindowInfo.restype = c.c_void_p
    cf.CFPropertyListCreateData.argtypes = [
        c.c_void_p,
        c.c_void_p,
        c.c_long,
        c.c_ulong,
        c.c_void_p,
    ]
    cf.CFPropertyListCreateData.restype = c.c_void_p
    cf.CFDataGetLength.argtypes = [c.c_void_p]
    cf.CFDataGetLength.restype = c.c_long
    cf.CFDataGetBytePtr.argtypes = [c.c_void_p]
    cf.CFDataGetBytePtr.restype = c.c_void_p
    cf.CFRelease.argtypes = [c.c_void_p]
    info = cg.CGWindowListCopyWindowInfo(1, 0)
    data = cf.CFPropertyListCreateData(None, info, 200, 0, None)
    try:
        raw = c.string_at(cf.CFDataGetBytePtr(data), cf.CFDataGetLength(data))
        return [
            row for row in plistlib.loads(raw) if row.get("kCGWindowOwnerPID") == pid
        ]
    finally:
        cf.CFRelease(data)
        cf.CFRelease(info)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--live",
        action="store_true",
        help="create test windows and post real mouse events",
    )
    args = parser.parse_args()
    if not args.live:
        parser.print_help()
        return

    root = Path(tempfile.mkdtemp(prefix="wm-drag-check-", dir="/private/tmp"))
    executable = root / "drag-windows"
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
    )
    baseline = windows()
    focused = next(row for row in baseline if row["has-focus"])
    baseline_spaces = json.loads(yb("query", "--spaces"))
    mouse = Mouse()
    daemon_pid = int(
        subprocess.check_output(["pgrep", "-x", "yabai"], text=True).split()[0]
    )
    fixture = None
    report = {"checks": [], "output": str(root)}

    def cards():
        return {
            row["title"][-1]: row
            for row in windows()
            if fixture and row["pid"] == fixture.pid
        }

    def settled():
        previous = None
        until = time.monotonic() + 4
        while time.monotonic() < until:
            current = cards()
            if (
                len(current) == 3
                and previous
                and all(
                    near(row["frame"], previous[key]["frame"])
                    for key, row in current.items()
                )
            ):
                assert all(not row["is-floating"] for row in current.values()), (
                    "Fixture windows are not tiled"
                )
                return current
            previous = current
            time.sleep(0.15)
        raise AssertionError("Test windows did not settle")

    def drag(zone, titlebar=False, screenshot=False):
        before = settled()
        source, target = before["A"]["frame"], before["B"]["frame"]
        fractions = {
            "center": (0.5, 0.5),
            "left": (0.12, 0.5),
            "right": (0.88, 0.5),
            "top": (0.5, 0.12),
            "bottom": (0.5, 0.88),
        }
        fx, fy = fractions[zone]
        start = Point(
            source["x"] + source["w"] * 0.5,
            source["y"] + (12 if titlebar else source["h"] * 0.5),
        )
        end = Point(target["x"] + target["w"] * fx, target["y"] + target["h"] * fy)
        native_before = {row["kCGWindowNumber"] for row in owned_windows(daemon_pid)}
        mouse.post(5, start)
        time.sleep(0.08)
        mouse.post(1, start, ALT)
        time.sleep(0.08)
        for step in range(1, 31):
            t = step / 30
            mouse.post(
                6,
                Point(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t),
                ALT,
            )
            time.sleep(0.012)
        time.sleep(0.15)
        overlays = [
            row
            for row in owned_windows(daemon_pid)
            if row["kCGWindowNumber"] not in native_before
        ]
        if screenshot:
            subprocess.run(
                [
                    "screencapture",
                    "-x",
                    "-D",
                    str(focused["display"]),
                    str(root / (zone + ".png")),
                ],
                check=True,
            )
        mouse.post(2, end, ALT)
        time.sleep(0.25)
        after = settled()
        a, b = after["A"]["frame"], after["B"]["frame"]
        if zone == "center":
            assert near(a, target) and near(b, source), (zone, source, target, a, b)
        else:
            axis, length, other, other_length = (
                ("x", "w", "y", "h")
                if zone in ("left", "right")
                else ("y", "h", "x", "w")
            )
            first, second = (a, b) if zone in ("left", "top") else (b, a)
            assert abs(first[axis] + first[length] + 10 - second[axis]) <= 2, (
                zone,
                a,
                b,
            )
            assert (
                abs(a[other] - b[other]) <= 2
                and abs(a[other_length] - b[other_length]) <= 2
            ), (zone, a, b)
        assert overlays, "No native drop indicator appeared"
        time.sleep(0.1)
        native_after = {row["kCGWindowNumber"] for row in owned_windows(daemon_pid)}
        assert not any(row["kCGWindowNumber"] in native_after for row in overlays), (
            "Drop indicator remained after release"
        )
        report["checks"].append(
            {
                "zone": zone,
                "titlebar": titlebar,
                "feedback": True,
                "before": before,
                "after": after,
            }
        )
        print(
            "PASS:",
            zone,
            "title bar" if titlebar else "window body",
            "drop, tiling and indicator cleanup",
            flush=True,
        )

    try:
        fixture = subprocess.Popen(
            [str(executable)],
            stdout=subprocess.DEVNULL,
            stderr=(root / "fixture.log").open("w"),
        )
        settled()
        for zone in ("center", "left", "right", "top", "bottom"):
            drag(zone, screenshot=zone in ("center", "left"))
        for index in range(5):
            drag("center", titlebar=index % 2 == 0)
        # A normal click must still reach the application after modified drags.
        card = settled()["C"]
        frame = card["frame"]
        point = Point(frame["x"] + frame["w"] * 0.5, frame["y"] + frame["h"] * 0.5)
        mouse.post(5, point)
        mouse.post(1, point)
        mouse.post(2, point)
        time.sleep(0.2)
        assert next(row for row in windows() if row["has-focus"])["id"] == card["id"], (
            "Ordinary click failed"
        )
        print("PASS: ordinary clicks still focus windows", flush=True)
    finally:
        if mouse.down:
            mouse.post(2, mouse.position, ALT)
        if fixture:
            fixture.terminate()
            fixture.wait(timeout=5)
        time.sleep(0.5)
        yb("window", focused["id"], "--focus")
        mouse.restore()
        current = {row["id"]: row for row in windows()}
        for original in baseline:
            actual = current[original["id"]]
            assert actual["space"] == original["space"] and near(
                actual["frame"], original["frame"]
            ), "Original desktop layout changed"
        assert (
            next(row for row in current.values() if row["has-focus"])["id"]
            == focused["id"]
        )
        spaces = json.loads(yb("query", "--spaces"))

        def signature(rows):
            return [
                (row["id"], row["label"], row["display"], row["windows"])
                for row in rows
            ]

        assert signature(spaces) == signature(baseline_spaces), (
            "Space assignments changed"
        )
        report["restored"] = True
        (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print("Desktop restored. Evidence:", root, flush=True)


if __name__ == "__main__":
    main()
