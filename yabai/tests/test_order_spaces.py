"""Test the compiled C helper with fake yabai; never changes the live desktop."""
import copy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BINARY = Path(__file__).resolve().parents[1] / 'runtime/order-spaces'


def space(native_id, label, display=1, fullscreen=False, focused=False):
    return {'id': native_id, 'index': native_id, 'label': label, 'display': display,
            'is-native-fullscreen': fullscreen, 'has-focus': focused, 'windows': [native_id + 100]}


FAKE = r'''
import json, os, sys
from pathlib import Path
path = Path(os.environ['FAKE_STATE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
assert args[0] == '-m'
rows = state['rows']
if args[1:] == ['query', '--spaces']:
    state['queries'] += 1
    if state.get('change') == 'monitor' and state['queries'] == 2:
        moving = rows.pop(1)
        moving['display'] = 2
        rows.append(moving)
    if state.get('change') == 'label' and state['queries'] == 2:
        rows[0]['label'], rows[1]['label'] = 'ws-1', 'ws-3'
    if state.get('change') == 'continuous': rows.reverse()
    if state.get('change'):
        for index, row in enumerate(rows, 1): row['index'] = index
    path.write_text(json.dumps(state))
    if state.get('query_fails'):
        print('query rejected', file=sys.stderr)
        sys.exit(1)
    print(state.get('raw', json.dumps(rows)))
else:
    assert len(args) == 5 and args[1] == 'space' and args[3] == '--move', args
    if state.get('fail_move'):
        print('move rejected', file=sys.stderr)
        sys.exit(1)
    source_index, target_index = int(args[2]), int(args[4])
    source, target = rows[source_index - 1], rows[target_index - 1]
    assert source['display'] == target['display'], 'cross-display move'
    assert not source['is-native-fullscreen'] and not target['is-native-fullscreen']
    state['moves'].append([source['id'], target['id'], source_index, target_index])
    if not state.get('ignore_move'):
        rows.pop(source_index - 1)
        rows.insert(target_index - 1, source)
        for index, row in enumerate(rows, 1): row['index'] = index
    path.write_text(json.dumps(state))
'''


class OrderingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state_path = self.root / 'state.json'
        fake = self.root / 'yabai'
        fake.write_text(f'#!{sys.executable}\n' + FAKE)
        fake.chmod(0o755)
        self.env = {**os.environ, 'YABAI_BIN': str(fake), 'FAKE_STATE': str(self.state_path), 'TMPDIR': str(self.root)}

    def prepare(self, rows, **options):
        rows = copy.deepcopy(rows)
        for index, row in enumerate(rows, 1): row['index'] = index
        self.state_path.write_text(json.dumps({'rows': rows, 'queries': 0, 'moves': [], **options}))

    def run_helper(self, *args, expected=0):
        result = subprocess.run([str(BINARY), *args], env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def state(self):
        return json.loads(self.state_path.read_text())

    def labels(self, display=1):
        return [r['label'] for r in self.state()['rows'] if r['display'] == display and not r['is-native-fullscreen']]

    def test_scrambled_spaces_preserve_monitors_windows_and_focus(self):
        rows = [space(31, 'ws-a'), space(55, 'ws-2', focused=True), space(82, '', 2),
                *[space(i + 100, f'ws-{label}', 2) for i, label in enumerate('349567801')],
                space(15, '', 2), space(16, 'custom', 2)]
        def identity(data):
            return {r['id']: (r['display'], r['windows'], r['has-focus']) for r in data}
        self.prepare(rows)
        self.run_helper()
        self.assertEqual(self.labels(), ['ws-2', 'ws-a'])
        self.assertEqual(self.labels(2), [f'ws-{label}' for label in '134567890'] + ['', '', 'custom'])
        self.assertEqual(identity(rows), identity(self.state()['rows']))
        self.assertEqual([r['id'] for r in self.state()['rows'] if r['label'] == ''], [82, 15])
        moves = self.state()['moves']
        self.run_helper()
        self.assertEqual(self.state()['moves'], moves)

    def test_fullscreen_spaces_are_never_sources_or_targets(self):
        self.prepare([space(1, 'ws-3'), space(2, 'Video', fullscreen=True), space(3, 'ws-1'),
                      space(4, 'Other', fullscreen=True), space(5, 'ws-2')])
        self.run_helper()
        self.assertEqual(self.labels(), ['ws-1', 'ws-2', 'ws-3'])
        self.assertTrue(all(s not in {2, 4} and t not in {2, 4} for s, t, _, _ in self.state()['moves']))

    def test_native_indices_are_resolved_after_every_move(self):
        self.prepare([space(90, 'ws-0'), space(70, 'ws-3'), space(60, 'ws-2'), space(50, 'ws-1')])
        self.run_helper()
        self.assertEqual(self.state()['moves'], [[50, 90, 4, 1], [60, 90, 4, 2], [70, 90, 4, 3]])

    def test_monitor_change_invalidates_old_plan(self):
        self.prepare([space(1, 'ws-2'), space(2, 'ws-1'), space(3, 'ws-a', 2)], change='monitor')
        self.run_helper()
        self.assertEqual(self.labels(), ['ws-2'])
        self.assertEqual(self.labels(2), ['ws-1', 'ws-a'])
        self.assertEqual(self.state()['moves'], [[2, 3, 3, 2]])

    def test_label_change_invalidates_old_plan(self):
        self.prepare([space(1, 'ws-3'), space(2, 'ws-1'), space(3, 'ws-2')], change='label')
        self.run_helper()
        self.assertEqual(self.labels(), ['ws-1', 'ws-2', 'ws-3'])
        self.assertEqual(self.state()['moves'][0][:2], [3, 2])

    def test_failed_move_stops(self):
        self.prepare([space(1, 'ws-2'), space(2, 'ws-1')], fail_move=True)
        self.assertIn('move rejected', self.run_helper(expected=2).stderr)
        self.assertEqual(self.state()['moves'], [])

    def test_ignored_moves_are_bounded(self):
        self.prepare([space(1, 'ws-2'), space(2, 'ws-1')], ignore_move=True)
        self.assertIn('did not settle', self.run_helper(expected=2).stderr)
        self.assertEqual(len(self.state()['moves']), 16)

    def test_continuously_changing_topology_is_bounded(self):
        self.prepare([space(1, 'ws-2'), space(2, 'ws-1')], change='continuous')
        self.assertIn('did not settle', self.run_helper(expected=2).stderr)
        self.assertEqual(self.state()['moves'], [])
        self.assertLessEqual(self.state()['queries'], 18)

    def test_unmanaged_order_is_stable(self):
        self.prepare([space(1, ''), space(2, 'custom'), space(3, '', fullscreen=True)])
        self.run_helper()
        self.assertEqual(self.state()['moves'], [])

    def test_malformed_reports_fail_before_moves(self):
        reports = [{}, [None], [space(1, 'ws-1'), space(1, 'ws-2')],
                   [{**space(1, 'ws-1'), 'display': True}], [{**space(1, 'ws-1'), 'index': 1.0}],
                   [{**space(1, 'ws-1'), 'is-native-fullscreen': 'false'}],
                   [{**space(1, 'ws-1'), 'label': None}], [{**space(1, 'ws-1'), 'label': 'ws-1\x00extra'}]]
        for raw in [*(json.dumps(report) for report in reports), 'not JSON', '[] trailing', '[{},]']:
            with self.subTest(raw=raw):
                self.prepare([], raw=raw)
                self.run_helper(expected=2)
                self.assertEqual(self.state()['moves'], [])

    def test_check_and_dry_run_never_mutate(self):
        self.prepare([space(1, 'ws-2'), space(2, 'ws-1')])
        self.run_helper('--check', expected=1)
        self.assertEqual(self.run_helper('--dry-run').stdout, 'Display 1: ws-1#2 ws-2#1\n')
        self.assertEqual(self.state()['moves'], [])
        self.prepare([space(1, 'ws-1')])
        self.run_helper('--check')
        self.prepare([])
        self.run_helper('--check')
        self.assertEqual(self.run_helper('--dry-run').stdout, '')

    def test_errors_and_invalid_arguments_are_visible(self):
        self.prepare([], query_fails=True)
        self.assertIn('query rejected', self.run_helper('--check', expected=2).stderr)
        self.run_helper('--invalid', expected=2)
        self.run_helper('--check', '--dry-run', expected=2)
        self.env['YABAI_BIN'] = '/does/not/exist'
        self.run_helper(expected=2)

    def test_lock_coalesces_and_recovers(self):
        self.prepare([])
        path = self.root / f'yabai-space-order-{os.getuid()}.lock'
        with path.open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_helper()
            self.assertEqual(self.state()['queries'], 0)
        self.assertTrue(path.exists())
        self.run_helper()
        self.assertEqual(self.state()['queries'], 2)

    def test_unsafe_lock_is_rejected(self):
        self.prepare([])
        (self.root / f'yabai-space-order-{os.getuid()}.lock').symlink_to(self.state_path)
        self.run_helper(expected=2)
        self.assertEqual(self.state()['queries'], 0)


if __name__ == '__main__':
    unittest.main()
