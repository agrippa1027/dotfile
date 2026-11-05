"""Pure/mocked activation tests. Never run yabai, sudo, launchctl or Quartz.

Run: python3 -m unittest discover -s yabai/tests -p 'test_activate_resize.py'
"""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location('activate_resize', Path(__file__).parents[1] / 'activate-resize.py')
assert spec is not None and spec.loader is not None
activation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(activation)


def report():
    spaces, windows = [], []
    for index, label in enumerate(activation.LABELS, 1):
        spaces.append({'id': 1000 + index, 'index': index, 'label': label,
                       'display': 1 if index <= 10 else 2, 'windows': [2000 + index],
                       'is-native-fullscreen': False, 'is-visible': index in (1, 11),
                       'has-focus': index == 1})
        windows.append({'id': 2000 + index, 'space': index, 'display': spaces[-1]['display'],
                        'has-focus': index == 1})
    displays = [{'id': 90 + index, 'uuid': f'display-{index}', 'index': index,
                 'label': f'monitor-{index}', 'has-focus': index == 1,
                 'frame': {'x': (index - 1) * 1920, 'y': 0, 'w': 1920, 'h': 1080}}
                for index in (1, 2)]
    return {'spaces': spaces, 'displays': displays, 'windows': windows, 'pointer': [-30.5, 100.25]}


class FakePointer:
    def __init__(self, point=None):
        self.point = list(point or report()['pointer'])
        self.restorations = []

    def get(self):
        return list(self.point)

    def restore(self, point):
        self.point = list(point)
        self.restorations.append(list(point))


class FakeYabai:
    def __init__(self, saved, pointer):
        self.saved = copy.deepcopy(saved)
        self.pointer = pointer
        self.commands = []
        self.follows = 'on'

    def focus_space(self, selected):
        for space in self.saved['spaces']:
            if space['display'] == selected['display']:
                space['is-visible'] = space['id'] == selected['id']
            space['has-focus'] = space['id'] == selected['id']
        for display in self.saved['displays']:
            display['has-focus'] = display['index'] == selected['display']
        if self.follows == 'on':
            self.pointer.point = [999, 999]

    def __call__(self, *args):
        self.commands.append(args)
        if args[0] == 'query':
            # Reverse enumeration to catch accidental reliance on array position.
            return json.dumps(list(reversed(self.saved[args[1][2:]])))
        if args[:2] == ('config', 'mouse_follows_focus'):
            if len(args) == 3:
                self.follows = args[2]
            return self.follows + '\n'
        if args[:2] == ('space', '--focus'):
            if len(args) != 3:
                raise AssertionError('Space focus requires a destination')
            selected = next(row for row in self.saved['spaces'] if row['index'] == args[2])
            self.focus_space(selected)
            return ''
        noun, selector, action, *values = args
        key = {'space': 'spaces', 'display': 'displays', 'window': 'windows'}[noun]
        field = 'id' if noun == 'window' else 'index'
        selected = next(row for row in self.saved[key] if row[field] == selector)
        if action == '--label':
            selected['label'] = values[0]
        elif action == '--focus' and noun == 'space':
            raise AssertionError('Use space --focus DESTINATION')
        elif action == '--focus' and noun == 'window':
            for window in self.saved['windows']:
                window['has-focus'] = window['id'] == selected['id']
            self.focus_space(next(s for s in self.saved['spaces'] if s['index'] == selected['space']))
        else:
            raise AssertionError(f'Unexpected command: {args}')
        return ''


