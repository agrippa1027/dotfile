#!/usr/bin/env python3
"""Guarded, user-run M2 activation. No arguments means read-only preflight.

Run --activate in a terminal, not via sudo. Keep the desktop idle; approve
Accessibility if requested (default deadline: 60s). A failed startup triggers
rollback. --rollback RECORD --activate restores the saved binary and sudoers,
using a NEW desktop snapshot if the service is running. Offline recovery uses
its saved snapshot and fails closed if topology or captured membership changed.
New permission UI windows are allowed; keep all captured windows open.

The service helper's --restart-service only kickstarts its loaded job; it does
not accept a config override. Instead we bootout/bootstrap a private, temporary
copy of the LaunchAgent with --config pointing at a label-restoring wrapper.
Neither the persistent plist nor yabairc is edited, and no launchctl environment
is changed. After success the wrapper delegates to the original yabairc. Keep
its record directory until logout: launchd retains that temporary config path.
This preserves mappings across this replacement, not arbitrary future restarts.

Backups and the transaction journal survive failures. SIGKILL/power loss cannot
be rolled back automatically; rerun --rollback RECORD --activate. If rollback
cannot start, leave the service stopped rather than start an unguarded config.
No input events are posted; pointer restoration uses CGWarpMouseCursorPosition.
"""
import argparse
import ctypes
import fcntl
import hashlib
import json
import math
import os
import plistlib
import re
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

BINARY = Path('/opt/homebrew/bin/yabai')
DEFAULT_CANDIDATE = Path('/Users/afsalahamed/dev/yabai/bin-milestone2/yabai')
BEFORE = '8970ce9a6703607cfb435d05b0c82ae00fd94361f97156dbbf281bcead15d5a2'
AFTER = '3443cdd1da2da5f1ecbaf029c2a1de8538d2468c2310f8549747951325653440'
SUDOERS = Path('/private/etc/sudoers.d/yabai')
ROOT = Path(__file__).resolve().parent
PLIST = Path.home() / 'Library/LaunchAgents/com.asmvik.yabai.plist'
CONFIG = ROOT / 'yabairc'
OSAX_PLIST = Path('/Library/ScriptingAdditions/yabai.osax/Contents/Resources/payload.bundle/Contents/Info.plist')
LABELS = tuple('ws-' + label for label in '1234567890a')
PAYLOADS = {
    'payload': '49195b85e079cf107296985aaa7d82d0f8e4fafe065146855badab66adf79ead',
    'loader': 'c9060a8fcd1f47c5379f04984276dfb854aaea206bd67f474229639dbec18848',
}


def run(*args, check=True, timeout=10, text=True):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=text,
                            check=False, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'{shlex.join(list(map(str, args)))}: '
                           f'{result.stderr.strip() or result.stdout.strip() or result.returncode}')
    return result


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def atomic_write(path, data, mode=0o600):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def journal(directory, record):
    atomic_write(directory / 'record.json', (json.dumps(record, indent=2) + '\n').encode())


def authenticate():
    if run('/usr/bin/sudo', '-n', 'true', check=False).returncode:
        require(sys.stdin.isatty() and sys.stdout.isatty(),
                'Authorization unavailable; run --activate yourself in a terminal (sudo -v). Nothing changed.')
        # Only explicit user-run activation can reach this bounded interactive prompt.
        subprocess.run(['/usr/bin/sudo', '-v'], check=True, timeout=120)
    run('/usr/bin/sudo', '-n', 'true')


@contextmanager
def authorization_lease():
    # Keep the already-authorized sudo timestamp alive through a TCC wait/rollback.
    # Never prompt in the background, and never keep credentials alive after exit.
    done = threading.Event()

    def refresh():
        while not done.wait(20):
            try:
                run('/usr/bin/sudo', '-n', '-v')
            except (RuntimeError, OSError, subprocess.SubprocessError) as error:
                print(f'Sudo authorization renewal failed: {error}', file=sys.stderr)
                return

    worker = threading.Thread(target=refresh, daemon=True)
    worker.start()
    try:
        yield
    finally:
        done.set()
        worker.join(timeout=11)


