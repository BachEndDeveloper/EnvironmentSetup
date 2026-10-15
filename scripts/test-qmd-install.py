#!/usr/bin/env python3
"""Sandbox qmd installation with mocked npm/qmd/brew and temporary HOME.

Uses real Node for the installer's YAML-reader/launcher code. Mock qmd emits the
JSON subset of YAML; mock npm supplies a JSON-only stand-in for its YAML parser.
No package installs, downloads, real indexes, host configuration or model calls.
"""
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

MOCK = r'''#!/usr/bin/env python3
import datetime as dt
import json, os, sys, sqlite3
from pathlib import Path
root = Path(os.environ['SANDBOX_ROOT'])
home = Path(os.environ['HOME'])
assert root.name.startswith('qmd-install-test-') and home.parent == root
name = sys.argv[1]
args = sys.argv[2:]
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps([name, args]) + '\n')
prefix = home / 'npm prefix'
package = prefix / 'lib/node_modules/@tobilu/qmd'
config = home / '.config/qmd/dailydriver.yml'
database = home / '.cache/qmd/dailydriver.sqlite'
def read_config():
    return json.loads(config.read_text()) if config.exists() else {'collections': {}}
def save_config(data):
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(json.dumps(data, indent=2) + '\n')
def sync(data, embed=False):
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as db:
        db.execute('CREATE TABLE IF NOT EXISTS store_collections (name TEXT, path TEXT, pattern TEXT)')
        db.execute('CREATE TABLE IF NOT EXISTS content_vectors (embedded_at TEXT)')
        db.execute('DELETE FROM store_collections')
        db.executemany('INSERT INTO store_collections VALUES (?, ?, ?)',
                       [(n, c['path'], c['pattern']) for n, c in data['collections'].items()])
        if embed:
            db.execute('DELETE FROM content_vectors')
            db.execute('INSERT INTO content_vectors VALUES (?)',
                       [(dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=1)).isoformat()])
if name == 'npm':
    if args == ['prefix', '-g']: print(prefix)
    elif args == ['root', '-g']: print(prefix / 'lib/node_modules')
    elif args[:2] == ['install', '-g']:
        assert len(args) == 3 and args[2].startswith('@tobilu/qmd@')
        package.mkdir(parents=True, exist_ok=True)
        (package / 'package.json').write_text(json.dumps({'version': args[2].split('@')[-1]}))
        parser = package / 'node_modules/yaml'
        parser.mkdir(parents=True, exist_ok=True)
        (parser / 'index.js').write_text('module.exports = {parse: JSON.parse};\n')
        binary = prefix / 'bin/qmd'
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text('#!/usr/bin/env node\n' +
            "const r = require('node:child_process').spawnSync(" + json.dumps(sys.executable) +
            ', [' + json.dumps(str(root / 'mock.py')) + ", 'qmd', ...process.argv.slice(2)], {stdio: 'inherit'});\n" +
            'process.exit(r.status ?? 1);\n')
        binary.chmod(0o755)
    else: raise AssertionError('unmocked npm call')
elif name == 'brew':
    state = root / 'sqlite-installed'
    if args == ['list', '--versions', 'sqlite']:
        if state.exists(): print('sqlite 3.50.0')
        else: sys.exit(1)
    elif args == ['install', 'sqlite']: state.write_text('installed')
    else: raise AssertionError('unmocked brew call')
elif name == 'qmd':
    if args == ['--version']:
        print('qmd ' + os.environ.get('MOCK_QMD_VERSION', json.loads((package / 'package.json').read_text())['version']))
        sys.exit(0)
    assert args[:2] == ['--index', 'dailydriver'], args
    args = args[2:]
    data = read_config()
    collections = data['collections']
    if args[:2] == ['collection', 'add']:
        path = args[2]; n = args[args.index('--name') + 1]
        assert args[-2:] == ['--mask', '**/*.md']
        assert n not in collections
        assert not any(c['path'] == path and c['pattern'] == '**/*.md' for c in collections.values())
        assert '/memory/quarantine' not in str(Path(path).resolve())
        assert '/memory/core' not in str(Path(path).resolve())
        collections[n] = {'path': path, 'pattern': '**/*.md'}
    elif args[:2] == ['collection', 'remove']:
        del collections[args[2]]
    elif args[:2] == ['context', 'add']:
        n = args[2].removeprefix('qmd://')
        collections[n].setdefault('context', {})[''] = args[3]
    elif args == ['update']:
        assert all('/memory/quarantine' not in c['path'] and '/memory/core' not in c['path']
                   for c in collections.values())
    elif args == ['embed']:
        if os.environ.get('MOCK_EMBED_FAIL'): sys.exit(2)
    else: raise AssertionError('unmocked qmd command: ' + repr(args))
    save_config(data)
    sync(data, embed=args == ['embed'])
else: raise AssertionError('unmocked command: ' + name)
'''