class MappingTests(unittest.TestCase):
    def test_mock_rejects_space_focus_without_destination(self):
        fake = FakeYabai(report(), FakePointer())
        with self.assertRaisesRegex(AssertionError, 'space --focus DESTINATION'):
            fake('space', 1, '--focus')

    def test_safe_setup_preserves_unusual_existing_monitor_assignments(self):
        saved = report()
        # No assumption that ws-a belongs to the smaller display, or ws-1 to the larger one.
        saved['spaces'][0]['display'], saved['spaces'][-1]['display'] = 2, 1
        activation.safe_setup(saved)

    def test_missing_label_or_unordered_spaces_refused(self):
        for mutation in ('missing', 'order', 'fullscreen'):
            saved = report()
            if mutation == 'missing':
                saved['spaces'][3]['label'] = ''
            elif mutation == 'order':
                saved['spaces'][0]['label'], saved['spaces'][1]['label'] = 'ws-2', 'ws-1'
            else:
                saved['spaces'][3]['is-native-fullscreen'] = True
            with self.subTest(mutation=mutation), self.assertRaises(RuntimeError):
                activation.safe_setup(saved)

    def test_malformed_reports_fail_closed(self):
        mutations = [lambda r: r.update(spaces={}),
                     lambda r: r['spaces'].append(copy.deepcopy(r['spaces'][0])),
                     lambda r: r['spaces'][0].update(index=True),
                     lambda r: r['spaces'][0].update(label=None),
                     lambda r: r['spaces'][0].update(windows=['bad']),
                     lambda r: r['spaces'][0].update(display=99),
                     lambda r: r['spaces'][1].update(**{'has-focus': True}),
                     lambda r: r['spaces'][1].update(**{'is-visible': True}),
                     lambda r: r['windows'][0].update(space=None),
                     lambda r: r.update(pointer=[float('nan'), 0])]
        for mutate in mutations:
            saved = report()
            mutate(saved)
            with self.subTest(mutate=mutate), self.assertRaises(RuntimeError):
                activation.validate_snapshot(saved)

    def test_labels_restore_by_native_id_before_other_configuration(self):
        saved, pointer = report(), FakePointer()
        fake = FakeYabai(saved, pointer)
        for key in ('spaces', 'displays'):
            for row in fake.saved[key]:
                row['label'] = ''
        with mock.patch.object(activation, 'yabai', side_effect=fake):
            activation.restore_labels(saved, pointer)
            restored = activation.snapshot(pointer)
        self.assertEqual(activation.topology(saved), activation.topology(restored))
        self.assertEqual(activation.context(saved), activation.context(restored))
        mutations = [args for args in fake.commands if args[0] != 'query']
        self.assertTrue(mutations)
        self.assertTrue(all(args[2] == '--label' for args in mutations))
        self.assertEqual(pointer.restorations, [])

    def test_changed_topology_is_not_repaired_with_moves_or_creations(self):
        for key in ('id', 'index', 'display'):
            saved, pointer = report(), FakePointer()
            fake = FakeYabai(saved, pointer)
            fake.saved['spaces'][0][key] = 99 if key != 'display' else 2
            with self.subTest(key=key), mock.patch.object(activation, 'yabai', side_effect=fake), \
                 self.assertRaises(RuntimeError):
                activation.restore_labels(saved, pointer)
            self.assertTrue(all(args[0] == 'query' for args in fake.commands))

    def test_conflicting_live_labels_are_not_overwritten(self):
        saved, pointer = report(), FakePointer()
        fake = FakeYabai(saved, pointer)
        fake.saved['spaces'][0]['label'] = 'unexpected'
        with mock.patch.object(activation, 'yabai', side_effect=fake), \
             self.assertRaisesRegex(RuntimeError, 'Unexpected live label'):
            activation.restore_labels(saved, pointer)
        self.assertTrue(all(args[0] == 'query' for args in fake.commands))

    def test_window_membership_drift_blocks_config(self):
        saved, pointer = report(), FakePointer()
        fake = FakeYabai(saved, pointer)
        fake.saved['windows'][0]['space'] = 2
        with mock.patch.object(activation, 'yabai', side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, 'window membership'):
                activation.restore_labels(saved, pointer)
            with self.assertRaisesRegex(RuntimeError, 'window membership'):
                activation.restore_context(saved, pointer)

    def test_accessibility_settings_window_can_open_without_invalidating_captured_memberships(self):
        saved, pointer = report(), FakePointer()
        fake = FakeYabai(saved, pointer)
        for key in ('spaces', 'displays'):
            for row in fake.saved[key]:
                row['label'] = ''
        for window in fake.saved['windows']:
            window['has-focus'] = False
        fake.saved['windows'].append({'id': 9999, 'space': 11, 'display': 2, 'has-focus': True})
        fake.saved['spaces'][-1]['windows'].append(9999)
        fake.focus_space(fake.saved['spaces'][-1])
        with mock.patch.object(activation, 'yabai', side_effect=fake):
            activation.restore_labels(saved, pointer)
            activation.restore_context(saved, pointer)
            latest = activation.snapshot(pointer)
        self.assertTrue(activation.mappings_match(saved, latest))
        self.assertEqual(activation.context(saved), activation.context(latest))
        self.assertIn(9999, latest['spaces'][0]['windows'])  # query enumeration is reversed
        self.assertEqual(pointer.point, saved['pointer'])

    def test_missing_captured_window_is_not_ignored_like_new_permission_ui(self):
        saved, current = report(), report()
        current['windows'].pop()
        current['spaces'][-1]['windows'].clear()
        self.assertFalse(activation.mappings_match(saved, current))

    def test_visible_spaces_focus_and_pointer_restore_without_mouse_follow(self):
        saved, pointer = report(), FakePointer([500, 600])
        fake = FakeYabai(saved, pointer)
        fake.focus_space(fake.saved['spaces'][1])
        for window in fake.saved['windows']:
            window['has-focus'] = window['id'] == 2002
        with mock.patch.object(activation, 'yabai', side_effect=fake):
            activation.restore_context(saved, pointer)
            latest = activation.snapshot(pointer)
        self.assertEqual(activation.topology(saved), activation.topology(latest))
        self.assertEqual(activation.context(saved), activation.context(latest))
        self.assertEqual(pointer.point, saved['pointer'])
        self.assertEqual(fake.follows, 'on')
        off = fake.commands.index(('config', 'mouse_follows_focus', 'off'))
        on = fake.commands.index(('config', 'mouse_follows_focus', 'on'))
        focus = [i for i, args in enumerate(fake.commands) if '--focus' in args]
        self.assertTrue(focus and all(off < i < on for i in focus))
        space_focus = [args for args in fake.commands if args[0] == 'space' and '--focus' in args]
        self.assertTrue(space_focus)
        self.assertTrue(all(args[:2] == ('space', '--focus') and len(args) == 3
                            for args in space_focus))
        self.assertFalse(any('--move' in args or '--create' in args or '--display' in args
                             for args in fake.commands))

    def test_snapshot_must_be_stable(self):
        saved, changed = report(), report()
        changed['pointer'][0] += 1
        with mock.patch.object(activation, 'snapshot', side_effect=[saved, changed]), \
             self.assertRaisesRegex(RuntimeError, 'Desktop changed'):
            activation.stable_snapshot(FakePointer())