@contextmanager
def activation_lock():
    runtime = ROOT / 'runtime'
    runtime.mkdir(exist_ok=True)
    with (runtime / 'activate-resize.lock').open('a') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Another activation is in progress') from error
        yield


class Pointer:
    class Point(ctypes.Structure):
        _fields_ = [('x', ctypes.c_double), ('y', ctypes.c_double)]

    def __init__(self):
        self.cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
        self.cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        self.cg.CGEventCreate.argtypes = [ctypes.c_void_p]
        self.cg.CGEventCreate.restype = ctypes.c_void_p
        self.cg.CGEventGetLocation.argtypes = [ctypes.c_void_p]
        self.cg.CGEventGetLocation.restype = self.Point
        self.cg.CGWarpMouseCursorPosition.argtypes = [self.Point]
        self.cg.CGWarpMouseCursorPosition.restype = ctypes.c_int32
        self.cf.CFRelease.argtypes = [ctypes.c_void_p]
        self.cf.CFRelease.restype = None

    def get(self):
        event = self.cg.CGEventCreate(None)
        require(event, 'Cannot read pointer position')
        try:
            point = self.cg.CGEventGetLocation(event)
            return [point.x, point.y]
        finally:
            self.cf.CFRelease(event)

    def restore(self, point):
        # Quartz warps to whole-pixel positions. Round first so readback stays
        # within half a pixel of a fractional hardware-pointer snapshot.
        destination = [round(value) for value in point]
        require(self.cg.CGWarpMouseCursorPosition(self.Point(*destination)) == 0,
                'Cannot restore pointer position')


def yabai(*args):
    return run(BINARY, '-m', *args).stdout


def snapshot(pointer):
    result = {key: json.loads(yabai('query', '--' + key))
              for key in ('spaces', 'displays', 'windows')}
    result['pointer'] = pointer.get()
    validate_snapshot(result)
    return result


def validate_snapshot(report):
    for key in ('spaces', 'displays', 'windows'):
        rows = report.get(key)
        require(isinstance(rows, list) and (rows or key == 'windows'), f'Invalid {key} report')
        require(all(isinstance(row, dict) and type(row.get('id')) is int and row['id'] > 0
                    for row in rows), f'Invalid {key} IDs')
        require(len({row['id'] for row in rows}) == len(rows), f'Duplicate {key} IDs')
    for rows in (report['spaces'], report['displays']):
        require(len({row.get('index') for row in rows}) == len(rows), 'Duplicate indices')
        for row in rows:
            require(type(row.get('index')) is int and row['index'] > 0
                    and isinstance(row.get('label'), str)
                    and type(row.get('has-focus')) is bool, 'Invalid index, label or focus')
        labels = [row['label'] for row in rows if row['label']]
        require(len(set(labels)) == len(labels), 'Duplicate labels')
    for space in report['spaces']:
        require(type(space.get('display')) is int
                and space['display'] in {d['index'] for d in report['displays']}
                and type(space.get('is-native-fullscreen')) is bool
                and type(space.get('is-visible')) is bool
                and isinstance(space.get('windows'), list)
                and all(type(wid) is int and wid > 0 for wid in space['windows']), 'Invalid Space')
    for display in report['displays']:
        require(isinstance(display.get('uuid'), str) and isinstance(display.get('frame'), dict),
                'Invalid display identity')
    for window in report['windows']:
        require(type(window.get('space')) is int and type(window.get('display')) is int
                and type(window.get('has-focus')) is bool, 'Invalid window membership/focus')
    for key in ('spaces', 'displays'):
        require(sum(row['has-focus'] for row in report[key]) == 1, f'Unsettled {key} focus')
    require(sum(row['has-focus'] for row in report['windows']) <= 1, 'Unsettled window focus')
    require(isinstance(report.get('pointer'), list) and len(report['pointer']) == 2
            and all(type(n) in (int, float) and math.isfinite(n) for n in report['pointer']),
            'Invalid pointer')
    for display in report['displays']:
        require(sum(s['is-visible'] for s in report['spaces'] if s['display'] == display['index']) == 1,
                'Each display must have exactly one visible Space')


