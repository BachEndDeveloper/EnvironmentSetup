#!/usr/bin/env python3
"""Exercise the daily-memory installer/runner with temporary HOME and mocked CLIs.

Usage: python3 scripts/test-memory-daily.py
Never loads a real launchd job, invokes real Pi, or accesses the real HOME.
"""
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MOCK = r'''#!/usr/bin/env python3
import json, os, plistlib, sys, time
from pathlib import Path
root = Path(os.environ['SANDBOX_ROOT'])
home = Path(os.environ['HOME'])
assert root.name.startswith('memory-daily-test-') and home.parent == root
command = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps({'command': command, 'args': args,
                        'tz': os.environ.get('TZ'), 'cwd': os.getcwd(),
                        'path': os.environ['PATH']}) + '\n')
if command == 'launchctl':
    path = root / 'launchctl-state.json'
    state = json.loads(path.read_text()) if path.exists() else {'loaded': False, 'disabled': True}
    operation = args[0]
    if operation == 'print':
        assert args[1].endswith('/local.sandbox-user.memory-daily')
        sys.exit(0 if state['loaded'] else 1)
    if operation == 'bootstrap':
        assert not state['loaded'] and not state['disabled']
        plist = Path(args[2])
        assert plist.is_relative_to(home)
        config = plistlib.loads(plist.read_bytes())
        assert config['RunAtLoad'] is False
        state['loaded'] = True
        state['config'] = config
    elif operation == 'bootout':
        assert state['loaded']
        state['loaded'] = False
    elif operation in ('enable', 'disable'):
        state['disabled'] = operation == 'disable'
    else:
        raise AssertionError('unmocked launchctl command')
    path.write_text(json.dumps(state))
elif command == 'pi':
    assert args[:2] == ['-p', '--no-session']
    assert args[-1] in ('Run the memory-daily skill.', 'run memory-daily catch-up')
    if os.environ.get('MOCK_PI_WAIT'):
        (root / 'pi-ready').write_text('ready')
        deadline = time.monotonic() + 15
        while not (root / 'pi-release').exists():
            assert time.monotonic() < deadline, 'test failed to release mock Pi'
            time.sleep(0.02)
    print(os.environ.get('MOCK_PI_OUTPUT', 'Synthetic run.\nMEMORY-DAILY: OK'))
    sys.exit(int(os.environ.get('MOCK_PI_EXIT', '0')))
elif command == 'qmd-check':
    assert args == ['--check']
    print('qmd check: synthetic read-only summary')
    sys.exit(int(os.environ.get('MOCK_QMD_EXIT', '0')))
elif command == 'osascript':
    assert args[0] == '-e' and 'display notification' in args[1]
    assert 'synthetic-private-output' not in args[1]
    sys.exit(int(os.environ.get('MOCK_NOTIFY_EXIT', '0')))
else:
    raise AssertionError('unmocked command')
'''


