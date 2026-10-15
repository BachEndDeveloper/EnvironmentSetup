#!/usr/bin/env python3
"""Provision/check the dailydriver qmd index; never write to the memory repository."""
import argparse
import datetime as dt
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

INDEX = 'dailydriver'
MASK = '**/*.md'
# Deliberately no core: reviewed positions are read through memory_core_read.
COLLECTIONS = {
    'wiki': ('memory/wiki', 'Compiled pages; every statement cited; inbound attributed'),
    'decisions': ('memory/archive/decisions', "Martin's decisions, his own words (authored)"),
    'sources': ('memory/archive/sources', 'Imported raw sources; corpus tells authorship '
                '(sessions/mail/teams/tasks = Martin; docs = the document; projects = the artifact)'),
    'bank': ('memory/bank', "Claims by others, attributed; **never Martin's view**"),
}
WRAPPER_MARKER = '# EnvironmentSetup: npm qmd launcher'


def command(*args, capture=False):
    return subprocess.run([str(arg) for arg in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def memory_paths():
    configured = os.environ.get('MEMORY_REPO')
    if configured is None:
        settings = Path.home() / '.config/memory-mcp/config.json'
        if settings.exists():
            data = json.loads(settings.read_text())
            if not isinstance(data, dict):
                raise ValueError('memory-mcp settings must be a JSON object')
            configured = data.get('memoryRepo')
    if configured is None:
        configured = str(Path.home() / 'source/DailyDriver')
    if not isinstance(configured, str) or not configured.strip():
        raise ValueError('memoryRepo / MEMORY_REPO must be a non-empty directory path')
    repo = Path(configured).expanduser().resolve()
    if not repo.is_dir():
        raise ValueError('memory repository does not exist; set MEMORY_REPO or memoryRepo')
    # Check both lexical and resolved roots: a symlink must not hide a forbidden path.
    forbidden = [repo / 'memory' / name for name in ('quarantine', 'core')]
    forbidden += [path.resolve() for path in forbidden]
    paths = {name: repo / relative for name, (relative, _) in COLLECTIONS.items()}
    for name, path in paths.items():
        if unsafe_path(path, forbidden):
            raise ValueError(f'refusing {name}: collection overlaps memory/quarantine or memory/core')
        if not path.is_dir():
            raise ValueError(f'missing collection directory: {name} (initialize the memory repository first)')
    return paths, forbidden


def unsafe_path(path, forbidden):
    path = Path(path).expanduser()
    if not path.is_absolute():
        raise ValueError('collection paths must be absolute')
    for candidate in (path, path.resolve()):
        # Also reject forbidden trees in another repository (or a MEMORY_REPO
        # accidentally rooted inside one), not only this repository's roots.
        if any(part == 'memory' and candidate.parts[index + 1] in ('quarantine', 'core')
               for index, part in enumerate(candidate.parts[:-1])):
            return True
        for root in forbidden:
            if candidate == root or root in candidate.parents or candidate in root.parents:
                return True
    return False


def read_config(package, config):
    if not config.exists():
        return {}
    # Use the YAML parser shipped with the pinned package, not an extra global dependency.
    # Do not invoke qmd status/list: opening its store can migrate/create a database.
    script = """
const fs = require('node:fs');
const { createRequire } = require('node:module');
const yaml = createRequire(process.argv[1] + '/package.json')('yaml');
process.stdout.write(JSON.stringify(yaml.parse(fs.readFileSync(process.argv[2], 'utf8'))));
"""
    data = json.loads(command('node', '-e', script, package, config, capture=True))
    if not isinstance(data, dict) or not isinstance(data.get('collections'), dict):
        raise ValueError('invalid qmd collections config')
    for name, collection in data['collections'].items():
        if not isinstance(collection, dict) or not isinstance(collection.get('path'), str):
            raise ValueError(f'invalid collection: {name}')
    return data['collections']


def check_collections(collections, expected, forbidden):
    errors = []
    for name, collection in collections.items():
        if unsafe_path(collection['path'], forbidden):
            errors.append(f'{name}: forbidden quarantine/core overlap')
    for name, path in expected.items():
        collection = collections.get(name, {})
        if collection.get('path') != str(path) or collection.get('pattern') != MASK:
            errors.append(f'{name}: missing or incorrect path/mask')
    return errors


def read_index(database):
    if not database.is_file():
        raise ValueError('named index does not exist')
    # immutable=1 guarantees no journal/SHM creation during --check. Refuse a live
    # WAL rather than silently reading an old checkpoint without its newer rows.
    wal = Path(str(database) + '-wal')
    if wal.exists() and wal.stat().st_size:
        raise ValueError('index has an active WAL; finish the qmd refresh and retry --check')
    with sqlite3.connect(database.as_uri() + '?mode=ro&immutable=1', uri=True) as db:
        collections = {name: {'path': path, 'pattern': pattern}
                       for name, path, pattern in db.execute('SELECT name, path, pattern FROM store_collections')}
        last_embed = db.execute('SELECT MAX(embedded_at) FROM content_vectors').fetchone()[0]
    return collections, last_embed


def embed_age(last_embed):
    if not last_embed:
        return 'never (no embedded chunks)'
    stamp = dt.datetime.fromisoformat(last_embed.replace('Z', '+00:00'))
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=dt.timezone.utc)
    age = max(0, int((dt.datetime.now(dt.timezone.utc) - stamp).total_seconds()))
    return f'{age}s (latest embedded chunk: {last_embed})'


def install_launcher(binary):
    local = Path.home() / '.local/bin/qmd'
    if local == binary:
        return  # npm itself owns this path when prefix=$HOME/.local.
    node_binary = shutil.which('node')
    if node_binary is None:
        raise ValueError('node is missing from PATH')
    node = Path(node_binary).resolve()
    content = ('#!/bin/sh\n' + WRAPPER_MARKER + '\n'
               + 'export PATH=' + shlex.quote(str(node.parent)) + ':"$PATH"\n'
               + 'exec ' + shlex.quote(str(node)) + ' ' + shlex.quote(str(binary)) + ' "$@"\n')
    if local.exists() or local.is_symlink():
        if not local.is_symlink() and WRAPPER_MARKER not in local.read_text():
            raise ValueError('unmanaged ~/.local/bin/qmd exists; move it aside before installing')
        if not local.is_symlink() and local.read_text() == content:
            return
        local.unlink()
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_text(content)
    local.chmod(0o755)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version', help=argparse.SUPPRESS)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--check', action='store_true', help='read-only version, paths and embed-age check')
    modes.add_argument('--no-embed', action='store_true', help='configure and update, but skip model download/embedding')
    args = parser.parse_args()
    expected, forbidden = memory_paths()  # Refuse unsafe inputs before any installer command.
    # A different config/cache override could mix this index with another qmd use.
    # Use the same standard HOME locations as memory-mcp's named index.
    for variable in ('INDEX_PATH', 'QMD_CONFIG_DIR', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
        if os.environ.get(variable):
            raise ValueError(f'unset {variable} to provision/check the standard dailydriver index')
    node_version = command('node', '--version', capture=True).strip()
    match = re.fullmatch(r'v(\d+)\.\d+\.\d+', node_version)
    if not match or int(match[1]) < 22:
        raise ValueError('qmd requires Node >=22 (use the nvm default LTS)')
    prefix = Path(command('npm', 'prefix', '-g', capture=True).strip())
    package = Path(command('npm', 'root', '-g', capture=True).strip()) / '@tobilu/qmd'
    binary = prefix / 'bin/qmd'
    manifest = package / 'package.json'
    installed = json.loads(manifest.read_text()).get('version') if manifest.exists() else None
    errors = []
    if args.check:
        if installed != args.version:
            errors.append(f'qmd package version {installed or "missing"}; expected {args.version}')
    else:
        if not shutil.which('brew'):
            raise ValueError('Homebrew is required (brew install sqlite)')
        # brew list exits nonzero for a missing formula; handle that without masking install failures.
        sqlite = subprocess.run(['brew', 'list', '--versions', 'sqlite'],
                                capture_output=True, text=True, check=False)
        if sqlite.returncode or not sqlite.stdout.strip():
            command('brew', 'install', 'sqlite')
        if installed != args.version or not binary.is_file():
            command('npm', 'install', '-g', f'@tobilu/qmd@{args.version}')
    if binary.is_file():
        version = command(binary, '--version', capture=True).strip()
        if not re.search(r'(?<![\d.])' + re.escape(args.version) + r'(?![\d.\w-])', version):
            errors.append(f'qmd CLI version does not match pin {args.version}')
    else:
        errors.append('qmd global binary is missing')
    config = Path.home() / '.config/qmd/dailydriver.yml'
    database = Path.home() / '.cache/qmd/dailydriver.sqlite'
    if args.check:
        if config.exists() and manifest.exists():
            collections = read_config(package, config)
            errors += ['config: ' + error for error in check_collections(collections, expected, forbidden)]
        else:
            errors.append('named index config is missing (or qmd is not installed)')
        age = 'unknown'
        try:
            collections, last_embed = read_index(database)
            errors += ['index: ' + error for error in check_collections(collections, expected, forbidden)]
            age = embed_age(last_embed)
        except (ValueError, sqlite3.Error) as error:
            errors.append(str(error))
        for error in errors:
            print('ERROR: ' + error, file=sys.stderr)
        print(f'qmd: check {"FAILED" if errors else "OK"} (pin={args.version}; index={INDEX}; last embed age={age})')
        return 1 if errors else 0
    if errors:
        raise ValueError('; '.join(errors))
    collections = read_config(package, config)
    qmd = (binary, '--index', INDEX)
    # Remove unsafe collections before any add/update can scan content. Ancestor
    # paths (e.g. memory/) are unsafe too, even with a mask excluding quarantine.
    for name, collection in list(collections.items()):
        if unsafe_path(collection['path'], forbidden):
            print(f'WARNING: removing {name}: collection overlaps quarantine/core', file=sys.stderr)
            command(*qmd, 'collection', 'remove', name)
            del collections[name]
    # Remove all wrong managed paths first: two collections may have swapped
    # roots, and qmd refuses adding a path/mask already owned by another name.
    for name, path in expected.items():
        existing = collections.get(name)
        if existing and (existing['path'] != str(path) or existing.get('pattern') != MASK):
            command(*qmd, 'collection', 'remove', name)
            del collections[name]
    for name, path in expected.items():
        existing = collections.get(name)
        if not existing:
            command(*qmd, 'collection', 'add', path, '--name', name, '--mask', MASK)
        label = COLLECTIONS[name][1]
        if not existing or existing.get('context', {}).get('') != label:
            command(*qmd, 'context', 'add', f'qmd://{name}', label)
    errors = check_collections(read_config(package, config), expected, forbidden)
    if errors:
        raise ValueError('; '.join(errors))
    install_launcher(binary)
    command(*qmd, 'update')
    if not args.no_embed:
        command(*qmd, 'embed')
    print(f'qmd: ready (pin={args.version}; index={INDEX}; collections=4; embed={"skipped" if args.no_embed else "complete"})')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'qmd: ERROR ({error})', file=sys.stderr)
        sys.exit(1)