def topology(report, labels=True, membership=True):
    spaces = sorted((s['id'], s['index'], s['display'], s['is-native-fullscreen'],
                     s['label'] if labels else '', tuple(sorted(s['windows'])) if membership else ())
                    for s in report['spaces'])
    displays = sorted((d['id'], d['uuid'], d['index'], sorted(d['frame'].items()),
                       d['label'] if labels else '') for d in report['displays'])
    windows = sorted((w['id'], w['space'], w['display']) for w in report['windows']) if membership else []
    return spaces, displays, windows


def mappings_match(saved, current):
    # Accessibility approval may open Settings. Preserve every captured window,
    # but do not treat newly opened permission UI as a lost/moved old window.
    known = {w['id'] for w in saved['windows']}
    known.update(wid for space in saved['spaces'] for wid in space['windows'])
    projected = dict(current)
    projected['windows'] = [w for w in current['windows'] if w['id'] in known]
    projected['spaces'] = [dict(s, windows=[wid for wid in s['windows'] if wid in known])
                           for s in current['spaces']]
    return topology(saved) == topology(projected)


def context(report):
    return (sorted(s['id'] for s in report['spaces'] if s['is-visible']),
            [s['id'] for s in report['spaces'] if s['has-focus']],
            [d['id'] for d in report['displays'] if d['has-focus']],
            [w['id'] for w in report['windows'] if w['has-focus']])


def safe_setup(report):
    """Normal setup must be a no-op for Space identity, assignment and order."""
    ordinary = [s for s in report['spaces'] if not s['is-native-fullscreen']]
    require(set(LABELS) <= {s['label'] for s in ordinary},
            'Missing managed labels: normal setup could create Spaces; refusing activation')
    rank = {label: index for index, label in enumerate(LABELS)}
    for display in report['displays']:
        rows = sorted((s for s in ordinary if s['display'] == display['index']), key=lambda s: s['index'])
        require(rows == sorted(rows, key=lambda s: rank.get(s['label'], len(rank))),
                'Spaces are not already ordered; refusing to let normal setup move them')


def stable_snapshot(pointer):
    first, second = snapshot(pointer), snapshot(pointer)
    require(topology(first) == topology(second) and context(first) == context(second)
            and first['pointer'] == second['pointer'], 'Desktop changed during preflight; keep it idle and retry')
    safe_setup(second)
    return second


def transition_snapshot(pointer, record):
    loaded = run('/bin/launchctl', 'print', f'gui/{os.getuid()}/com.asmvik.yabai', check=False).returncode == 0
    if loaded:
        return stable_snapshot(pointer), True
    if record is None:
        raise RuntimeError('Service is not loaded; activation requires a live desktop snapshot')
    safe_setup(record['snapshot'])
    return record['snapshot'], False


def restore_labels(saved, pointer):
    current = snapshot(pointer)
    require(topology(saved, labels=False, membership=False) ==
            topology(current, labels=False, membership=False), 'Space/display topology changed; config NOT run')
    # Resolve indices from current native IDs, never use an old index as identity.
    for key, noun in (('spaces', 'space'), ('displays', 'display')):
        for row in saved[key]:
            latest = snapshot(pointer)
            require(topology(saved, labels=False, membership=False) ==
                    topology(latest, labels=False, membership=False), 'Topology changed during label restore')
            actual = next(item for item in latest[key] if item['id'] == row['id'])
            require(actual['label'] in ('', row['label']), 'Unexpected live label; refusing to overwrite it')
            if row['label'] and actual['label'] != row['label']:
                yabai(noun, actual['index'], '--label', row['label'])
    require(mappings_match(saved, snapshot(pointer)),
            'Labels or window membership did not restore; config NOT run')


