"""Run with python3 -m unittest discover -s sketchybar/tests -p 'test_display_control.py'."""

import contextlib
import importlib.util
import io
import json
import subprocess
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "display_control", Path(__file__).parents[1] / "helpers/display_control.py"
)
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)
FIRST = "11111111-2222-3333-4444-555555555555"
SECOND = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


def row(identity=FIRST, name="Desk display", display_id="2", kind="Display"):
    return {"UUID": identity, "name": name, "displayID": display_id, "deviceType": kind}


def result(output="", status=0):
    return subprocess.CompletedProcess([], status, output, "")


class BridgeTests(unittest.TestCase):
    def client(self, responses, budget=8):
        access = mock.patch.object(display.os, "access", return_value=True)
        access.start()
        self.addCleanup(access.stop)
        run = mock.patch.object(
            display.subprocess, "run", side_effect=responses
        ).start()
        self.addCleanup(mock.patch.stopall)
        return display.Client(budget), run

    def test_comma_objects_preserve_names_and_skip_groups_and_duplicates(self):
        name = "Afsal’s 'display'; $(touch nope)"
        raw = ",".join(
            json.dumps(value)
            for value in [
                row(name=name),
                row(kind="DisplayGroup"),
                row(),
                row(SECOND.lower(), display_id="3"),
            ]
        )
        parsed = display.identifiers(raw)
        self.assertEqual([item["uuid"] for item in parsed], [FIRST, SECOND])
        self.assertEqual(parsed[0]["name"], name)
        self.assertEqual(parsed[1]["display_id"], 3)

    def test_single_and_array_forms_and_empty_list(self):
        self.assertEqual(len(display.identifiers(json.dumps(row()))), 1)
        self.assertEqual(len(display.identifiers(json.dumps([row(), row(SECOND)]))), 2)
        self.assertEqual(display.identifiers("[]"), [])

    def test_malformed_discovery_is_error_and_bad_rows_are_ignored(self):
        with self.assertRaises(display.DisplayError):
            display.identifiers("Failed.")
        bad = [
            row("bad"),
            row(display_id="0"),
            row(display_id="-1"),
            row(display_id=True),
            row(display_id="2.2"),
            row(display_id=None),
            row(kind="VirtualScreen"),
        ]
        self.assertEqual(display.identifiers(json.dumps(bad)), [])

    def test_snapshot_is_read_only_and_brightness_is_fractional(self):
        client, run = self.client(
            [
                result(json.dumps(row())),
                result("0.988"),
                result("2560x1440"),
                result("85.05Hz"),
                result(json.dumps(row())),
            ]
        )
        answer = display.snapshot(client)
        self.assertTrue(answer["ok"])
        self.assertEqual(answer["mouse_uuid"], FIRST)
        self.assertEqual(answer["displays"][0]["brightness"], 98.8)
        self.assertEqual(answer["displays"][0]["refresh_rate"], "85.05Hz")
        for call in run.call_args_list:
            self.assertEqual(call.args[0][1], "get")
            self.assertNotIn("shell", call.kwargs)
            self.assertLessEqual(call.kwargs["timeout"], 1.2)

    def test_periodic_levels_read_only_identity_and_brightness(self):
        client, run = self.client(
            [result(json.dumps([row(), row(SECOND)])), result("0.988"), result("0.5")]
        )
        answer = display.snapshot(client, details=False)
        self.assertEqual(
            [entry["brightness"] for entry in answer["displays"]], [98.8, 50]
        )
        self.assertEqual(run.call_count, 3)
        self.assertIsNone(answer["mouse_uuid"])
        self.assertNotIn("resolution", answer["displays"][0])
        self.assertTrue(all(call.args[0][1] == "get" for call in run.call_args_list))

    def test_unavailable_fields_do_not_hide_other_displays(self):
        client, _ = self.client(
            [
                result(json.dumps([row(), row(SECOND)])),
                result("Failed.", 1),
                result("garbage"),
                result("nanHz"),
                result("0.5"),
                result("1920x1080"),
                result("60Hz"),
                result("Failed.", 1),
            ]
        )
        answer = display.snapshot(client)
        self.assertIsNone(answer["displays"][0]["brightness"])
        self.assertIsNone(answer["displays"][0]["resolution"])
        self.assertEqual(answer["displays"][1]["brightness"], 50)
        self.assertIsNone(answer["mouse_uuid"])

    def test_nonfinite_or_multiple_brightness_values_are_rejected(self):
        for value in ("nan", "inf", "-inf", "0.2,0.3", "-0.1", "1.2", "Failed."):
            with self.subTest(value=value), self.assertRaises(display.DisplayError):
                display.brightness_value(value)

    def test_snapshot_discovery_timeout_is_bounded_and_reports_error(self):
        client, run = self.client([subprocess.TimeoutExpired("betterdisplaycli", 1.2)])
        with self.assertRaisesRegex(display.DisplayError, "in time"):
            display.snapshot(client)
        self.assertEqual(run.call_count, 1)

    def test_expired_total_budget_never_launches_another_process(self):
        client, run = self.client([])
        client.deadline = display.time.monotonic() - 1
        with self.assertRaises(display.DisplayError):
            client.run("get", "--identifiers")
        run.assert_not_called()

    def test_exact_uuid_mutation_reads_back_and_never_uses_display_name(self):
        client, run = self.client(
            [
                result(json.dumps(row(name="$(oops)"))),
                result("0.5,0.0,1.0"),
                result("Succeeded."),
                result("0.625"),
            ]
        )
        answer = display.set_brightness(client, FIRST, 62.5)
        self.assertEqual(answer, {"ok": True, "uuid": FIRST, "brightness": 62.5})
        self.assertEqual(
            run.call_args_list[2].args[0][1:],
            ["set", "--UUID=" + FIRST, "--brightness=62.5%"],
        )

    def test_disconnected_target_never_mutates(self):
        client, run = self.client([result(json.dumps(row(SECOND)))])
        answer = display.set_brightness(client, FIRST, 50)
        self.assertFalse(answer["ok"])
        self.assertIn("no longer connected", answer["error"])
        self.assertEqual(run.call_count, 1)

    def test_delayed_readback_retries_reads_but_never_write(self):
        client, run = self.client(
            [
                result(json.dumps(row())),
                result("0.5,0,1"),
                result("Succeeded."),
                result("0.5"),
                result("0.6"),
            ]
        )
        with mock.patch.object(display.time, "sleep"):
            answer = display.set_brightness(client, FIRST, 60)
        self.assertTrue(answer["ok"])
        self.assertEqual(
            sum(call.args[0][1] == "set" for call in run.call_args_list), 1
        )

    def test_readback_mismatch_is_error_with_actual_level(self):
        client, run = self.client(
            [
                result(json.dumps(row())),
                result("0.5,0,1"),
                result("Succeeded."),
                result("0.5"),
                result("0.5"),
                result("0.5"),
            ]
        )
        with mock.patch.object(display.time, "sleep"):
            answer = display.set_brightness(client, FIRST, 60)
        self.assertFalse(answer["ok"])
        self.assertEqual(answer["brightness"], 50)
        self.assertEqual(
            sum(call.args[0][1] == "set" for call in run.call_args_list), 1
        )

    def test_failed_write_is_not_retried(self):
        client, run = self.client(
            [result(json.dumps(row())), result("0.5,0,1"), result("Failed.", 1)]
        )
        answer = display.set_brightness(client, FIRST, 60)
        self.assertFalse(answer["ok"])
        self.assertEqual(run.call_count, 3)

    def test_bad_or_hdr_range_never_mutates(self):
        for bounds in ("0.5", "0.5,0,nan", "1.2,0,1.5", "0.5,0.6,1", "0.5,0.4,0.6"):
            with self.subTest(bounds=bounds):
                client, run = self.client([result(json.dumps(row())), result(bounds)])
                answer = display.set_brightness(client, FIRST, 20)
                self.assertFalse(answer["ok"])
                self.assertEqual(run.call_count, 2)

    def test_invalid_action_arguments_never_launch_processes(self):
        with mock.patch.object(display.subprocess, "run") as run:
            for arguments in (
                ["brightness", "bad", "50"],
                ["brightness", FIRST, "NaN"],
                ["brightness", FIRST, "-1"],
                ["brightness", FIRST, "101"],
                ["set"],
            ):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(display.main(arguments), 1)
                self.assertFalse(json.loads(output.getvalue())["ok"])
            run.assert_not_called()

    def test_missing_cli_and_app_fallback(self):
        with mock.patch.object(display.os, "access", return_value=False):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(display.main(["snapshot"]), 1)
            self.assertIn("not installed", json.loads(output.getvalue())["error"])
        with mock.patch.object(display.os, "access", side_effect=[False, True]):
            self.assertEqual(display.Client(8).binary, display.CLI_PATHS[1])


if __name__ == "__main__":
    unittest.main()