def main():
    source = Path(__file__).resolve().parent.parent
    node = shutil.which('node')
    assert node, 'Node >=22 is needed for the sandbox gate'
    installer = source / 'scripts/install-qmd.sh'
    with tempfile.TemporaryDirectory(prefix='qmd-install-test-') as temporary:
        root = Path(temporary).resolve()
        home = root / "home & quote's"
        home.mkdir()
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        mock = root / 'mock.py'
        mock.write_text(MOCK)
        for name in ('npm', 'brew'):
            path = bin_dir / name
            path.write_text(f'#!/bin/sh\nexec {shlex_quote(sys.executable)} {shlex_quote(str(mock))} {name} "$@"\n')
            path.chmod(0o755)
        (bin_dir / 'node').symlink_to(node)
        env = {'HOME': str(home), 'SANDBOX_ROOT': str(root),
               'PATH': f'{bin_dir}:{Path(sys.executable).parent}:/usr/bin:/bin',
               'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
        repo = home / 'source/DailyDriver'

        def make_repo(path):
            for relative in ('wiki', 'archive/decisions', 'archive/sources', 'bank', 'quarantine', 'core'):
                (path / 'memory' / relative).mkdir(parents=True)
            (path / 'memory/wiki/example.md').write_text('# Synthetic page\n')

        make_repo(repo)
        config = home / '.config/qmd/dailydriver.yml'
        database = home / '.cache/qmd/dailydriver.sqlite'
        manifest = home / 'npm prefix/lib/node_modules/@tobilu/qmd/package.json'

        def run(*args, success=True, extra=None):
            result = subprocess.run(['bash', str(installer), *args], env=env | (extra or {}),
                                    cwd=source, capture_output=True, text=True, timeout=30)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        def calls(name=None):
            file = root / 'calls.jsonl'
            items = [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []
            return [args for command, args in items if name is None or command == name]

        def snapshot():
            return {str(p.relative_to(home)): (p.read_bytes(), p.stat().st_mtime_ns)
                    for p in home.rglob('*') if p.is_file()}

        def read_config():
            return json.loads(config.read_text())

        def write_config(data):
            config.write_text(json.dumps(data))

        before = snapshot()
        output = run('--check', success=False)
        assert snapshot() == before
        assert 'named index does not exist' in output.stderr and 'check FAILED' in output.stdout
        assert calls('brew') == [] and not any(a[:2] == ['install', '-g'] for a in calls('npm'))
        print('PASS: --check on a fresh HOME is read-only and reports missing version/index')

        memory_before = {str(p): p.read_bytes() for p in repo.rglob('*') if p.is_file()}
        output = run()
        assert output.stdout.splitlines()[-1].endswith('collections=4; embed=complete)')
        data = read_config()['collections']
        assert set(data) == {'wiki', 'decisions', 'sources', 'bank'}
        labels = {
            'wiki': 'Compiled pages; every statement cited; inbound attributed',
            'decisions': "Martin's decisions, his own words (authored)",
            'sources': 'Imported raw sources; corpus tells authorship (sessions/mail/teams/tasks = Martin; docs = the document; projects = the artifact)',
            'bank': "Claims by others, attributed; **never Martin's view**",
        }
        for name, relative in [('wiki', 'wiki'), ('decisions', 'archive/decisions'),
                               ('sources', 'archive/sources'), ('bank', 'bank')]:
            assert data[name] == {'path': str(repo / 'memory' / relative), 'pattern': '**/*.md',
                                  'context': {'': labels[name]}}
        assert calls('brew') == [['list', '--versions', 'sqlite'], ['install', 'sqlite']]
        assert ['install', '-g', '@tobilu/qmd@2.8.3'] in calls('npm')
        qmd_calls = calls('qmd')
        assert sum(a[2:4] == ['collection', 'add'] for a in qmd_calls) == 4
        assert sum(a[2:4] == ['context', 'add'] for a in qmd_calls) == 4
        assert qmd_calls[-2:] == [['--index', 'dailydriver', 'update'], ['--index', 'dailydriver', 'embed']]
        assert {str(p): p.read_bytes() for p in repo.rglob('*') if p.is_file()} == memory_before
        print('PASS: fresh install uses the exact npm pin, installs SQLite, creates four collections/labels and updates/embeds')

        config_before = config.read_bytes()
        launcher_before = (home / '.local/bin/qmd').stat().st_mtime_ns
        count = len(calls('qmd'))
        npm_installs = calls('npm').count(['install', '-g', '@tobilu/qmd@2.8.3'])
        run()
        assert config.read_bytes() == config_before
        assert calls('qmd')[count:] == [['--version'], ['--index', 'dailydriver', 'update'],
                                             ['--index', 'dailydriver', 'embed']]
        assert calls('npm').count(['install', '-g', '@tobilu/qmd@2.8.3']) == npm_installs
        assert (home / '.local/bin/qmd').stat().st_mtime_ns == launcher_before
        print('PASS: repeat install keeps matching collections/contexts and does not reinstall or rewrite the launcher')

        before = snapshot()
        count = len(calls('qmd'))
        output = run('--check')
        assert 'check OK' in output.stdout and 'last embed age=360' in output.stdout
        assert snapshot() == before and calls('qmd')[count:] == [['--version']]
        run('--check', success=False, extra={'MOCK_QMD_VERSION': '2.8.30'})
        assert snapshot() == before
        print('PASS: --check verifies the exact CLI pin, config and SQLite paths, reports embed age and changes no HOME files')
        with sqlite3.connect(database) as db:
            db.execute('DELETE FROM content_vectors')
        before = snapshot()
        assert 'never (no embedded chunks)' in run('--check').stdout
        assert snapshot() == before
        print('PASS: doctor reports an unembedded index explicitly without inventing a freshness threshold')

        # Stable launcher uses absolute npm/Node paths even without Node on GUI PATH.
        launcher = home / '.local/bin/qmd'
        output = subprocess.run([str(launcher), '--version'], env=env | {'PATH': '/usr/bin:/bin'},
                                capture_output=True, text=True, check=True)
        assert '2.8.3' in output.stdout
        nvm_bin = home / '.nvm/versions/node/v99.0.0/bin'
        nvm_bin.mkdir(parents=True)
        (nvm_bin / 'node').symlink_to(node)
        alias = home / '.nvm/alias/default'
        alias.parent.mkdir(parents=True)
        alias.write_text('v99.0.0\n')
        output = subprocess.run(['bash', str(source / 'MCP/mcp-node'), '-e',
                                 "require('node:child_process').execFileSync('qmd', ['--version'], {stdio: 'inherit'})"],
                                env=env | {'PATH': '/usr/bin:/bin'}, capture_output=True, text=True, check=True)
        assert '2.8.3' in output.stdout
        print('PASS: qmd and mcp-node find the pinned npm tool with a GUI-minimal PATH')

        manifest.write_text('{"version":"9.9.9"}')
        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before
        run('--no-embed')
        assert json.loads(manifest.read_text())['version'] == '2.8.3'
        assert calls('qmd')[-1] == ['--index', 'dailydriver', 'update']
        run(success=False, extra={'MOCK_EMBED_FAIL': '1'})
        print('PASS: version drift reinstalls only the pin; --no-embed skips embedding and embed failures fail the run')

        data = read_config()
        data['collections']['wiki']['path'] = str(repo / 'memory/archive/sources')
        data['collections']['wiki']['pattern'] = '*.txt'
        data['collections']['leak'] = {'path': str(repo / 'memory/quarantine/nested'), 'pattern': '**/*.md'}
        data['collections']['positions'] = {'path': str(repo / 'memory/core'), 'pattern': '**/*.md'}
        data['collections']['other-repo-leak'] = {'path': str(home / 'another/memory/quarantine'), 'pattern': '**/*.md'}
        data['collections']['ancestor'] = {'path': str(repo / 'memory'), 'pattern': '**/*.md'}
        write_config(data)
        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before
        count = len(calls('qmd'))
        output = run('--no-embed')
        assert 'WARNING: removing leak' in output.stderr
        assert set(read_config()['collections']) == {'wiki', 'decisions', 'sources', 'bank'}
        operations = calls('qmd')[count:]
        first_add = next(i for i, a in enumerate(operations) if a[2:4] == ['collection', 'add'])
        for name in ('leak', 'positions', 'other-repo-leak', 'ancestor'):
            assert operations.index(['--index', 'dailydriver', 'collection', 'remove', name]) < first_add
        run('--check')
        print('PASS: wrong path/mask repaired; quarantine, core and ancestor collections warned/removed before indexing')
        data = read_config()
        wiki_path = data['collections']['wiki']['path']
        decisions_path = data['collections']['decisions']['path']
        data['collections']['wiki']['path'] = decisions_path
        data['collections']['decisions']['path'] = wiki_path
        write_config(data)
        run('--no-embed')
        assert read_config()['collections']['wiki']['path'] == wiki_path
        assert read_config()['collections']['decisions']['path'] == decisions_path
        print('PASS: swapped managed collection paths repaired without qmd duplicate-path conflicts')

        # Unsafe expected roots are refused before even npm/brew discovery.
        wiki = repo / 'memory/wiki'
        shutil.rmtree(wiki)
        for target in (repo / 'memory/quarantine', repo / 'memory/core'):
            wiki.symlink_to(target, target_is_directory=True)
            count = len(calls())
            output = run('--no-embed', success=False)
            assert 'refusing wiki' in output.stderr and len(calls()) == count
            wiki.unlink()
        wiki.mkdir()
        nested = repo / 'memory/quarantine/accidental-repo'
        make_repo(nested)
        count = len(calls())
        run('--no-embed', success=False, extra={'MEMORY_REPO': str(nested)})
        assert len(calls()) == count
        print('PASS: symlinked/nested quarantine/core collection paths are refused before installer activity')

        second = home / 'alternate memory'
        make_repo(second)
        settings = home / '.config/memory-mcp/config.json'
        settings.parent.mkdir(parents=True)
        settings.write_text(json.dumps({'memoryRepo': str(second)}))
        run('--no-embed')
        assert read_config()['collections']['wiki']['path'] == str(second / 'memory/wiki')
        run('--no-embed', extra={'MEMORY_REPO': str(repo)})
        assert read_config()['collections']['wiki']['path'] == str(repo / 'memory/wiki')
        before = snapshot()
        run('--check', success=False, extra={'INDEX_PATH': str(root / 'other.sqlite'), 'MEMORY_REPO': str(repo)})
        assert snapshot() == before
        print('PASS: MEMORY_REPO overrides settings, settings overrides default; conflicting qmd locations refused')

        with sqlite3.connect(database) as db:
            db.execute('UPDATE store_collections SET path=? WHERE name=?',
                       (str(repo / 'memory/quarantine'), 'bank'))
        before = snapshot()
        run('--check', success=False, extra={'MEMORY_REPO': str(repo)})
        assert snapshot() == before
        wal = Path(str(database) + '-wal')
        wal.write_bytes(b'synthetic-active-wal')
        before = snapshot()
        output = run('--check', success=False, extra={'MEMORY_REPO': str(repo)})
        assert 'active WAL' in output.stderr and snapshot() == before
        print('PASS: doctor catches unsafe SQLite-only paths and refuses live WAL without writing sidecars')
    print('All qmd sandbox checks passed (no real HOME or network changes).')


def shlex_quote(value):
    import shlex
    return shlex.quote(value)


if __name__ == '__main__':
    main()