def restore_context(saved, pointer):
    current = snapshot(pointer)
    require(mappings_match(saved, current), 'Space labels/assignments/window membership changed')
    follows = yabai('config', 'mouse_follows_focus').strip()
    require(follows in ('on', 'off'), 'Cannot read mouse_follows_focus')
    yabai('config', 'mouse_follows_focus', 'off')
    try:
        focused = next(s for s in saved['spaces'] if s['has-focus'])
        visible = [s for s in saved['spaces'] if s['is-visible'] and s['id'] != focused['id']]
        for space in visible + [focused]:
            latest = snapshot(pointer)
            require(mappings_match(saved, latest), 'Desktop changed while restoring focus')
            actual = next(s for s in latest['spaces'] if s['id'] == space['id'])
            if not actual['is-visible'] or (space['id'] == focused['id'] and not actual['has-focus']):
                yabai('space', '--focus', actual['index'])
        windows = [w for w in saved['windows'] if w['has-focus']]
        if windows and context(snapshot(pointer))[3] != [windows[0]['id']]:
            yabai('window', windows[0]['id'], '--focus')
        deadline = time.monotonic() + 3
        while True:
            latest = snapshot(pointer)
            require(mappings_match(saved, latest), 'Desktop changed while focus settled')
            if context(saved) == context(latest):
                break
            require(time.monotonic() < deadline, 'Focus did not settle')
            time.sleep(0.1)
    finally:
        yabai('config', 'mouse_follows_focus', follows)
        pointer.restore(saved['pointer'])
    latest = snapshot(pointer)
    require(mappings_match(saved, latest) and context(saved) == context(latest)
            and all(abs(a - b) <= 0.5 for a, b in zip(saved['pointer'], latest['pointer'])),
            'Desktop/focus/pointer verification failed')


def service_plist():
    value = plistlib.loads(PLIST.read_bytes())
    require(value.get('Label') == 'com.asmvik.yabai'
            and value.get('ProgramArguments') == [str(BINARY)] and 'Program' not in value
            and value.get('RunAtLoad') is True,
            'Unexpected persistent service arguments; refusing an assumed config override')
    require(not {'XDG_CONFIG_HOME', 'HOME'} & value.get('EnvironmentVariables', {}).keys(),
            'Service overrides config discovery; refusing')
    return value


def check_candidate(candidate):
    require(candidate.is_file() and os.access(candidate, os.X_OK) and sha(candidate) == AFTER,
            'Candidate hash/executable does not match the approved M2 build')
    run('/usr/bin/codesign', '--verify', '--strict', '--all-architectures', candidate)
    signature = run('/usr/bin/codesign', '-dv', candidate)
    require('Identifier=com.asmvik.yabai' in signature.stderr.splitlines(), 'Unexpected signing identifier')
    require(set(run('/usr/bin/lipo', '-archs', candidate).stdout.split()) == {'arm64', 'x86_64'},
            'Candidate is not the approved universal build')
    for name, expected in PAYLOADS.items():
        source = DEFAULT_CANDIDATE.parents[1] / 'src/osax' / (name + '_bin.c')
        data = bytes(int(n, 16) for n in re.findall(r'0x([0-9a-fA-F]{2})', source.read_text()))
        require(hashlib.sha256(data).hexdigest() == expected
                and data in candidate.read_bytes() and data in BINARY.read_bytes(),
                f'{name} source/embedded payload mismatch; refresh is deliberately NOT automated')
    require(plistlib.loads(OSAX_PLIST.read_bytes()).get('CFBundleVersion') == '2.1.30',
            'Installed payload version differs; refusing an activation that might restart Dock')


def config_hashes():
    return {str(path): sha(path) for path in (CONFIG, ROOT / 'setup-spaces.sh', ROOT / 'order-spaces.py', PLIST)}


def check_config(record):
    require(config_hashes() == record['config_hashes'], 'Config/plist changed during activation; config NOT run')


def read_record(directory):
    require(directory.is_dir() and not directory.is_symlink()
            and directory.stat().st_uid == os.getuid() and directory.stat().st_mode & 0o077 == 0,
            'Record directory must be private and owned by this user')
    record = json.loads((directory / 'record.json').read_text())
    require(record['version'] == 1 and record['uid'] == os.getuid()
            and record['target'] == str(BINARY.resolve(strict=True))
            and record['before_hash'] == BEFORE and record['after_hash'] == AFTER,
            'Record does not describe this installation/build')
    require(sha(directory / 'binary.before') == BEFORE
            and sha(directory / 'sudoers.before') == record['sudoers_hash'], 'Rollback backup integrity failure')
    validate_snapshot(record['snapshot'])
    return record