class FilesAndStartupTests(unittest.TestCase):
    def test_pointer_restore_rounds_to_nearest_pixel(self):
        pointer = activation.Pointer.__new__(activation.Pointer)
        pointer.cg = mock.Mock()
        pointer.cg.CGWarpMouseCursorPosition.return_value = 0
        for saved in ([420.40234375, 644.62109375], [-1530.8, -40.2], [1.5, -3.5]):
            pointer.restore(saved)
            sent = pointer.cg.CGWarpMouseCursorPosition.call_args.args[0]
            self.assertEqual((sent.x, sent.y), tuple(round(value) for value in saved))
            self.assertTrue(all(abs(a - b) <= 0.5 for a, b in zip(saved, (sent.x, sent.y))))

    def test_pointer_restore_still_rejects_quartz_failure(self):
        pointer = activation.Pointer.__new__(activation.Pointer)
        pointer.cg = mock.Mock()
        pointer.cg.CGWarpMouseCursorPosition.return_value = 1
        with self.assertRaisesRegex(RuntimeError, 'Cannot restore pointer'):
            pointer.restore([100.2, 200.8])

    def test_wrapper_uses_explicit_config_and_never_global_environment(self):
        with tempfile.TemporaryDirectory(prefix='activation with spaces ') as temporary:
            directory = Path(temporary)
            plist = {'Label': 'com.asmvik.yabai', 'ProgramArguments': [str(activation.BINARY)],
                     'EnvironmentVariables': {'PATH': '/usr/bin:/bin'}}
            original = copy.deepcopy(plist)
            record = {'attempt': 'test-token'}
            activation.write_wrapper(directory, record, plist)
            wrapper = (directory / 'yabairc').read_text()
            self.assertIn('--startup', wrapper)
            self.assertIn("'" + str(directory) + "'", wrapper)
            self.assertFalse(os.access(directory / 'yabairc', os.X_OK))
            staged = plistlib.loads((directory / 'service.plist').read_bytes())
            self.assertEqual(staged['ProgramArguments'],
                             [str(activation.BINARY), '--config', str(directory / 'yabairc')])
            self.assertFalse(staged['AbandonProcessGroup'])
            self.assertEqual(staged['EnvironmentVariables']['XDG_CONFIG_HOME'], str(activation.ROOT.parent))
            self.assertEqual(plist, original)
            activation.write_wrapper(directory, record, plist, guarded=False)
            self.assertNotIn('--startup', (directory / 'yabairc').read_text())
            self.assertIn('/bin/bash', (directory / 'yabairc').read_text())

    def test_startup_restores_labels_before_normal_config_then_context(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            record = {'attempt': 'token', 'state': 'starting', 'expected_hash': activation.AFTER,
                      'snapshot': report()}
            events = []
            with mock.patch.object(activation, 'read_record', return_value=record), \
                 mock.patch.object(activation, 'check_config'), \
                 mock.patch.object(activation, 'sha', return_value=activation.AFTER), \
                 mock.patch.object(activation, 'Pointer', return_value=FakePointer()), \
                 mock.patch.object(activation, 'restore_labels', side_effect=lambda *a: events.append('labels')), \
                 mock.patch.object(activation, 'run', side_effect=lambda *a, **kw: events.append('config')), \
                 mock.patch.object(activation, 'restore_context', side_effect=lambda *a: events.append('context')):
                self.assertEqual(activation.startup(directory, 'token'), 0)
            self.assertEqual(events, ['labels', 'config', 'context'])
            self.assertTrue((directory / 'token.ready').exists())

    def test_failed_early_label_guard_never_runs_normal_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            record = {'attempt': 'token', 'state': 'starting', 'expected_hash': activation.AFTER,
                      'snapshot': report()}
            with mock.patch.object(activation, 'read_record', return_value=record), \
                 mock.patch.object(activation, 'check_config'), \
                 mock.patch.object(activation, 'sha', return_value=activation.AFTER), \
                 mock.patch.object(activation, 'Pointer'), \
                 mock.patch.object(activation, 'restore_labels', side_effect=RuntimeError('topology drift')), \
                 mock.patch.object(activation, 'run') as runner, \
                 self.assertRaisesRegex(RuntimeError, 'topology drift'):
                activation.startup(directory, 'token')
            runner.assert_not_called()
            self.assertEqual((directory / 'token.error').read_text(), 'topology drift')
            self.assertFalse((directory / 'token.ready').exists())

    def test_stale_attempt_is_rejected(self):
        with mock.patch.object(activation, 'read_record', return_value={'attempt': 'new', 'state': 'starting'}), \
             mock.patch.object(activation, 'run') as runner, \
             self.assertRaisesRegex(RuntimeError, 'Stale'):
            activation.startup(Path('/unused'), 'old')
        runner.assert_not_called()

    def test_bounded_wait_timeout_and_reported_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with mock.patch.object(activation.time, 'monotonic', side_effect=[0, 61]), \
                 self.assertRaisesRegex(RuntimeError, 'Accessibility'):
                activation.wait_ready(directory, 'token', 60)
            (directory / 'token.error').write_text('label restore rejected')
            with self.assertRaisesRegex(RuntimeError, 'label restore rejected'):
                activation.wait_ready(directory, 'token', 60)
            (directory / 'token.error').unlink()
            (directory / 'token.ready').write_text('ready')
            activation.wait_ready(directory, 'token', 60)

    def test_atomic_install_validates_sudoers_before_rename(self):
        calls = []
        with mock.patch.object(activation, 'run', side_effect=lambda *a, **kw: calls.append(a)):
            activation.privileged_replace(Path('/backup/rule'), Path('/etc/example'), [0, 0, 0o440], sudoers=True)
        self.assertEqual([call[2] for call in calls], ['/usr/bin/install', '/usr/sbin/visudo', '/bin/mv', '/bin/rm'])
        staged = calls[0][-1]
        self.assertEqual(staged.parent, Path('/etc'))
        self.assertNotEqual(staged, Path('/etc/example'))
        self.assertEqual(calls[1][-1], staged)
        self.assertEqual(calls[2][-2:], (staged, Path('/etc/example')))
        self.assertIn('440', calls[0])

    def test_failed_staging_never_renames_destination(self):
        calls = []
        def failure(*args, **kwargs):
            calls.append(args)
            if args[2] == '/usr/bin/install':
                raise RuntimeError('install rejected')
        with mock.patch.object(activation, 'run', side_effect=failure), \
             self.assertRaisesRegex(RuntimeError, 'install rejected'):
            activation.privileged_replace(Path('/backup/bin'), Path('/target/bin'), [501, 20, 0o755])
        self.assertFalse(any('/bin/mv' in call for call in calls))
        self.assertEqual(calls[-1][2], '/bin/rm')

    def test_atomic_write_replaces_inode_and_preserves_previous_open_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'binary'
            path.write_bytes(b'old')
            with path.open('rb') as old:
                activation.atomic_write(path, b'new')
                self.assertEqual(old.read(), b'old')
            self.assertEqual(path.read_bytes(), b'new')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_record_integrity_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            target = directory / 'installed'
            target.write_bytes(b'installed')
            (directory / 'binary.before').write_bytes(b'backup')
            (directory / 'sudoers.before').write_bytes(b'original sudoers\r\n')
            before = activation.sha(directory / 'binary.before')
            record = {'version': 1, 'uid': os.getuid(), 'target': str(target.resolve()),
                      'before_hash': before, 'after_hash': activation.AFTER, 'snapshot': report(),
                      'sudoers_hash': activation.sha(directory / 'sudoers.before')}
            activation.journal(directory, record)
            with mock.patch.object(activation, 'BINARY', target), mock.patch.object(activation, 'BEFORE', before):
                self.assertEqual(activation.read_record(directory), record)
                (directory / 'binary.before').write_bytes(b'tampered')
                with self.assertRaisesRegex(RuntimeError, 'integrity'):
                    activation.read_record(directory)
                directory.chmod(0o755)
                with self.assertRaisesRegex(RuntimeError, 'private'):
                    activation.read_record(directory)


class BackupIntegrationTests(unittest.TestCase):
    def test_staging_and_rollback_preserve_symlink_binary_sudoers_and_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'runtime').mkdir()
            target, binary, candidate = root / 'cellar-yabai', root / 'yabai', root / 'candidate'
            target.write_bytes(b'old executable')
            target.chmod(0o755)
            binary.symlink_to(target)
            candidate.write_bytes(b'new executable')
            before, after = activation.sha(target), activation.sha(candidate)
            sudoers = root / 'sudoers'
            rule = f'tester ALL=(root) NOPASSWD: sha256:{before} {binary} --load-sa\n'.encode()
            sudoers.write_bytes(rule)
            sudoers.chmod(0o440)
            original_stat = target.stat()
            calls = []

            def command(*args, **kwargs):
                argv = list(map(str, args))
                calls.append(argv)
                output = '' if kwargs.get('text', True) else b''
                if argv[:2] == ['/usr/bin/id', '-un']:
                    output = 'tester\n'
                elif argv[2] == '/bin/cat':
                    output = Path(argv[-1]).read_bytes()
                elif argv[2] == '/usr/bin/install':
                    shutil.copyfile(argv[-2], argv[-1])
                    os.chmod(argv[-1], int(argv[8], 8))
                elif argv[2] == '/bin/mv':
                    os.replace(argv[-2], argv[-1])
                elif argv[2] == '/bin/rm':
                    Path(argv[-1]).unlink(missing_ok=True)
                elif argv[2] != '/usr/sbin/visudo':
                    raise AssertionError(argv)
                return subprocess.CompletedProcess(argv, 0, output, '')

            with mock.patch.object(activation, 'ROOT', root), \
                 mock.patch.object(activation, 'BINARY', binary), \
                 mock.patch.object(activation, 'SUDOERS', sudoers), \
                 mock.patch.object(activation, 'BEFORE', before), \
                 mock.patch.object(activation, 'AFTER', after), \
                 mock.patch.object(activation, 'config_hashes', return_value={}), \
                 mock.patch.object(activation, 'run', side_effect=command):
                saved = report()
                directory, record = activation.prepare(candidate, saved)
                self.assertEqual((directory / 'binary.before').read_bytes(), b'old executable')
                self.assertEqual((directory / 'sudoers.before').read_bytes(), rule)
                self.assertEqual(record['initial_snapshot'], saved)
                self.assertFalse(any('/bin/mv' in argv for argv in calls))
                activation.install_pair(directory, record, rollback=False)
                self.assertEqual(target.read_bytes(), b'new executable')
                self.assertIn(after.encode(), sudoers.read_bytes())
                self.assertTrue(binary.is_symlink())
                activation.read_record(directory)
                activation.install_pair(directory, record, rollback=True)
                self.assertEqual(target.read_bytes(), b'old executable')
                self.assertEqual(sudoers.read_bytes(), rule)
                self.assertTrue(binary.is_symlink())
                self.assertEqual(target.stat().st_mode & 0o777, original_stat.st_mode & 0o777)
                self.assertEqual(sudoers.stat().st_mode & 0o777, 0o440)
                self.assertEqual((directory / 'binary.before').read_bytes(), b'old executable')
                self.assertEqual((directory / 'sudoers.before').read_bytes(), rule)
                activation.read_record(directory)


