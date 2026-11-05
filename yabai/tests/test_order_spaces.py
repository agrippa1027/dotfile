"""Run: python3 -m unittest discover -s yabai/tests -p 'test_*.py'. No live yabai calls."""
import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("order_spaces", Path(__file__).parents[1] / "order-spaces.py")
order = importlib.util.module_from_spec(spec)
spec.loader.exec_module(order)


def space(native_id, label, display=1, fullscreen=False, focused=False):
    return {"id": native_id, "index": native_id, "label": label, "display": display,
            "is-native-fullscreen": fullscreen, "has-focus": focused, "windows": [native_id + 100]}


class FakeYabai:
    def __init__(self, rows):
        self.rows = copy.deepcopy(rows)
        self.moves = []
        self.queries = 0
        self.on_query = None
        self.fail_move = False
        self.ignore_move = False
        self.renumber()

    def renumber(self):
        for index, row in enumerate(self.rows, 1):
            row["index"] = index

    def spaces(self):
        self.queries += 1
        if self.on_query:
            self.on_query(self)
        return order.validate_spaces(copy.deepcopy(self.rows))

    def move(self, source_index, target_index):
        if self.fail_move:
            raise RuntimeError("move rejected by yabai")
        source, target = self.rows[source_index - 1], self.rows[target_index - 1]
        assert source["display"] == target["display"], "cross-display move"
        assert not source["is-native-fullscreen"] and not target["is-native-fullscreen"]
        self.moves.append((source["id"], target["id"], source_index, target_index))
        if not self.ignore_move:
            self.rows.pop(source_index - 1)
            self.rows.insert(target_index - 1, source)
            self.renumber()

    def labels(self, display):
        return [row["label"] for row in self.rows if row["display"] == display and not row["is-native-fullscreen"]]


