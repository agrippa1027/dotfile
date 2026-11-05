#!/usr/bin/env python3
"""Bounded, JSON-only BetterDisplay access for the SketchyBar display panel."""

import json
import math
import os
import re
import subprocess
import sys
import time

CLI_PATHS = (
    "/opt/homebrew/bin/betterdisplaycli",
    "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay",
)
UUID_PATTERN = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\Z")


class DisplayError(Exception):
    """An actionable integration failure, safe to show in the panel."""


def canonical_uuid(value):
    if not isinstance(value, str) or not UUID_PATTERN.fullmatch(value):
        raise DisplayError("Invalid display identifier")
    return value.upper()


def identifiers(raw):
    """BetterDisplay emits comma-separated objects without enclosing brackets."""
    try:
        value = json.loads(raw if raw.lstrip().startswith("[") else "[" + raw + "]")
    except (TypeError, ValueError) as exc:
        raise DisplayError("BetterDisplay returned invalid display data") from exc
    if not isinstance(value, list):
        raise DisplayError("BetterDisplay returned invalid display data")
    result, seen = [], set()
    for row in value:
        if not isinstance(row, dict) or row.get("deviceType") != "Display":
            continue
        try:
            identity = canonical_uuid(row.get("UUID"))
        except DisplayError:
            continue
        display_id = row.get("displayID")
        if isinstance(display_id, bool) or not re.fullmatch(
            r"[1-9][0-9]*", str(display_id)
        ):
            continue
        if identity in seen:
            continue
        seen.add(identity)
        name = row.get("name")
        result.append(
            {
                "uuid": identity,
                "name": name if isinstance(name, str) and name else "Display",
                "display_id": int(display_id),
            }
        )
    return result


def finite_number(value):
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise DisplayError("BetterDisplay returned invalid brightness") from exc
    if not math.isfinite(result):
        raise DisplayError("BetterDisplay returned invalid brightness")
    return result


def brightness_value(raw):
    result = finite_number(raw.strip())
    if not 0 <= result <= 1:
        raise DisplayError("Brightness is outside the supported 0–100% range")
    return round(result * 100, 3)


class Client:
    def __init__(self, budget):
        self.binary = next(
            (path for path in CLI_PATHS if os.access(path, os.X_OK)), None
        )
        if self.binary is None:
            raise DisplayError("BetterDisplay is not installed")
        self.deadline = time.monotonic() + budget

    def run(self, *arguments):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise DisplayError("BetterDisplay did not respond in time")
        try:
            result = subprocess.run(
                [self.binary, *arguments],
                capture_output=True,
                text=True,
                timeout=min(1.2, remaining),
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise DisplayError("BetterDisplay did not respond in time") from exc
        except OSError as exc:
            raise DisplayError("Could not contact BetterDisplay") from exc
        if result.returncode:
            message = (
                "BetterDisplay Pro is required"
                if "Pro required" in result.stdout
                else "BetterDisplay command failed · open BetterDisplay"
            )
            raise DisplayError(message)
        return result.stdout.strip()

    def displays(self):
        return identifiers(self.run("get", "--identifiers"))

    def read(self, identity, feature):
        return self.run("get", "--UUID=" + identity, "--" + feature)


def snapshot(client, details=True):
    displays = client.displays()
    for display in displays:
        identity = display["uuid"]
        try:
            display["brightness"] = brightness_value(
                client.read(identity, "brightness")
            )
        except DisplayError:
            display["brightness"] = None
        if not details:
            continue
        for feature, key, pattern in (
            ("resolution", "resolution", r"[1-9][0-9]*x[1-9][0-9]*"),
            (
                "refreshRate",
                "refresh_rate",
                r"[0-9]+(?:\.[0-9]+)?(?:-[0-9]+(?:\.[0-9]+)?)?Hz(?:-VRR)?|ProMotion",
            ),
        ):
            try:
                value = client.read(identity, feature)
                display[key] = value if re.fullmatch(pattern, value) else None
            except DisplayError:
                display[key] = None
    mouse_uuid = None
    if details:
        try:
            under_mouse = identifiers(
                client.run("get", "--displayWithMouse", "--identifiers")
            )
            known = {display["uuid"] for display in displays}
            if len(under_mouse) == 1 and under_mouse[0]["uuid"] in known:
                mouse_uuid = under_mouse[0]["uuid"]
        except DisplayError:
            pass
    return {"ok": True, "displays": displays, "mouse_uuid": mouse_uuid}


def set_brightness(client, identity, percentage):
    actual = None
    try:
        if identity not in {display["uuid"] for display in client.displays()}:
            raise DisplayError("Selected display is no longer connected")
        raw = client.run(
            "get", "--UUID=" + identity, "--brightness", "--value", "--min", "--max"
        )
        parts = raw.split(",")
        if len(parts) != 3:
            raise DisplayError("BetterDisplay did not report a brightness range")
        current, lower, upper = [finite_number(part) for part in parts]
        if not 0 <= lower <= current <= upper <= 1:
            raise DisplayError("Brightness is outside the supported 0–100% range")
        actual = round(current * 100, 3)
        if not lower * 100 <= percentage <= upper * 100:
            raise DisplayError("Brightness is outside this display’s supported range")
        client.run(
            "set",
            "--UUID=" + identity,
            "--brightness=" + format(percentage, ".6g") + "%",
        )
        for attempt in range(3):
            try:
                actual = brightness_value(client.read(identity, "brightness"))
                if abs(actual - percentage) <= 1:
                    return {"ok": True, "uuid": identity, "brightness": actual}
            except DisplayError:
                pass
            if attempt < 2 and client.deadline - time.monotonic() > 0.15:
                time.sleep(0.15)
        raise DisplayError(
            "Brightness change could not be verified · refresh or use BetterDisplay"
        )
    except DisplayError as exc:
        return {"ok": False, "error": str(exc), "uuid": identity, "brightness": actual}


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    try:
        if arguments in (["snapshot"], ["levels"]):
            result = snapshot(Client(8), details=arguments == ["snapshot"])
        elif len(arguments) == 3 and arguments[0] == "brightness":
            identity = canonical_uuid(arguments[1])
            percentage = finite_number(arguments[2])
            if not 0 <= percentage <= 100:
                raise DisplayError("Brightness must be between 0 and 100%")
            result = set_brightness(Client(6), identity, percentage)
        else:
            raise DisplayError(
                "Usage: display_control.py snapshot | levels | brightness UUID PERCENT"
            )
    except DisplayError as exc:
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
