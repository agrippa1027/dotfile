"""Exercise wm.sh against a fake yabai; never touches the live desktop."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "wm.sh"


def space(index, label="", *, focused=False, fullscreen=False, display=1):
    return {
        "index": index,
        "label": label,
        "display": display,
        "has-focus": focused,
        "is-native-fullscreen": fullscreen,
    }


class WorkspaceNavigation(unittest.TestCase):
    def run_helper(self, spaces, *arguments, query_fails=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "yabai"
            fake.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "args = sys.argv[1:]\n"
                "assert args[0] == '-m'\n"
                "if args[1:] == ['query', '--spaces']:\n"
                "    if os.environ['QUERY_FAILS'] == '1': sys.exit(1)\n"
                "    print(os.environ['SPACES'])\n"
                "else:\n"
                "    with Path(os.environ['COMMAND_LOG']).open('a') as output:\n"
                "        output.write(json.dumps(args[1:]) + '\\n')\n"
            )
            fake.chmod(0o755)
            log = root / "commands.jsonl"
            result = subprocess.run(
                ["/bin/bash", str(HELPER), *arguments],
                env={
                    **os.environ,
                    "YABAI_BIN": str(fake),
                    "SPACES": json.dumps(spaces),
                    "QUERY_FAILS": str(int(query_fails)),
                    "COMMAND_LOG": str(log),
                },
                text=True,
                capture_output=True,
            )
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, commands

    def assert_focus(self, spaces, direction, destination):
        result, commands = self.run_helper(spaces, "cycle-space", direction)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands, [["space", "--focus", destination]])

    def test_logical_order_ignores_native_indices_and_monitor_grouping(self):
        spaces = [
            space(1, "ws-a", display=1),
            space(2, "ws-2", display=1),
            space(3, "ws-9", display=2),
            space(4, "ws-1", focused=True, display=2),
            space(5, "ws-3", display=2),
        ]
        self.assert_focus(spaces, "next", "ws-2")
        spaces[3]["has-focus"] = False
        spaces[1]["has-focus"] = True
        self.assert_focus(spaces, "prev", "ws-1")
        self.assert_focus(spaces, "next", "ws-3")

    def test_zero_and_a_wrap_after_nine(self):
        spaces = [space(1, "ws-a"), space(2, "ws-0"), space(3, "ws-9", focused=True), space(4, "ws-1")]
        self.assert_focus(spaces, "next", "ws-0")
        spaces[2]["has-focus"] = False
        spaces[1]["has-focus"] = True
        self.assert_focus(spaces, "next", "ws-a")
        spaces[1]["has-focus"] = False
        spaces[0]["has-focus"] = True
        self.assert_focus(spaces, "next", "ws-1")
        spaces[0]["has-focus"] = False
        spaces[3]["has-focus"] = True
        self.assert_focus(spaces, "prev", "ws-a")

    def test_unmanaged_and_fullscreen_spaces_are_skipped(self):
        spaces = [space(1, "ws-1", focused=True), space(2, ""), space(3, "custom"), space(4, "ws-2", fullscreen=True), space(5, "ws-3")]
        self.assert_focus(spaces, "next", "ws-3")
        spaces[0]["has-focus"] = False
        spaces[1]["has-focus"] = True
        self.assert_focus(spaces, "next", "ws-1")
        self.assert_focus(spaces, "prev", "ws-3")

    def test_bootstrap_without_managed_labels_keeps_native_order(self):
        spaces = [space(5), space(2, focused=True), space(3, fullscreen=True)]
        self.assert_focus(spaces, "next", "5")
        self.assert_focus(spaces, "prev", "5")

    def test_invalid_direction_empty_and_failed_queries_never_focus(self):
        for spaces, direction, fails in [([], "next", False), ([space(1, fullscreen=True)], "prev", False), ([space(1)], "sideways", False), ([space(1)], "next", True)]:
            with self.subTest(spaces=spaces, direction=direction, fails=fails):
                result, commands = self.run_helper(spaces, "cycle-space", direction, query_fails=fails)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands, [])

    def test_named_focus_and_window_moves_use_stable_labels(self):
        spaces = [space(12, "ws-1")]
        for arguments, expected in [
            (("space", "1"), [["space", "--focus", "ws-1"]]),
            (("move", "1"), [["window", "--space", "ws-1"]]),
            (("move", "1", "follow"), [["window", "--space", "ws-1"], ["space", "--focus", "ws-1"]]),
        ]:
            result, commands = self.run_helper(spaces, *arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(commands, expected)
        for label in ("missing", "1; open x", "", "11"):
            result, commands = self.run_helper(spaces, "space", label)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(commands, [])
        result, commands = self.run_helper(spaces, "move", "2")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])


if __name__ == "__main__":
    unittest.main()