class OrderingTests(unittest.TestCase):
    def test_scrambled_spaces_keep_monitors_windows_and_focus(self):
        fake = FakeYabai([
            space(31, "ws-a", 1), space(55, "ws-2", 1, focused=True),
            space(82, "", 2), space(6, "ws-3", 2), space(7, "ws-4", 2),
            space(12, "ws-9", 2), space(8, "ws-5", 2), space(9, "ws-6", 2),
            space(10, "ws-7", 2), space(11, "ws-8", 2), space(13, "ws-0", 2),
            space(14, "ws-1", 2), space(15, "", 2), space(16, "custom", 2),
        ])
        identities = {row["id"]: (row["display"], row["windows"], row["has-focus"]) for row in fake.rows}
        self.assertGreater(order.reconcile(fake), 0)
        self.assertEqual(fake.labels(1), ["ws-2", "ws-a"])
        self.assertEqual(fake.labels(2), ["ws-1", "ws-3", "ws-4", "ws-5", "ws-6", "ws-7", "ws-8", "ws-9", "ws-0", "", "", "custom"])
        self.assertEqual(identities, {row["id"]: (row["display"], row["windows"], row["has-focus"]) for row in fake.rows})
        self.assertEqual([row["id"] for row in fake.rows if row["label"] == ""], [82, 15])
        count = len(fake.moves)
        self.assertEqual(order.reconcile(fake), 0)
        self.assertEqual(len(fake.moves), count)

    def test_fullscreen_spaces_are_never_sources_or_targets(self):
        fake = FakeYabai([space(1, "ws-3"), space(2, "Video", fullscreen=True),
                          space(3, "ws-1"), space(4, "Other", fullscreen=True), space(5, "ws-2")])
        order.reconcile(fake)
        self.assertEqual(fake.labels(1), ["ws-1", "ws-2", "ws-3"])
        self.assertEqual([row["id"] for row in fake.rows if row["is-native-fullscreen"]], [2, 4])
        self.assertTrue(all(source not in {2, 4} and target not in {2, 4} for source, target, _, _ in fake.moves))

    def test_native_indices_are_resolved_again_after_every_move(self):
        fake = FakeYabai([space(90, "ws-0"), space(70, "ws-3"), space(60, "ws-2"), space(50, "ws-1")])
        order.reconcile(fake)
        self.assertEqual(fake.labels(1), ["ws-1", "ws-2", "ws-3", "ws-0"])
        self.assertEqual(fake.moves, [(50, 90, 4, 1), (60, 90, 4, 2), (70, 90, 4, 3)])

    def test_user_monitor_move_between_queries_invalidates_old_plan(self):
        fake = FakeYabai([space(1, "ws-2"), space(2, "ws-1"), space(3, "ws-a", 2)])
        def changed(client):
            if client.queries == 2:
                moving = client.rows.pop(1)
                moving["display"] = 2
                client.rows.append(moving)
                client.renumber()
        fake.on_query = changed
        order.reconcile(fake)
        self.assertEqual(fake.labels(1), ["ws-2"])
        self.assertEqual(fake.labels(2), ["ws-1", "ws-a"])
        self.assertEqual(fake.moves, [(2, 3, 3, 2)])

    def test_moving_target_stays_on_current_monitor_even_when_labels_change(self):
        fake = FakeYabai([space(1, "ws-3"), space(2, "ws-1"), space(3, "ws-2")])
        def relabeled(client):
            if client.queries == 2:
                client.rows[0]["label"], client.rows[1]["label"] = "ws-1", "ws-3"
        fake.on_query = relabeled
        order.reconcile(fake)
        self.assertEqual(fake.labels(1), ["ws-1", "ws-2", "ws-3"])
        self.assertEqual(fake.moves[0][:2], (3, 2))

    def test_failed_move_does_not_continue(self):
        fake = FakeYabai([space(1, "ws-2"), space(2, "ws-1")])
        fake.fail_move = True
        with self.assertRaisesRegex(RuntimeError, "move rejected"):
            order.reconcile(fake)
        self.assertEqual(fake.moves, [])

    def test_success_without_actual_movement_is_bounded(self):
        fake = FakeYabai([space(1, "ws-2"), space(2, "ws-1")])
        fake.ignore_move = True
        with self.assertRaisesRegex(RuntimeError, "did not settle"):
            order.reconcile(fake)
        self.assertEqual(len(fake.moves), 16)

    def test_continuously_changing_topology_is_bounded(self):
        fake = FakeYabai([space(1, "ws-2"), space(2, "ws-1")])
        def changing(client):
            client.rows.reverse()
            client.renumber()
        fake.on_query = changing
        with self.assertRaisesRegex(RuntimeError, "did not settle"):
            order.reconcile(fake)
        self.assertEqual(fake.moves, [])
        self.assertLessEqual(fake.queries, 18)

    def test_unmanaged_only_order_stays_stable(self):
        fake = FakeYabai([space(1, ""), space(2, "custom"), space(3, "", fullscreen=True)])
        self.assertEqual(order.reconcile(fake), 0)
        self.assertEqual(fake.moves, [])

    def test_malformed_reports_fail_before_any_plan(self):
        for report in ({}, [None], [space(1, "ws-1"), space(1, "ws-2")],
                       [{**space(1, "ws-1"), "display": True}],
                       [{**space(1, "ws-1"), "is-native-fullscreen": "false"}],
                       [{**space(1, "ws-1"), "label": None}]):
            with self.subTest(report=report), self.assertRaises(ValueError):
                order.validate_spaces(report)

    def test_check_and_dry_run_never_mutate(self):
        fake = FakeYabai([space(1, "ws-2"), space(2, "ws-1")])
        output = io.StringIO()
        with mock.patch.object(order, "Yabai", return_value=fake), contextlib.redirect_stdout(output):
            self.assertEqual(order.main(["--check"]), 1)
            self.assertEqual(order.main(["--dry-run"]), 0)
        self.assertIn("Display 1: ws-1#2 ws-2#1", output.getvalue())
        self.assertEqual(fake.moves, [])
        fake.rows.reverse()
        fake.renumber()
        with mock.patch.object(order, "Yabai", return_value=fake):
            self.assertEqual(order.main(["--check"]), 0)

    def test_query_errors_are_visible_and_nonzero(self):
        fake = FakeYabai([])
        with mock.patch.object(fake, "spaces", side_effect=ValueError("bad JSON")), \
             mock.patch.object(order, "Yabai", return_value=fake), contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(order.main(["--check"]), 2)
        self.assertIn("bad JSON", errors.getvalue())

    def test_cli_invokes_only_structured_yabai_arguments(self):
        client = order.Yabai("/test/yabai")
        response = subprocess.CompletedProcess([], 0, "[]", "")
        with mock.patch.object(order.subprocess, "run", return_value=response) as runner:
            self.assertEqual(client.spaces(), [])
            client.move(4, 2)
        self.assertEqual(runner.call_args.args[0], ["/test/yabai", "-m", "space", "4", "--move", "2"])
        self.assertNotIn("shell", runner.call_args.kwargs)
        with mock.patch.object(order.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "not available")):
            with self.assertRaisesRegex(RuntimeError, "not available"):
                client.spaces()

    def test_lock_coalesces_and_recovers_from_persistent_file(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "order.lock"
            with order.order_lock(path) as first:
                self.assertTrue(first)
                with order.order_lock(path) as second:
                    self.assertFalse(second)
            self.assertTrue(path.exists())
            with order.order_lock(path) as after_release:
                self.assertTrue(after_release)


if __name__ == "__main__":
    unittest.main()