def prepare(candidate, saved):
    directory = Path(tempfile.mkdtemp(prefix='activation-', dir=ROOT / 'runtime'))
    target = BINARY.resolve(strict=True)
    require(not SUDOERS.is_symlink() and stat.S_ISREG(SUDOERS.stat().st_mode), 'Unexpected sudoers file')
    binary_stat, sudo_stat = target.stat(), SUDOERS.stat()
    record = {'version': 1, 'uid': os.getuid(), 'target': str(target),
              'before_hash': BEFORE, 'after_hash': AFTER, 'snapshot': saved, 'initial_snapshot': saved,
              'binary_meta': [binary_stat.st_uid, binary_stat.st_gid, stat.S_IMODE(binary_stat.st_mode)],
              'sudoers_meta': [sudo_stat.st_uid, sudo_stat.st_gid, stat.S_IMODE(sudo_stat.st_mode)],
              'config_hashes': config_hashes(), 'state': 'prepared'}
    atomic_write(directory / 'binary.before', target.read_bytes())
    atomic_write(directory / 'binary.after', candidate.read_bytes())
    # sudoers is normally unreadable by the user. Authentication precedes ALL writes.
    atomic_write(directory / 'sudoers.before', run('/usr/bin/sudo', '-n', '/bin/cat', SUDOERS, text=False).stdout)
    require(sha(directory / 'binary.before') == BEFORE and sha(directory / 'binary.after') == AFTER,
            'Binary changed while backing up; nothing installed')
    record['sudoers_hash'] = sha(directory / 'sudoers.before')
    username = run('/usr/bin/id', '-un').stdout.strip()
    require(re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_-]*', username), 'Unexpected sudoers username')
    rule = f'{username} ALL=(root) NOPASSWD: sha256:{AFTER} {BINARY} --load-sa\n'
    require((directory / 'sudoers.before').read_bytes() == rule.replace(AFTER, BEFORE).encode(),
            'Existing sudoers is not the expected single hash-pinned rule; nothing installed')
    atomic_write(directory / 'sudoers.after', rule.encode())
    run('/usr/bin/sudo', '-n', '/usr/sbin/visudo', '-cf', directory / 'sudoers.after')
    record['new_sudoers_hash'] = sha(directory / 'sudoers.after')
    journal(directory, record)
    return directory, record


def privileged_replace(source, destination, metadata, sudoers=False):
    """Copy to a sibling, validate, then rename. Never truncate a running inode."""
    temporary = destination.with_name('.' + destination.name + '.activation-' + uuid.uuid4().hex)
    uid, gid, mode = metadata
    try:
        run('/usr/bin/sudo', '-n', '/usr/bin/install', '-o', uid, '-g', gid, '-m', f'{mode:o}', source, temporary)
        if sudoers:
            run('/usr/bin/sudo', '-n', '/usr/sbin/visudo', '-cf', temporary)
        run('/usr/bin/sudo', '-n', '/bin/mv', '-f', temporary, destination)
    finally:
        run('/usr/bin/sudo', '-n', '/bin/rm', '-f', temporary, check=False)


def install_pair(directory, record, rollback):
    suffix = 'before' if rollback else 'after'
    require(str(BINARY.resolve(strict=True)) == record['target'], 'Installation symlink changed')
    require(sha(directory / ('binary.' + suffix)) == (BEFORE if rollback else AFTER), 'Staged binary changed')
    expected_rule = record['sudoers_hash'] if rollback else record['new_sudoers_hash']
    require(sha(directory / ('sudoers.' + suffix)) == expected_rule, 'Staged sudoers changed')
    privileged_replace(directory / ('binary.' + suffix), Path(record['target']), record['binary_meta'])
    privileged_replace(directory / ('sudoers.' + suffix), SUDOERS, record['sudoers_meta'], sudoers=True)
    require(sha(BINARY) == (BEFORE if rollback else AFTER), 'Installed binary verification failed')
    installed_rule = run('/usr/bin/sudo', '-n', '/bin/cat', SUDOERS, text=False).stdout
    require(hashlib.sha256(installed_rule).hexdigest() == expected_rule, 'Installed sudoers verification failed')


