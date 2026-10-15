#!/usr/bin/env python3
"""DEC-0018 qmd sandbox: temporary HOME, real YAML/Node, mocked npm/qmd/brew/git/pgrep.

Never installs packages, downloads models, commits data or accesses live host state.
"""
import json
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

MOCK = r'''#!/usr/bin/env python3
import datetime as dt
import json, os, sys, sqlite3, subprocess
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
if name == 'npm':
    if args == ['prefix', '-g']: print(prefix)
    elif args == ['root', '-g']: print(prefix / 'lib/node_modules')
    elif args[:2] == ['install', '-g']:
        assert len(args) == 3 and args[2].startswith('@tobilu/qmd@')
        package.mkdir(parents=True, exist_ok=True)
        (package / 'package.json').write_text(json.dumps({'version': args[2].split('@')[-1]}))
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
elif name == 'git':
    assert args[:1] == ['-C'] and args[2:] == ['rev-parse', '--git-common-dir'], args
    assert (Path(args[1]) / '.git').is_dir()
    print('.git')
elif name == 'pgrep':
    assert args[:1] == ['-f']
    sys.exit(0 if os.environ.get('MOCK_QMD_RUNNING') else 1)
elif name == 'qmd':
    if args == ['--version']:
        print('qmd ' + os.environ.get('MOCK_QMD_VERSION', json.loads((package / 'package.json').read_text())['version']))
        sys.exit(0)
    assert args[:2] == ['--index', 'dailydriver'], args
    operation = args[2:]
    assert operation in (['update'], ['embed']), 'canonical config must not use ad hoc collection/context commands'
    data = json.loads(subprocess.check_output(['ruby', '-r', 'yaml', '-r', 'json', '-e',
        'puts JSON.generate(YAML.safe_load(STDIN.read, aliases: false))'], input=config.read_bytes()))
    collections = data['collections']
    assert set(collections) == {'wiki', 'decisions', 'sources', 'bank'}
    assert all(Path(c['path']).is_absolute() and c['pattern'] == '**/*.md' for c in collections.values())
    if operation == ['embed'] and os.environ.get('MOCK_EMBED_FAIL'): sys.exit(2)
    if operation == ['update'] and os.environ.get('EXPECT_REBUILD'):
        assert not database.exists()
        assert not Path(str(database) + '-wal').exists()
        assert not Path(str(database) + '-shm').exists()
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as db:
        db.execute('CREATE TABLE IF NOT EXISTS store_collections (name TEXT, path TEXT, pattern TEXT)')
        db.execute('CREATE TABLE IF NOT EXISTS content_vectors (embedded_at TEXT)')
        db.execute('DELETE FROM store_collections')
        db.executemany('INSERT INTO store_collections VALUES (?, ?, ?)',
                       [(n, c['path'], c['pattern']) for n, c in collections.items()])
        if operation == ['embed']:
            db.execute('DELETE FROM content_vectors')
            db.execute('INSERT INTO content_vectors VALUES (?)',
                       [(dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=1)).isoformat()])
else: raise AssertionError('unmocked command: ' + name)
'''


def yaml_data(text):
    return json.loads(subprocess.check_output(['ruby', '-r', 'yaml', '-r', 'json', '-e',
                      'puts JSON.generate(YAML.safe_load(STDIN.read, aliases: false))'], input=text.encode('utf-8')))


