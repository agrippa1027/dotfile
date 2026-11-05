"""Test the native bridge with a fake BetterDisplay CLI; no hardware changes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

BINARY = Path(os.environ.get('DISPLAY_CONTROL_BIN', Path(__file__).resolve().parents[1] / 'runtime/display-control'))
FIRST = '11111111-2222-3333-4444-555555555555'
SECOND = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'


def row(identity=FIRST, name='Desk display', display_id='2', kind='Display'):
    return {'UUID': identity, 'name': name, 'displayID': display_id, 'deviceType': kind}


def result(output='', status=0, delay=0):
    return {'output': output, 'status': status, 'delay': delay}


FAKE = r'''
import json, os, sys, time
from pathlib import Path
path = Path(os.environ['FAKE_STATE'])
state = json.loads(path.read_text())
state['commands'].append(sys.argv[1:])
answer = state['responses'].pop(0) if state['responses'] else {'output': 'Unexpected call', 'status': 99}
path.write_text(json.dumps(state))
time.sleep(answer.get('delay', 0))
print(answer['output'])
sys.exit(answer['status'])
'''


class BridgeTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.state_path = self.root / 'state.json'
        fake = self.root / 'betterdisplay'
        fake.write_text(f'#!{sys.executable}\n' + FAKE)
        fake.chmod(0o755)
        self.env = {**os.environ, 'BETTERDISPLAY_BIN': str(fake), 'FAKE_STATE': str(self.state_path)}

    def prepare(self, responses):
        self.state_path.write_text(json.dumps({'responses': responses, 'commands': []}))

    def commands(self):
        return json.loads(self.state_path.read_text())['commands']

    def invoke(self, *args, expected=0):
        process = subprocess.run([str(BINARY), *args], env=self.env, capture_output=True, text=True, timeout=12)
        self.assertEqual(process.returncode, expected, process.stderr + process.stdout)
        self.assertEqual(process.stderr, '')
        answer = json.loads(process.stdout)
        self.assertEqual(answer['ok'], expected == 0)
        return answer

    def test_comma_objects_preserve_names_skip_groups_and_duplicates(self):
        name = "Afsal’s 'display'; $(touch nope)"
        raw = ','.join(json.dumps(value) for value in
                       [row(name=name), row(kind='DisplayGroup'), row(), row(SECOND.lower(), display_id='3')])
        self.prepare([result(raw), result('0.5'), result('0.9')])
        parsed = self.invoke('levels')['displays']
        self.assertEqual([d['uuid'] for d in parsed], [FIRST, SECOND])
        self.assertEqual(parsed[0]['name'], name)
        self.assertEqual(parsed[1]['display_id'], 3)

    def test_single_array_and_empty_discovery(self):
        for raw in (json.dumps(row()), json.dumps([row()]), '', '[]'):
            self.prepare([result(raw), result('0.5')])
            self.assertEqual(len(self.invoke('levels')['displays']), 0 if raw in ('', '[]') else 1)

    def test_malformed_discovery_and_bad_rows(self):
        for raw in ('Failed.', '[] trailing', '[{},]', '[null, 3, true]'):
            self.prepare([result(raw)])
            self.invoke('levels', expected=0 if raw == '[null, 3, true]' else 1)
        bad = [row('bad'), row(display_id='0'), row(display_id='-1'), row(display_id=True),
               row(display_id='2.2'), row(display_id=None), row(kind='VirtualScreen'),
               row(display_id='2\x00extra'), row(identity=FIRST + '\x00extra')]
        self.prepare([result(json.dumps(bad))])
        self.assertEqual(self.invoke('levels')['displays'], [])

    def test_snapshot_is_read_only_and_brightness_fractional(self):
        self.prepare([result(json.dumps(row())), result('0.988'), result('2560x1440'),
                      result('85.05Hz'), result(json.dumps(row()))])
        answer = self.invoke('snapshot')
        self.assertEqual(answer['mouse_uuid'], FIRST)
        self.assertEqual(answer['displays'][0]['brightness'], 98.8)
        self.assertEqual(answer['displays'][0]['resolution'], '2560x1440')
        self.assertEqual(answer['displays'][0]['refresh_rate'], '85.05Hz')
        self.assertTrue(all(command[0] == 'get' for command in self.commands()))
        self.assertEqual(self.commands()[-1], ['get', '--displayWithMouse', '--identifiers'])

    def test_periodic_levels_only_reads_identity_and_brightness(self):
        self.prepare([result(json.dumps([row(), row(SECOND)])), result('0.988'), result('0.5')])
        answer = self.invoke('levels')
        self.assertEqual([d['brightness'] for d in answer['displays']], [98.8, 50])
        self.assertIsNone(answer['mouse_uuid'])
        self.assertNotIn('resolution', answer['displays'][0])
        self.assertEqual(len(self.commands()), 3)
        self.assertTrue(all(command[0] == 'get' for command in self.commands()))

    def test_unavailable_fields_do_not_hide_other_displays(self):
        self.prepare([result(json.dumps([row(), row(SECOND)])), result('Failed.', 1), result('garbage'),
                      result('nanHz'), result('0.5'), result('1920x1080'), result('60Hz'), result('Failed.', 1)])
        answer = self.invoke('snapshot')
        self.assertIsNone(answer['displays'][0]['brightness'])
        self.assertIsNone(answer['displays'][0]['resolution'])
        self.assertIsNone(answer['displays'][0]['refresh_rate'])
        self.assertEqual(answer['displays'][1]['brightness'], 50)
        self.assertIsNone(answer['mouse_uuid'])

    def test_nonfinite_multiple_and_out_of_range_brightness(self):
        for raw in ('nan', 'inf', '-inf', '0.2,0.3', '-0.1', '1.2', 'Failed.', '0x1p-1', '0.5\x00extra'):
            self.prepare([result(json.dumps(row())), result(raw)])
            self.assertIsNone(self.invoke('levels')['displays'][0]['brightness'], raw)

    def test_snapshot_discovery_timeout_is_bounded(self):
        self.prepare([result('', delay=2)])
        start = time.monotonic()
        self.assertIn('in time', self.invoke('snapshot', expected=1)['error'])
        self.assertLess(time.monotonic() - start, 1.8)
        self.assertEqual(len(self.commands()), 1)

    def test_total_budget_stops_launching_commands(self):
        rows = [row(f'{i:08X}-2222-3333-4444-555555555555') for i in range(50)]
        self.prepare([result(json.dumps(rows))] + [result('0.5', delay=0.25) for _ in rows])
        start = time.monotonic()
        answer = self.invoke('levels')
        self.assertLess(time.monotonic() - start, 8.6)
        self.assertEqual(len(answer['displays']), 50)
        self.assertLess(len(self.commands()), 40)
        self.assertIsNone(answer['displays'][-1]['brightness'])

    def test_exact_uuid_write_readback_and_no_name_in_command(self):
        self.prepare([result(json.dumps(row(name='$(oops)'))), result('0.5,0.0,1.0'), result('Succeeded.'), result('0.625')])
        self.assertEqual(self.invoke('brightness', FIRST, '62.5'), {'ok': True, 'uuid': FIRST, 'brightness': 62.5})
        self.assertEqual(self.commands()[2], ['set', '--UUID=' + FIRST, '--brightness=62.5%'])
        self.assertEqual(self.commands()[3], ['get', '--UUID=' + FIRST, '--brightness'])

    def test_disconnected_target_never_writes(self):
        self.prepare([result(json.dumps(row(SECOND)))])
        self.assertIn('no longer connected', self.invoke('brightness', FIRST, '50', expected=1)['error'])
        self.assertEqual(len(self.commands()), 1)

    def test_delayed_readback_retries_reads_only(self):
        self.prepare([result(json.dumps(row())), result('0.5,0,1'), result('Succeeded.'), result('0.5'), result('0.6')])
        self.invoke('brightness', FIRST.lower(), '60')
        self.assertEqual(sum(c[0] == 'set' for c in self.commands()), 1)
        self.assertEqual(len(self.commands()), 5)

    def test_readback_mismatch_reports_actual_level(self):
        self.prepare([result(json.dumps(row())), result('0.5,0,1'), result('Succeeded.')] + [result('0.5')] * 3)
        answer = self.invoke('brightness', FIRST, '60', expected=1)
        self.assertEqual(answer['brightness'], 50)
        self.assertIn('could not be verified', answer['error'])
        self.assertEqual(sum(c[0] == 'set' for c in self.commands()), 1)

    def test_failed_write_is_not_retried_and_pro_errors_preserved(self):
        self.prepare([result(json.dumps(row())), result('0.5,0,1'), result('Pro required', 1)])
        answer = self.invoke('brightness', FIRST, '60', expected=1)
        self.assertEqual(answer['brightness'], 50)
        self.assertIn('Pro is required', answer['error'])
        self.assertEqual(len(self.commands()), 3)

    def test_bad_or_hdr_ranges_never_write(self):
        for bounds in ('0.5', '0.5,0,nan', '1.2,0,1.5', '0.5,0.6,1', '0.5,0.4,0.6', '0.5,0,1,2', '0.5,,1'):
            self.prepare([result(json.dumps(row())), result(bounds)])
            self.invoke('brightness', FIRST, '20', expected=1)
            self.assertEqual(len(self.commands()), 2)

    def test_invalid_arguments_never_launch_cli(self):
        for args in (('brightness', 'bad', '50'), ('brightness', FIRST, 'NaN'), ('brightness', FIRST, '-1'),
                     ('brightness', FIRST, '101'), ('brightness', FIRST, '0x1p1'), ('set',), (), ('levels', 'extra')):
            self.prepare([])
            self.invoke(*args, expected=1)
            self.assertEqual(self.commands(), [])

    def test_missing_cli(self):
        self.prepare([])
        self.env['BETTERDISPLAY_BIN'] = str(self.root / 'missing')
        self.assertIn('not installed', self.invoke('snapshot', expected=1)['error'])
        self.assertEqual(self.commands(), [])

    def test_resolution_refresh_formats_and_unknown_mouse(self):
        for refresh in ('60Hz', '48-120Hz-VRR', '85.05Hz', 'ProMotion', 'nanHz', '60Hz junk'):
            self.prepare([result(json.dumps(row())), result('0.5'), result('012x1080'), result(refresh), result(json.dumps(row(SECOND)))])
            answer = self.invoke('snapshot')
            self.assertIsNone(answer['displays'][0]['resolution'])
            self.assertEqual(answer['displays'][0]['refresh_rate'], None if refresh in ('nanHz', '60Hz junk') else refresh)
            self.assertIsNone(answer['mouse_uuid'])


if __name__ == '__main__':
    unittest.main()