def write_wrapper(directory, record, plist, guarded=True):
    wrapper = directory / 'yabairc'
    command = ([sys.executable, str(Path(__file__).resolve()), '--startup', str(directory), record['attempt']]
               if guarded else ['/bin/bash', str(CONFIG)])
    atomic_write(wrapper, ('#!/bin/sh\nexec ' + shlex.join(command) + '\n').encode())
    temporary = dict(plist)
    temporary['ProgramArguments'] = [str(BINARY), '--config', str(wrapper)]
    temporary['EnvironmentVariables'] = dict(plist.get('EnvironmentVariables', {}), XDG_CONFIG_HOME=str(ROOT.parent))
    temporary['AbandonProcessGroup'] = False
    atomic_write(directory / 'service.plist', plistlib.dumps(temporary))


def startup(directory, attempt):
    """Invoked only by the temporary service config, before the real yabairc."""
    record = read_record(directory)
    require(record.get('attempt') == attempt and record['state'] == 'starting', 'Stale startup guard')
    try:
        check_config(record)
        require(sha(BINARY) == record['expected_hash'], 'Wrong binary at guarded startup')
        pointer = Pointer()
        restore_labels(record['snapshot'], pointer)
        # Do not call setup-spaces (or any normal config) until labels are verified.
        check_config(record)
        run('/bin/bash', CONFIG, timeout=30)
        restore_context(record['snapshot'], pointer)
        atomic_write(directory / (attempt + '.ready'), b'ready\n')
        return 0
    except Exception as error:
        atomic_write(directory / (attempt + '.error'), str(error).encode())
        raise