def main():
    source = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix='memory-daily-test-') as temporary:
        root = Path(temporary).resolve()
        # Spaces and XML metacharacters prove the plist is rendered, not interpolated.
        home = root / 'home & space'
        home.mkdir()
        setup = root / 'setup'
        shutil.copytree(source / 'scripts', setup / 'scripts')
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        for name in ('pi', 'launchctl', 'osascript', 'qmd-check'):
            path = bin_dir / name
            path.write_text(MOCK)
            path.chmod(0o755)
        # Whitelist the environment: no real host overrides, credentials or shell startup.
        env = {'HOME': str(home), 'USER': 'Sandbox_User', 'SANDBOX_ROOT': str(root),
               'PATH': f'{bin_dir}:{Path(sys.executable).parent}:/usr/bin:/bin',
               'LC_ALL': 'C', 'TMPDIR': str(root), 'PYTHONDONTWRITEBYTECODE': '1'}
        # The qmd doctor has its own sandbox suite; mock only that boundary here.
        (setup / 'scripts/install-qmd.sh').write_text('#!/usr/bin/env bash\nexec qmd-check "$@"\n')
        installer = setup / 'scripts/install-memory-daily.sh'
        on_demand = setup / 'scripts/memory-run.sh'
        runner = home / '.local/share/memory-daily/run.sh'
        plist = home / 'Library/LaunchAgents/local.sandbox-user.memory-daily.plist'
        log_dir = home / 'Library/Logs/memory-daily'
        state_dir = runner.parent
        lock = state_dir / 'run.lock'

        def run(script, *args, success=True, extra=None):
            result = subprocess.run(['bash', str(script), *args], env=env | (extra or {}),
                                    cwd=setup, capture_output=True, text=True, timeout=20)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        def calls(command=None):
            path = root / 'calls.jsonl'
            items = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
            return [item for item in items if command is None or item['command'] == command]

        def count(operation):
            return sum(item['args'][0] == operation for item in calls('launchctl'))

        def state():
            return json.loads((root / 'launchctl-state.json').read_text())

        def snapshot():
            return {str(p.relative_to(home)): p.read_bytes() for p in home.rglob('*') if p.is_file()}

        def write_registry(data):
            path = home / '.pi/agent/mcp.json'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data))
            return path

        def log():
            logs = list(log_dir.glob('????-??-??.log'))
            assert len(logs) == 1, logs
            return logs[0].read_text()

        before = snapshot()
        output = run(on_demand, 'status').stdout
        assert 'no dated log found' in output and 'unloaded' in output and 'qmd check:' in output
        assert snapshot() == before and not calls('pi')
        for args in ((), ('other',), ('daily', '--model'), ('daily', '--model', ''),
                     ('daily', '--model', '--bad'), ('daily', '--unknown', 'provider/id')):
            run(on_demand, *args, success=False)
        assert not calls('pi') and snapshot() == before
        print('PASS: on-demand status without an installation is read-only; invalid command/model arguments fail before writes')
        # Ignore the status-only launchctl print above for the install assertions.
        (root / 'calls.jsonl').unlink()

        output = run(installer).stdout
        assert output.splitlines()[-1] == 'memory-daily: installed, disabled -- enable with scripts/install-memory-daily.sh --enable'
        assert '--enable' in output and calls('launchctl') == []
        config = plistlib.loads(plist.read_bytes())
        assert config['Label'] == 'local.sandbox-user.memory-daily'
        assert config['ProgramArguments'] == ['/bin/bash', str(runner)]
        assert config['WorkingDirectory'] == str(state_dir)
        assert config['EnvironmentVariables']['HOME'] == str(home)
        assert config['EnvironmentVariables']['TZ'] == 'Europe/Copenhagen'
        assert config['EnvironmentVariables']['PATH'].startswith(f'{home}/.local/bin:')
        assert 'MEMORY_DAILY_MODEL' not in config['EnvironmentVariables']
        assert config['StartCalendarInterval'] == {'Hour': 7, 'Minute': 30}
        assert config['RunAtLoad'] is False and config['Disabled'] is True
        assert Path(config['StandardOutPath']).parent == log_dir
        assert Path(config['StandardErrorPath']).parent == log_dir
        before = snapshot()
        run(installer)
        assert snapshot() == before and calls('launchctl') == []
        assert runner.stat().st_mode & 0o777 == 0o700
        assert plist.stat().st_mode & 0o777 == 0o600
        print('PASS: install-memory-daily default/repeat install files only, with opt-in-safe plist and HOME-derived paths')

        before = snapshot()
        assert 'unloaded' in run(installer, '--status').stdout
        assert snapshot() == before
        assert run(installer, '--enable').stdout.splitlines()[-1] == 'memory-daily: enabled (07:30; RunAtLoad=false)'
        assert state()['loaded'] and not state()['disabled'] and count('bootstrap') == 1
        assert (state_dir / '.enabled').exists()
        launch_calls = len(calls('launchctl'))
        run(installer, '--enable')
        assert len(calls('launchctl')) == launch_calls
        assert count('bootstrap') == 1 and count('bootout') == 0
        before = snapshot()
        assert 'loaded (daily' in run(installer, '--status').stdout
        assert snapshot() == before
        launch_calls = len(calls('launchctl'))
        run(installer)
        assert len(calls('launchctl')) == launch_calls and state()['loaded']
        assert 'disabled (unloaded)' in run(installer, '--disable', extra={'MEMORY_DAILY_ENABLE': '1'}).stdout.splitlines()[-1]
        assert not state()['loaded'] and state()['disabled'] and count('bootout') == 1
        assert not (state_dir / '.enabled').exists()
        run(installer, '--disable')
        assert count('bootout') == 1
        # Rewriting a disabled job's runner/plist must never call launchctl.
        script_source = setup / 'scripts/memory-daily/run.sh'
        script_source.write_text(script_source.read_text() + '\n# Synthetic disabled update.\n')
        model = 'provider/model:thinking & test'
        launch_calls = len(calls('launchctl'))
        assert 'installed, disabled' in run(installer, extra={'MEMORY_DAILY_MODEL': model}).stdout.splitlines()[-1]
        assert len(calls('launchctl')) == launch_calls and not state()['loaded']
        assert runner.read_text() == script_source.read_text()
        run(installer, extra={'MEMORY_DAILY_ENABLE': '1', 'MEMORY_DAILY_MODEL': model})
        assert state()['loaded'] and state()['config']['EnvironmentVariables']['MEMORY_DAILY_MODEL'] == model
        bootstraps = count('bootstrap')
        run(installer, '--enable', extra={'MEMORY_DAILY_MODEL': model})
        assert count('bootstrap') == bootstraps
        # Prior opt-in survives a default reinstall: changed enabled definitions
        # reload immediately; unchanged ones make no launchctl call at all.
        bootouts = count('bootout')
        assert 'memory-daily: enabled' in run(installer).stdout.splitlines()[-1]
        assert count('bootstrap') == bootstraps + 1 and count('bootout') == bootouts + 1
        assert state()['loaded'] and 'MEMORY_DAILY_MODEL' not in state()['config']['EnvironmentVariables']
        launch_calls = len(calls('launchctl'))
        run(installer, '--enable')
        run(installer)
        assert len(calls('launchctl')) == launch_calls
        # A script-only update also reloads an enabled job.
        script_source.write_text(script_source.read_text() + '\n# Synthetic enabled update.\n')
        run(installer)
        assert count('bootstrap') == bootstraps + 2 and count('bootout') == bootouts + 2
        assert state()['loaded'] and runner.read_text() == script_source.read_text()
        run(installer, '--unknown', success=False)
        print('PASS: explicit flag/env enable, persistent disable/status, preserved opt-in, changed-enabled reloads and no calls for unchanged/disabled installs')

        # Full setup's mode ignores inherited enable and previous opt-in. It
        # queries only loaded state; no silent reversal of an explicit opt-in.
        run(installer, '--disable')
        before_calls = len(calls('launchctl'))
        result = run(installer, '--install-disabled', extra={'MEMORY_DAILY_ENABLE': '1'})
        assert 'on-demand only' in result.stdout and not state()['loaded']
        assert [c['args'][0] for c in calls('launchctl')[before_calls:]] == ['print']
        run(installer, '--enable')
        before_state = state()
        before_calls = len(calls('launchctl'))
        # A changed shared runner must not reload an existing job in setup mode.
        common_source = setup / 'scripts/memory-daily/common.sh'
        common_source.write_text(common_source.read_text() + '\n# Synthetic on-demand update.\n')
        result = run(installer, '--install-disabled', extra={'MEMORY_DAILY_ENABLE': '1'})
        assert 'ENABLED (loaded)' in result.stderr and 'DEC-0029' in result.stderr
        assert 'scripts/install-memory-daily.sh --disable' in result.stderr
        assert state() == before_state
        assert [c['args'][0] for c in calls('launchctl')[before_calls:]] == ['print']
        assert (state_dir / 'common.sh').read_bytes() == common_source.read_bytes()
        run(installer, '--disable')
        print('PASS: --install-disabled ignores env/prior opt-in, never loads/reloads/unloads, warns prominently if already loaded')

        daily = home / 'source/DailyDriver'
        (daily / '.git').mkdir(parents=True)
        registry = write_registry({'mcpServers': {'memory': {'command': 'synthetic-memory'},
                                                'm365-personal-productivity': {'command': 'synthetic-m365'}}})
        registry_before = registry.read_bytes()
        pi_before = len(calls('pi'))
        run(runner)
        assert len(calls('pi')) == pi_before + 1
        pi_call = calls('pi')[-1]
        assert pi_call['args'] == ['-p', '--no-session', 'Run the memory-daily skill.']
        assert pi_call['tz'] == 'Europe/Copenhagen'
        assert pi_call['cwd'] == str(state_dir)
        assert str(home / '.local/bin') in pi_call['path'].split(':')
        assert 'MEMORY-DAILY: OK' in log() and 'COMPLETED:' in log()
        assert not lock.exists() and not list(state_dir.glob('output.*'))
        assert registry.read_bytes() == registry_before
        run(runner, extra={'MEMORY_DAILY_MODEL': model})
        assert calls('pi')[-1]['args'] == ['-p', '--no-session', '--model', model, 'Run the memory-daily skill.']
        dated_log = next(log_dir.glob('????-??-??.log'))
        assert dated_log.stat().st_mode & 0o777 == 0o600
        # The date and day rollover are calculated using the requested timezone.
        expected_date = subprocess.check_output(['date', '+%Y-%m-%d'], env=env | {'TZ': 'Europe/Copenhagen'}, text=True).strip()
        assert dated_log.name == expected_date + '.log'
        print('PASS: run.sh uses exact headless flags/prompt, optional model, Copenhagen date/TZ, private neutral cwd and read-only config')

        summary = ('Memory daily — synthetic; mode=normal; batches=1\n'
                   'Counts: synthetic=1\nWritten: none\nFailures: none\nMEMORY-DAILY: OK')
        result = run(on_demand, 'daily', '--model', 'provider/model', extra={'MOCK_PI_OUTPUT': summary})
        assert summary in result.stdout and summary in log()
        assert 'Final marker: MEMORY-DAILY: OK' in result.stdout and f'Log: {dated_log}' in result.stdout
        assert calls('pi')[-1]['args'] == ['-p', '--no-session', '--model', 'provider/model', 'Run the memory-daily skill.']
        assert calls('pi')[-1]['tz'] == 'Europe/Copenhagen' and calls('pi')[-1]['cwd'] == str(state_dir)
        before = snapshot()
        pi_before = len(calls('pi'))
        result = run(on_demand, 'status')
        assert 'Memory daily — synthetic' in result.stdout and 'Counts: synthetic=1' in result.stdout
        assert 'MEMORY-DAILY: OK' in result.stdout and 'qmd check:' in result.stdout and 'unloaded' in result.stdout
        assert snapshot() == before and len(calls('pi')) == pi_before
        run(on_demand, 'status', success=False, extra={'MOCK_QMD_EXIT': '6'})
        assert snapshot() == before and len(calls('pi')) == pi_before
        # Installed runner and status helpers must not depend on a source checkout.
        installed_on_demand = state_dir / 'memory-run.sh'
        result = run(installed_on_demand, 'catch-up', extra={'MOCK_PI_OUTPUT': 'MEMORY-DAILY: PARTIAL 1 step(s) skipped'})
        assert calls('pi')[-1]['args'] == ['-p', '--no-session', 'run memory-daily catch-up']
        assert 'Final marker: MEMORY-DAILY: PARTIAL 1 step(s) skipped' in result.stdout
        run(installed_on_demand, 'status')
        result = run(on_demand, 'daily', success=False, extra={'MOCK_PI_OUTPUT': 'truncated synthetic run'})
        assert 'FAILED:' in result.stdout and 'Final marker: none' in result.stdout and f'Log: {dated_log}' in result.stdout
        before = snapshot()
        result = run(on_demand, 'status')
        assert 'Summary: unavailable' in result.stdout and 'Final marker: unavailable' in result.stdout
        assert 'Memory daily — synthetic' not in result.stdout and 'MEMORY-DAILY: OK' not in result.stdout
        assert snapshot() == before
        print('PASS: daily/catch-up stream to terminal and dated log, select model, print marker/path; source/installed status is read-only and never reuses stale summaries')

        # launchd has no nvm shell profile: discover only sandboxed Node/Pi copies.
        nvm = home / '.nvm'
        for version in ('v20.1.0', 'v30.2.0'):
            node_bin = nvm / 'versions/node' / version / 'bin'
            node_bin.mkdir(parents=True)
            (node_bin / 'pi').symlink_to(bin_dir / 'pi')
            (node_bin / 'node').write_text('#!/bin/sh\nexit 0\n')
            (node_bin / 'node').chmod(0o755)
        run(runner)
        assert calls('pi')[-1]['path'].split(':')[1] == str(nvm / 'versions/node/v30.2.0/bin')
        (nvm / 'alias').mkdir()
        (nvm / 'alias/default').write_text('v20.1.0\n')
        run(runner)
        assert calls('pi')[-1]['path'].split(':')[1] == str(nvm / 'versions/node/v20.1.0/bin')
        shutil.rmtree(nvm)
        # Mock the PATH probe itself so testing a missing Pi cannot fall through
        # to a real executable in the runner's system/Homebrew fallback paths.
        pi_before = len(calls('pi'))
        notifications = len(calls('osascript'))
        result = subprocess.run(['bash', '-c',
                                 'command() { if [[ "$*" == "-v pi" ]]; then return 1; '
                                 'else builtin command "$@"; fi; }; source "$1"',
                                 'missing-pi-test', str(runner)], env=env, cwd=setup,
                                capture_output=True, text=True, timeout=20)
        assert result.returncode != 0 and 'pi is not on PATH' in log()
        assert len(calls('pi')) == pi_before and len(calls('osascript')) == notifications + 1
        print('PASS: nvm PATH discovery uses default/newest installed Pi; missing-Pi probe fails before invocation')

        for output, code in [('MEMORY-DAILY: FAILED synthetic-private-output', '0'),
                             ('MEMORY-DAILY: OK', '7'),
                             ('crashed before final marker', '0'),
                             ('MEMORY-DAILY: OK\ntruncated continuation', '0'),
                             ('MEMORY-DAILY: FAILED earlier\nMEMORY-DAILY: OK', '0')]:
            notifications = len(calls('osascript'))
            result = run(runner, success=False, extra={'MOCK_PI_OUTPUT': output, 'MOCK_PI_EXIT': code})
            assert result.returncode != 0 and 'FAILED:' in log()
            assert len(calls('osascript')) == notifications + 1
            assert 'sound name' in calls('osascript')[-1]['args'][1]
            assert not lock.exists() and not list(state_dir.glob('output.*'))
        notifications = len(calls('osascript'))
        run(runner)  # Historical FAILED lines in today's log must not poison this run.
        assert len(calls('osascript')) == notifications
        run(runner, extra={'MOCK_PI_OUTPUT': 'Synthetic run.\nMEMORY-DAILY: PARTIAL 2 step(s) skipped'})
        assert len(calls('osascript')) == notifications + 1
        assert 'sound name' not in calls('osascript')[-1]['args'][1]
        run(runner, success=False, extra={'MOCK_PI_EXIT': '3', 'MOCK_NOTIFY_EXIT': '1'})
        assert 'notification could not be delivered' in log()
        print('PASS: failure/nonzero/missing-final markers notify and fail; PARTIAL is successful/quiet; past failures and notification errors handled')

        pi_before = len(calls('pi'))
        notifications = len(calls('osascript'))
        write_registry({'mcpServers': {'memory': {'command': 'synthetic-memory'}}})
        before = registry.read_bytes()
        run(runner, success=False)
        assert registry.read_bytes() == before
        registry.write_text('{invalid-json')
        run(runner, success=False)
        registry.write_bytes(registry_before)
        (daily / '.git').rmdir()
        run(runner, success=False)
        (daily / '.git').mkdir()
        assert len(calls('pi')) == pi_before
        assert len(calls('osascript')) == notifications + 3
        assert not lock.exists()
        # Shared registry presence is supported too, with no writes/probes.
        shared = home / '.config/mcp/mcp.json'
        shared.parent.mkdir(parents=True)
        shared.write_bytes(registry_before)
        registry.unlink()
        run(runner)
        assert shared.read_bytes() == registry_before
        registry.write_bytes(registry_before)
        print('PASS: missing/invalid registrations and missing DailyDriver fail preflight, notify and never invoke Pi or rewrite registries')

        old = log_dir / '2000-01-01.log'
        recent = log_dir / '2000-01-02.log'
        unrelated = log_dir / 'keep.txt'
        for path, days in ((old, 31), (recent, 5), (unrelated, 31)):
            path.write_text('fixture')
            age = time.time() - days * 86400
            os.utime(path, (age, age))
        run(runner)
        assert not old.exists() and recent.exists() and unrelated.exists()
        recent.unlink()
        print('PASS: only dated logs older than the 30-day retention window are removed')

        pi_before = len(calls('pi'))
        lock.mkdir()
        (lock / 'pid').write_text('2147483647\n')
        age = time.time() - 2 * 3600
        os.utime(lock, (age, age))
        run(runner)
        assert len(calls('pi')) == pi_before and lock.exists()
        assert 'SKIPPED:' in log()
        age = time.time() - 3 * 3600 - 1
        os.utime(lock, (age, age))
        run(runner)
        assert len(calls('pi')) == pi_before + 1 and not lock.exists()
        # A live process never loses ownership, even when the lock is >3h old.
        lock.mkdir()
        (lock / 'pid').write_text(str(os.getpid()))
        os.utime(lock, (age, age))
        pi_before = len(calls('pi'))
        run(runner)
        assert len(calls('pi')) == pi_before and lock.exists()
        shutil.rmtree(lock)
        # Two contenders recover one abandoned lock; only the winner reaches Pi.
        lock.mkdir()
        os.utime(lock, (age, age))
        first = subprocess.Popen(['bash', str(runner)], env=env | {'MOCK_PI_WAIT': '1'}, cwd=setup)
        second = subprocess.Popen(['bash', str(runner)], env=env | {'MOCK_PI_WAIT': '1'}, cwd=setup)
        try:
            deadline = time.monotonic() + 10
            while not (root / 'pi-ready').exists():
                assert time.monotonic() < deadline, 'mock Pi did not start'
                time.sleep(0.02)
            # A manual invocation also skips while the first is still running.
            run(runner)
            assert len(calls('pi')) == pi_before + 1 and lock.exists()
            # Do not release the winner until the competing invocation has skipped.
            while first.poll() is None and second.poll() is None:
                assert time.monotonic() < deadline, 'overlapping contender did not skip'
                time.sleep(0.02)
        finally:
            (root / 'pi-release').write_text('release')
            assert first.wait(timeout=20) == 0 and second.wait(timeout=20) == 0
        assert len(calls('pi')) == pi_before + 1 and not lock.exists()
        print('PASS: fresh/live locks prevent overlap; abandoned 3h locks recover safely with concurrent contenders')
        print('PASS: all memory-daily tests used temporary HOME and mocked pi/launchctl/osascript; no real launchd or agent invocation')


if __name__ == '__main__':
    main()