def main():
    source = Path(__file__).resolve().parent.parent
    node = shutil.which('node')
    assert node and shutil.which('ruby'), 'Node >=22 and macOS Ruby/YAML are needed for the sandbox'
    installer = source / 'scripts/install-qmd.sh'
    with tempfile.TemporaryDirectory(prefix='qmd-install-test-') as temporary:
        root = Path(temporary).resolve()
        home = root / "home & quote's"
        home.mkdir()
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        mock = root / 'mock.py'
        mock.write_text(MOCK)
        for name in ('npm', 'brew', 'git', 'pgrep'):
            path = bin_dir / name
            path.write_text(f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(mock))} {name} "$@"\n')
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
            (path / '.git').mkdir()
            (path / '.git/HEAD').write_text('ref: refs/heads/synthetic\n')

        make_repo(repo)
        canonical = repo / 'qmd/dailydriver.yml'
        config = home / '.config/qmd/dailydriver.yml'
        database = home / '.cache/qmd/dailydriver.sqlite'
        manifest = home / 'npm prefix/lib/node_modules/@tobilu/qmd/package.json'

        def run(*args, success=True, extra=None):
            result = subprocess.run(['bash', str(installer), *args], env=env | (extra or {}),
                                    cwd=root, capture_output=True, text=True, timeout=30)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        def calls(name=None):
            file = root / 'calls.jsonl'
            items = [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []
            return [args for command, args in items if name is None or command == name]

        def snapshot():
            return {str(p.relative_to(home)): (p.read_bytes(), p.stat().st_mtime_ns)
                    for p in home.rglob('*') if p.is_file()}

        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before and calls() == [] and not canonical.exists()
        print('PASS: fresh --check is read-only and does not propose a missing canonical config')

        git_before = {str(p): p.read_bytes() for p in (repo / '.git').rglob('*') if p.is_file()}
        memory_before = {str(p): p.read_bytes() for p in (repo / 'memory').rglob('*') if p.is_file()}
        output = run()
        assert output.stdout.splitlines()[-1].endswith('collections=4; embed=complete)')
        assert 'Review and commit it yourself: cd $MEMORY_REPO && git add qmd/ && git commit -m "qmd: index config"' in output.stdout
        text = canonical.read_bytes().decode('utf-8')
        defaults = yaml_data(text)
        assert set(defaults['collections']) == {'wiki', 'decisions', 'sources', 'bank'}
        labels = {
            'wiki': 'Compiled pages; every statement cited; inbound attributed',
            'decisions': "Martin's decisions, his own words (authored)",
            'sources': 'Imported raw sources; corpus tells authorship (sessions/mail/teams/tasks = Martin; docs = the document; projects = the artifact)',
            'bank': "Claims by others, attributed; **never Martin's view**",
        }
        relative_roots = {'wiki': 'memory/wiki', 'decisions': 'memory/archive/decisions',
                          'sources': 'memory/archive/sources', 'bank': 'memory/bank'}
        for name, relative in relative_roots.items():
            assert defaults['collections'][name] == {'path': '$MEMORY_REPO/' + relative, 'pattern': '**/*.md',
                                                    'context': {'': labels[name]}}
        assert defaults['models'] == {
            'embed': 'hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf',
            'rerank': 'hf:ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/qwen3-reranker-0.6b-q8_0.gguf',
            'generate': 'hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf',
        }
        assert calls('git') == []
        assert {str(p): p.read_bytes() for p in (repo / '.git').rglob('*') if p.is_file()} == git_before
        assert {str(p): p.read_bytes() for p in (repo / 'memory').rglob('*') if p.is_file()} == memory_before
        assert calls('brew') == [['list', '--versions', 'sqlite'], ['install', 'sqlite']]
        assert ['install', '-g', '@tobilu/qmd@2.8.3'] in calls('npm')
        assert calls('qmd') == [['--version'], ['--index', 'dailydriver', 'update'], ['--index', 'dailydriver', 'embed']]
        print('PASS: absent config proposes four portable roots/contexts and pinned models, installs the pin, updates/embeds, never stages or commits')

        # Existing private formatting/context is authoritative, not replaced by defaults.
        text = ('# Preserve this comment: $MEMORY_REPO/memory/wiki\n' + text).replace(
            '    path: "$MEMORY_REPO/memory/wiki"', "    path: '$MEMORY_REPO/memory/wiki' # keep this comment")
        text = text.replace(json.dumps(labels['wiki']), json.dumps('Synthetic routing — $MEMORY_REPO/memory/wiki', ensure_ascii=False))
        text = text.replace('\n', '\r\n')
        canonical.write_bytes(text.encode('utf-8'))
        canonical_before = (canonical.read_bytes(), canonical.stat().st_mtime_ns)
        count = len(calls('qmd'))
        run()
        rendered = text
        for name, relative in relative_roots.items():
            token = '$MEMORY_REPO/' + relative
            if name == 'wiki':
                rendered = rendered.replace("path: '" + token + "'", "path: '" + str(repo / relative).replace("'", "''") + "'")
            else:
                rendered = rendered.replace(json.dumps(token), json.dumps(str(repo / relative), ensure_ascii=False))
        expected_copy = '# generated from $MEMORY_REPO/qmd/dailydriver.yml, do not edit\n' + rendered
        assert config.read_bytes() == expected_copy.encode('utf-8')
        assert (canonical.read_bytes(), canonical.stat().st_mtime_ns) == canonical_before
        assert calls('qmd')[count:] == [['--version'], ['--index', 'dailydriver', 'update'], ['--index', 'dailydriver', 'embed']]
        print('PASS: present YAML is authoritative; only path scalars render, preserving contexts/comments/CRLF bytes and canonical mtime')
        flow_data = {'global_context': 'Synthetic — metadata', **yaml_data(text)}
        flow_text = json.dumps(flow_data, ensure_ascii=False)
        canonical.write_bytes(flow_text.encode('utf-8'))
        run('--no-embed')
        flow_copy = flow_text
        for relative in relative_roots.values():
            flow_copy = flow_copy.replace('"path": ' + json.dumps('$MEMORY_REPO/' + relative),
                                          '"path": ' + json.dumps(str(repo / relative), ensure_ascii=False))
        assert config.read_bytes() == ('# generated from $MEMORY_REPO/qmd/dailydriver.yml, do not edit\n' + flow_copy).encode('utf-8')
        canonical.write_bytes(text.encode('utf-8'))
        run('--no-embed')
        config.unlink()
        config.symlink_to(canonical)
        before = snapshot()
        count = len(calls())
        run(success=False)
        assert snapshot() == before and len(calls()) == count
        config.unlink()
        run('--no-embed')
        print('PASS: Unicode flow-YAML path spans render correctly; a symlinked host copy cannot overwrite canonical config')

        before = snapshot()
        count = len(calls('qmd'))
        run()
        assert config.stat().st_mtime_ns == before[str(config.relative_to(home))][1]
        assert calls('npm').count(['install', '-g', '@tobilu/qmd@2.8.3']) == 1
        before = snapshot()
        output = run('--check')
        assert 'check OK' in output.stdout and 'last embed age=360' in output.stdout
        assert snapshot() == before
        run('--check', success=False, extra={'MOCK_QMD_VERSION': '2.8.30'})
        assert snapshot() == before
        config.write_bytes(b'# drifted host copy\n')
        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before
        run('--no-embed')
        assert config.read_bytes() == expected_copy.encode('utf-8')
        assert calls('qmd')[-1] == ['--index', 'dailydriver', 'update']
        print('PASS: repeats are idempotent; doctor checks exact pin/canonical-copy drift and embed age without writing; --no-embed skips embed')

        good_text = canonical.read_bytes()
        for transform in (
            lambda d: d['collections']['wiki'].update(path='$MEMORY_REPO/memory/quarantine'),
            lambda d: d['collections']['wiki'].update(path='$MEMORY_REPO/memory/core'),
            lambda d: d['collections']['wiki'].update(path=str(repo / 'memory/wiki')),
            lambda d: d['collections']['wiki'].update(path='$MEMORY_REPO/memory/wiki/../core'),
            lambda d: d['collections']['wiki'].update(path='$MEMORY_REPO/outside'),
            lambda d: d['collections']['wiki'].update(pattern='**/*'),
            lambda d: d['collections']['wiki'].update(update=''),
            lambda d: d.update(update='synthetic-command'),
            lambda d: d['collections']['bank'].update(context={'update': 'forbidden even here'}),
            lambda d: d['collections'].update(extra=d['collections']['wiki']),
            lambda d: d.pop('models'),
        ):
            data = yaml_data(good_text.decode('utf-8'))
            transform(data)
            canonical.write_text(json.dumps(data))
            before = snapshot()
            count = len(calls())
            run(success=False)
            assert snapshot() == before and len(calls()) == count
        canonical.write_bytes(good_text + b'update: one\nupdate: two\n')
        count = len(calls())
        run(success=False)
        assert len(calls()) == count
        canonical.write_bytes(good_text)
        print('PASS: invalid canonical roots/masks/collections/models and any update key or duplicate key are refused before install/write')

        wiki = repo / 'memory/wiki'
        shutil.rmtree(wiki)
        for target in (repo / 'memory/quarantine', repo / 'memory/core', home):
            wiki.symlink_to(target, target_is_directory=True)
            count = len(calls())
            run(success=False)
            assert len(calls()) == count
            wiki.unlink()
        wiki.mkdir()
        print('PASS: resolved roots cannot escape the approved four or reach quarantine/core')

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
        print('PASS: standalone installer works outside checkout cwd, and qmd/mcp-node work with GUI-minimal PATH')

        model = home / '.cache/qmd/models/synthetic.gguf'
        model.parent.mkdir(parents=True)
        model.write_bytes(b'synthetic-model-never-copy')
        other_index = database.parent / 'other.sqlite'
        other_index.write_bytes(b'unrelated-index-never-delete')
        with sqlite3.connect(database) as db:
            db.execute('CREATE TABLE obsolete_marker (value TEXT)')
        wal = Path(str(database) + '-wal')
        shm = Path(str(database) + '-shm')
        wal.write_bytes(b'')
        shm.write_bytes(b'synthetic-idle-sidecar')
        canonical_before = canonical.read_bytes()
        output = run('--rebuild', extra={'EXPECT_REBUILD': '1'})
        with sqlite3.connect(database) as db:
            assert not db.execute("SELECT name FROM sqlite_master WHERE name='obsolete_marker'").fetchall()
        assert model.read_bytes() == b'synthetic-model-never-copy'
        assert other_index.read_bytes() == b'unrelated-index-never-delete'
        assert not wal.exists() and not shm.exists() and canonical.read_bytes() == canonical_before
        assert calls('qmd')[-2:] == [['--index', 'dailydriver', 'update'], ['--index', 'dailydriver', 'embed']]
        assert not any(p.suffix in ('.sqlite', '.gguf') for p in repo.rglob('*'))
        print('PASS: --rebuild removes only the named index/sidecars, updates/embeds fresh, and preserves models, other indexes and canonical config')

        lock = repo / '.git/memory-mcp-writer.lock'
        for reason in ('process', 'lock', 'wal'):
            extra = {'MOCK_QMD_RUNNING': '1'} if reason == 'process' else {}
            if reason == 'lock':
                lock.write_text('synthetic held writer lock')
            if reason == 'wal':
                wal.write_bytes(b'synthetic-active-wal')
            before = snapshot()
            count = len(calls('qmd'))
            run('--rebuild', success=False, extra=extra)
            assert snapshot() == before and len(calls('qmd')) == count
            if lock.exists():
                lock.unlink()
            if wal.exists():
                wal.unlink()
        print('PASS: --rebuild refuses running qmd, held memory writer lock or active WAL without modifying HOME')

        manifest.write_text('{"version":"9.9.9"}')
        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before
        run('--no-embed')
        assert json.loads(manifest.read_text())['version'] == '2.8.3'
        run(success=False, extra={'MOCK_EMBED_FAIL': '1'})
        with sqlite3.connect(database) as db:
            db.execute('DELETE FROM content_vectors')
        assert 'never (no embedded chunks)' in run('--check').stdout
        with sqlite3.connect(database) as db:
            db.execute('UPDATE store_collections SET path=? WHERE name=?', (str(repo / 'memory/quarantine'), 'bank'))
        before = snapshot()
        run('--check', success=False)
        assert snapshot() == before
        print('PASS: pin drift repaired, embed failures propagated, and doctor handles unembedded or unsafe SQLite-only state read-only')

        second = home / 'alternate memory'
        make_repo(second)
        settings = home / '.config/memory-mcp/config.json'
        settings.parent.mkdir(parents=True)
        settings.write_text(json.dumps({'memoryRepo': str(second)}))
        run('--no-embed')
        assert (second / 'qmd/dailydriver.yml').exists()
        assert yaml_data(config.read_text())['collections']['wiki']['path'] == str(second / 'memory/wiki')
        run('--no-embed', extra={'MEMORY_REPO': str(repo)})
        assert yaml_data(config.read_text())['collections']['wiki']['path'] == str(repo / 'memory/wiki')
        for override in ('INDEX_PATH', 'QMD_GENERATE_MODEL'):
            before = snapshot()
            run('--check', success=False, extra={'MEMORY_REPO': str(repo), override: 'synthetic-conflict'})
            assert snapshot() == before
        assert all(args[2:] == ['rev-parse', '--git-common-dir'] for args in calls('git'))
        print('PASS: repository settings precedence preserved; conflicting qmd overrides refused; mocked git saw no add/commit/push')
    print('All DEC-0018 qmd sandbox checks passed (no real HOME, network or git mutation).')


if __name__ == '__main__':
    main()