def wait_ready(directory, attempt, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        error = directory / (attempt + '.error')
        if error.exists():
            raise RuntimeError('Guarded startup failed: ' + error.read_text())
        if (directory / (attempt + '.ready')).exists():
            return
        time.sleep(0.2)
    raise RuntimeError(f'Startup timed out after {timeout:g}s; Accessibility may have rejected the new signature')


def start_guarded(directory, record, plist, timeout, rollback):
    record.update(state='starting', attempt=uuid.uuid4().hex, expected_hash=BEFORE if rollback else AFTER)
    journal(directory, record)
    write_wrapper(directory, record, plist)
    run('/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', directory / 'service.plist')
    wait_ready(directory, record['attempt'], timeout)
    restore_context(record['snapshot'], Pointer())
    record['state'] = 'rolled-back' if rollback else 'active'
    journal(directory, record)
    # Future restarts must not replay a now-stale desktop snapshot.
    write_wrapper(directory, record, plist, guarded=False)


def stop_service(check=True):
    run('/bin/launchctl', 'bootout', f'gui/{os.getuid()}/com.asmvik.yabai', check=check)


def transition(directory, record, plist, timeout, rollback=False, live=True):
    recovery_command = shlex.join([sys.executable, str(Path(__file__).resolve()), '--rollback', str(directory), '--activate'])
    print(f'Rollback record: {directory}\nRecovery command: {recovery_command}', flush=True)
    print('Keep the desktop idle. Approve yabai in Accessibility if requested. '
          f'Startup deadline: {timeout:g}s; failure automatically restores the old binary.', flush=True)
    check_config(record)
    if live:
        latest, saved = snapshot(Pointer()), record['snapshot']
        require(topology(latest) == topology(saved) and context(latest) == context(saved)
                and latest['pointer'] == saved['pointer'], 'Desktop changed while preparing backups; nothing replaced')
    try:
        record['state'] = 'replacing'
        journal(directory, record)
        stop_service(check=not rollback)
        install_pair(directory, record, rollback)
        start_guarded(directory, record, plist, timeout, rollback)
    except (Exception, KeyboardInterrupt) as error:
        print(f'Activation failed: {error}. Restoring backups...', file=sys.stderr, flush=True)
        try:
            stop_service(check=False)
            install_pair(directory, record, rollback=True)
            start_guarded(directory, record, plist, timeout, rollback=True)
        except (Exception, KeyboardInterrupt) as recovery:  # noqa: BLE001 -- journal unexpected recovery failures too.
            # Never fall back to an unguarded bootstrap: it could create new Spaces.
            try:
                stop_service(check=False)
            except (RuntimeError, OSError, subprocess.SubprocessError) as stop_error:
                print(f'Could not confirm service stopped: {stop_error}', file=sys.stderr)
            record.update(state='rollback-failed', error=str(error), recovery_error=str(recovery))
            journal(directory, record)
            raise RuntimeError(f'Rollback incomplete ({recovery}); no unguarded service was started. Backups: {directory}. '
                               'Do NOT start the normal service; rerun --rollback with this record.') from error
        raise RuntimeError(f'{error}; original binary/sudoers restored and desktop verified. Backups: {directory}') from error
    print(f'{record["state"]}: binary, labels, Space/display/window mappings, visible Spaces, focus and pointer verified.\n'
          f'Keep {directory} until logout (loaded service uses its config wrapper).\n'
          f'Rollback: {recovery_command}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--activate', action='store_true', help='authorize and perform replacement (default: dry-run)')
    mode.add_argument('--dry-run', action='store_true', help='read-only preflight (the default)')
    parser.add_argument('--candidate', type=Path, default=DEFAULT_CANDIDATE,
                        help='approved M2 binary (default: %(default)s)')
    parser.add_argument('--rollback', type=Path, metavar='RECORD', help='restore backups; still dry-run without --activate')
    parser.add_argument('--timeout', type=float, default=60, help='startup/Accessibility deadline, 5..300 seconds')
    parser.add_argument('--startup', nargs=2, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        require(sys.platform == 'darwin' and os.getuid() != 0, 'Run as the logged-in macOS user, never with sudo')
        if args.startup:
            require(not args.activate and not args.rollback and not args.dry_run, 'Invalid internal startup arguments')
            return startup(Path(args.startup[0]), args.startup[1])
        require(math.isfinite(args.timeout) and 5 <= args.timeout <= 300, 'Timeout must be 5..300 seconds')
        plist = service_plist()
        record = read_record(args.rollback) if args.rollback else None
        require(sha(BINARY) in ((BEFORE, AFTER) if record else (BEFORE,)), 'Installed binary is not an approved build')
        if not record:
            check_candidate(args.candidate)
        pointer = Pointer()
        saved, loaded = transition_snapshot(pointer, record)
        if not args.activate:
            print(f'DRY RUN: {"rollback from " + str(args.rollback) if record else "activate " + str(args.candidate)}\n'
                  f'{len(saved["spaces"])} Spaces; {"live" if loaded else "RECORDED (offline)"} labels/order/display/window mappings validated.\n'
                  'No writes, sudo prompts, service changes, payload refresh or input events.\n'
                  'Use --activate in an interactive terminal; backups precede replacement.\n'
                  'A private transient LaunchAgent provides early label restore; persistent config/plist stay unchanged.')
            return 0
        authenticate()  # Must precede lock files, backups, sudoers changes and service operations.
        with authorization_lease(), activation_lock():
            # Authentication may take time: snapshot again before stopping anything.
            require(sha(BINARY) in ((BEFORE, AFTER) if record else (BEFORE,)), 'Installed binary changed')
            plist = service_plist()
            saved, loaded = transition_snapshot(pointer, record)
            if record:
                directory = args.rollback.resolve()
                record = read_record(directory)
                record.update(snapshot=saved, config_hashes=config_hashes())
                journal(directory, record)
            else:
                directory, record = prepare(args.candidate, saved)
            transition(directory, record, plist, args.timeout, rollback=bool(args.rollback), live=loaded)
        return 0
    except (RuntimeError, ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f'Activation refused/failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    def interrupted(signum, frame):
        raise InterruptedError(f'Interrupted by signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