class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path('/private/mock-record')
        self.record = {'snapshot': report(), 'state': 'prepared'}
        self.output = contextlib.ExitStack()
        self.addCleanup(self.output.close)
        self.output.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.output.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.output.enter_context(mock.patch.object(activation, 'journal'))
        self.output.enter_context(mock.patch.object(activation, 'check_config'))
        self.output.enter_context(mock.patch.object(activation, 'Pointer', return_value=FakePointer()))
        self.snapshot = self.output.enter_context(mock.patch.object(activation, 'snapshot', return_value=report()))
        self.stop = self.output.enter_context(mock.patch.object(activation, 'stop_service'))
        self.install = self.output.enter_context(mock.patch.object(activation, 'install_pair'))
        self.start = self.output.enter_context(mock.patch.object(activation, 'start_guarded'))

    def test_desktop_change_while_backing_up_stops_before_service_changes(self):
        changed = report()
        changed['spaces'][0]['label'] = 'changed-after-snapshot'
        self.snapshot.return_value = changed
        with self.assertRaisesRegex(RuntimeError, 'nothing replaced'):
            activation.transition(self.directory, self.record, {}, 60)
        self.stop.assert_not_called()
        self.install.assert_not_called()
        self.start.assert_not_called()

    def test_offline_recovery_does_not_query_a_stopped_daemon(self):
        activation.transition(self.directory, self.record, {}, 60, rollback=True, live=False)
        self.snapshot.assert_not_called()
        self.stop.assert_called_once_with(check=False)
        self.install.assert_called_once_with(self.directory, self.record, True)

    def test_timeout_automatically_restores_old_binary_and_sudoers(self):
        self.start.side_effect = [RuntimeError('Accessibility startup timeout'), None]
        with self.assertRaisesRegex(RuntimeError, 'original binary/sudoers restored'):
            activation.transition(self.directory, self.record, {}, 60)
        self.assertEqual(self.install.call_args_list,
                         [mock.call(self.directory, self.record, False),
                          mock.call(self.directory, self.record, rollback=True)])
        self.assertEqual(self.start.call_args_list[-1],
                         mock.call(self.directory, self.record, {}, 60, rollback=True))
        self.assertEqual(self.stop.call_count, 2)

    def test_partial_install_failure_also_rolls_back(self):
        self.install.side_effect = [RuntimeError('sudoers update failed'), None]
        with self.assertRaisesRegex(RuntimeError, 'original binary/sudoers restored'):
            activation.transition(self.directory, self.record, {}, 60)
        self.start.assert_called_once_with(self.directory, self.record, {}, 60, rollback=True)

    def test_interrupt_during_replacement_rolls_back(self):
        self.install.side_effect = [KeyboardInterrupt(), None]
        with self.assertRaisesRegex(RuntimeError, 'original binary/sudoers restored'):
            activation.transition(self.directory, self.record, {}, 60)
        self.start.assert_called_once_with(self.directory, self.record, {}, 60, rollback=True)

    def test_failed_rollback_keeps_backups_and_never_starts_unguarded_config(self):
        self.start.side_effect = RuntimeError('TCC rejected both signatures')
        with self.assertRaisesRegex(RuntimeError, 'Do NOT start the normal service'):
            activation.transition(self.directory, self.record, {}, 60)
        self.assertEqual(self.record['state'], 'rollback-failed')
        self.assertEqual(self.start.call_count, 2)
        self.assertEqual(self.stop.call_count, 3)

    def test_success_disarms_historical_snapshot_for_future_restarts(self):
        with mock.patch.object(activation, 'write_wrapper') as wrapper, \
             mock.patch.object(activation, 'run') as runner, \
             mock.patch.object(activation, 'wait_ready') as wait, \
             mock.patch.object(activation, 'restore_context') as restore, \
             mock.patch.object(activation, 'Pointer'):
            # setUp patched this entry point; exercise its original implementation below.
            real_start_guarded(self.directory, self.record, {}, 60, rollback=False)
        self.assertEqual(self.record['state'], 'active')
        self.assertEqual(self.record['expected_hash'], activation.AFTER)
        self.assertEqual(wrapper.call_args_list[-1], mock.call(self.directory, self.record, {}, guarded=False))
        self.assertEqual(runner.call_args.args[1], 'bootstrap')
        wait.assert_called_once()
        restore.assert_called_once()


real_start_guarded = activation.start_guarded


class CommandAndCandidateTests(unittest.TestCase):
    def test_subprocess_arguments_are_structured_and_bounded(self):
        response = subprocess.CompletedProcess([], 0, 'ok', '')
        with mock.patch.object(activation.subprocess, 'run', return_value=response) as runner:
            activation.run('/test/yabai', '-m', 'space', 9, '--label', 'label; not shell')
        self.assertEqual(runner.call_args.args[0],
                         ['/test/yabai', '-m', 'space', '9', '--label', 'label; not shell'])
        self.assertEqual(runner.call_args.kwargs['timeout'], 10)
        self.assertNotIn('shell', runner.call_args.kwargs)

    def test_noninteractive_authorization_never_prompts(self):
        with mock.patch.object(activation, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'password required')), \
             mock.patch.object(activation.sys.stdin, 'isatty', return_value=False), \
             mock.patch.object(activation.subprocess, 'run') as runner, \
             self.assertRaisesRegex(RuntimeError, 'Nothing changed'):
            activation.authenticate()
        runner.assert_not_called()

    def test_interactive_authorization_is_bounded_then_rechecked(self):
        failure = subprocess.CompletedProcess([], 1, '', '')
        success = subprocess.CompletedProcess([], 0, '', '')
        with mock.patch.object(activation, 'run', side_effect=[failure, success]) as check, \
             mock.patch.object(activation.sys.stdin, 'isatty', return_value=True), \
             mock.patch.object(activation.sys.stdout, 'isatty', return_value=True), \
             mock.patch.object(activation.subprocess, 'run') as prompt:
            activation.authenticate()
        prompt.assert_called_once_with(['/usr/bin/sudo', '-v'], check=True, timeout=120)
        self.assertEqual(check.call_count, 2)

    def test_authorization_lease_never_prompts_and_stops_on_exit(self):
        with mock.patch.object(activation.threading, 'Event') as event, \
             mock.patch.object(activation.threading, 'Thread') as worker, \
             mock.patch.object(activation, 'run') as runner:
            event.return_value.wait.side_effect = [False, True]
            worker.return_value.start.side_effect = lambda: worker.call_args.kwargs['target']()
            with activation.authorization_lease():
                runner.assert_called_once_with('/usr/bin/sudo', '-n', '-v')
                event.return_value.set.assert_not_called()
            event.return_value.set.assert_called_once()
            worker.return_value.join.assert_called_once_with(timeout=11)

    def test_candidate_pins_signature_architectures_and_embedded_source_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary_dir, source_dir = root / 'bin', root / 'src/osax'
            binary_dir.mkdir()
            source_dir.mkdir(parents=True)
            candidate, installed, info = binary_dir / 'yabai', root / 'installed', root / 'Info.plist'
            payload, loader = b'payload-data', b'loader-data'
            candidate.write_bytes(b'candidate' + payload + loader)
            candidate.chmod(0o755)
            installed.write_bytes(b'installed' + payload + loader)
            info.write_bytes(plistlib.dumps({'CFBundleVersion': '2.1.30'}))
            pins = {}
            for name, data in [('payload', payload), ('loader', loader)]:
                (source_dir / (name + '_bin.c')).write_text(', '.join(f'0x{n:02x}' for n in data))
                pins[name] = hashlib.sha256(data).hexdigest()
            def command(*args, **kwargs):
                return subprocess.CompletedProcess([], 0, 'arm64 x86_64\n' if '-archs' in args else '',
                                                   'Identifier=com.asmvik.yabai\n' if '-dv' in args else '')
            with mock.patch.object(activation, 'DEFAULT_CANDIDATE', candidate), \
                 mock.patch.object(activation, 'BINARY', installed), \
                 mock.patch.object(activation, 'OSAX_PLIST', info), \
                 mock.patch.object(activation, 'PAYLOADS', pins), \
                 mock.patch.object(activation, 'AFTER', activation.sha(candidate)), \
                 mock.patch.object(activation, 'run', side_effect=command) as runner:
                activation.check_candidate(candidate)
                self.assertTrue(any('--all-architectures' in call.args for call in runner.call_args_list))
                installed.write_bytes(b'different payload')
                with self.assertRaisesRegex(RuntimeError, 'payload mismatch'):
                    activation.check_candidate(candidate)
            self.assertFalse(any('--refresh' in call.args or '--load-sa' in call.args
                                 for call in runner.call_args_list))


class MainTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.stack.enter_context(mock.patch.object(activation.sys, 'platform', 'darwin'))
        self.stack.enter_context(mock.patch.object(activation.os, 'getuid', return_value=501))
        self.stack.enter_context(mock.patch.object(activation, 'service_plist', return_value={}))
        self.stack.enter_context(mock.patch.object(activation, 'sha', return_value=activation.BEFORE))
        self.stack.enter_context(mock.patch.object(activation, 'check_candidate'))
        self.stack.enter_context(mock.patch.object(activation, 'Pointer', return_value=FakePointer()))
        self.runner = self.stack.enter_context(mock.patch.object(activation, 'run',
                                              return_value=subprocess.CompletedProcess([], 0, '', '')))
        self.saved = report()
        self.snapshot = self.stack.enter_context(mock.patch.object(activation, 'stable_snapshot', return_value=self.saved))
        self.auth = self.stack.enter_context(mock.patch.object(activation, 'authenticate'))
        self.lease = self.stack.enter_context(mock.patch.object(activation, 'authorization_lease'))
        self.lock = self.stack.enter_context(mock.patch.object(activation, 'activation_lock'))
        self.prepare = self.stack.enter_context(mock.patch.object(activation, 'prepare',
                                               return_value=(Path('/mock/record'), {'snapshot': self.saved})))
        self.transition = self.stack.enter_context(mock.patch.object(activation, 'transition'))
        self.stack.enter_context(mock.patch.object(activation, 'journal'))
        self.stack.enter_context(mock.patch.object(activation, 'config_hashes', return_value={}))

    def test_no_arguments_and_explicit_dry_run_never_mutate_or_prompt(self):
        self.assertEqual(activation.main([]), 0)
        self.assertEqual(activation.main(['--dry-run']), 0)
        self.auth.assert_not_called()
        self.lease.assert_not_called()
        self.lock.assert_not_called()
        self.prepare.assert_not_called()
        self.transition.assert_not_called()
        self.assertTrue(all(call.args[1] == 'print' for call in self.runner.call_args_list))

    def test_auth_failure_precedes_even_lock_or_backup_writes(self):
        self.auth.side_effect = RuntimeError('authorization unavailable')
        self.assertEqual(activation.main(['--activate']), 2)
        self.lease.assert_not_called()
        self.lock.assert_not_called()
        self.prepare.assert_not_called()
        self.transition.assert_not_called()

    def test_explicit_activation_takes_fresh_snapshot_after_auth(self):
        events = []
        self.snapshot.side_effect = lambda *a: events.append('snapshot') or self.saved
        self.auth.side_effect = lambda: events.append('auth')
        self.prepare.side_effect = lambda *a: events.append('backup') or (Path('/mock/record'), {'snapshot': self.saved})
        self.transition.side_effect = lambda *a, **kw: events.append('replace')
        self.assertEqual(activation.main(['--activate']), 0)
        self.assertEqual(events, ['snapshot', 'auth', 'snapshot', 'backup', 'replace'])

    def test_rollback_uses_live_mappings_not_old_snapshot(self):
        historical = report()
        historical['pointer'] = [200, 300]
        record = {'snapshot': historical, 'initial_snapshot': copy.deepcopy(historical)}
        with mock.patch.object(activation, 'read_record', return_value=record):
            self.assertEqual(activation.main(['--rollback', '/mock/record']), 0)
            self.auth.assert_not_called()
            self.assertEqual(activation.main(['--rollback', '/mock/record', '--activate']), 0)
        self.assertEqual(self.transition.call_args.args[1]['snapshot'], self.saved)
        self.assertEqual(record['initial_snapshot'], historical)
        self.assertTrue(self.transition.call_args.kwargs['rollback'])
        self.prepare.assert_not_called()

    def test_offline_record_recovery_does_not_require_running_daemon(self):
        record = {'snapshot': report()}
        self.runner.return_value.returncode = 1
        with mock.patch.object(activation, 'read_record', return_value=record):
            self.assertEqual(activation.main(['--rollback', '/mock/record', '--activate']), 0)
        self.snapshot.assert_not_called()
        self.transition.assert_called_once()

    def test_no_offline_activation_without_a_record(self):
        self.runner.return_value.returncode = 1
        self.assertEqual(activation.main(['--activate']), 2)
        self.auth.assert_not_called()

    def test_invalid_timeout_does_not_authorize_or_write(self):
        for value in ('nan', 'inf', '0', '301'):
            self.assertEqual(activation.main(['--activate', '--timeout', value]), 2)
        self.auth.assert_not_called()
        self.prepare.assert_not_called()


if __name__ == '__main__':
    unittest.main()
