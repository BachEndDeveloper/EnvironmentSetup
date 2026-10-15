#!/usr/bin/env python3
"""Install/check qmd from the portable, privately reviewed DailyDriver config."""
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
COLLECTIONS = {
    'wiki': ('memory/wiki', 'Compiled pages; every statement cited; inbound attributed'),
    'decisions': ('memory/archive/decisions', "Martin's decisions, his own words (authored)"),
    'sources': ('memory/archive/sources', 'Imported raw sources; corpus tells authorship '
                '(sessions/mail/teams/tasks = Martin; docs = the document; projects = the artifact)'),
    'bank': ('memory/bank', "Claims by others, attributed; **never Martin's view**"),
}
# Explicit upstream v2.8.3 defaults; proposing a config never follows newer defaults.
MODELS = {
    'embed': 'hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf',
    'rerank': 'hf:ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/qwen3-reranker-0.6b-q8_0.gguf',
    'generate': 'hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf',
}
HEADER = '# generated from $MEMORY_REPO/qmd/dailydriver.yml, do not edit\n'
WRAPPER_MARKER = '# EnvironmentSetup: npm qmd launcher'
# macOS Ruby's standard-library safe loader permits validation before npm installs.
# Scalar source spans let us render ONLY collection paths, preserving other bytes.
YAML_READER = r'''
require 'yaml'
require 'json'
text = STDIN.read
stream = Psych.parse_stream(text)
raise 'one document required' unless stream.children.length == 1
root = stream.children.first.root
def inspect_node(node)
  raise 'aliases not allowed' if node.is_a?(Psych::Nodes::Alias)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map do |key, _|
      raise 'scalar keys required' unless key.is_a?(Psych::Nodes::Scalar)
      key.value
    end
    raise 'duplicate keys not allowed' unless keys.uniq.length == keys.length
  end
  (node.children || []).each { |child| inspect_node(child) }
end
inspect_node(root)
def field(node, name)
  return nil unless node.is_a?(Psych::Nodes::Mapping)
  pair = node.children.each_slice(2).find { |key, _| key.value == name }
  pair && pair[1]
end
paths = []
collections = field(root, 'collections')
if collections.is_a?(Psych::Nodes::Mapping)
  collections.children.each_slice(2) do |name, collection|
    path = field(collection, 'path')
    next unless path.is_a?(Psych::Nodes::Scalar)
    paths << {name: name.value, line: path.start_line, column: path.start_column,
              end_line: path.end_line, end_column: path.end_column, style: path.style}
  end
end
puts JSON.generate({config: YAML.safe_load(text, permitted_classes: [], aliases: false), paths: paths})
'''


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
    forbidden = [repo / 'memory' / name for name in ('quarantine', 'core')]
    forbidden += [path.resolve() for path in forbidden]
    paths = {name: repo / relative for name, (relative, _) in COLLECTIONS.items()}
    for path in paths.values():
        if unsafe_path(path, forbidden):
            raise ValueError('refusing collection root: overlaps memory/quarantine or memory/core')
        if not path.is_dir():
            raise ValueError('missing memory collection directory; initialize the memory repository first')
    return repo, paths, forbidden


def unsafe_path(path, forbidden):
    path = Path(path)
    if not path.is_absolute():
        raise ValueError('rendered collection paths must be absolute')
    for candidate in (path, path.resolve()):
        if any(part == 'memory' and candidate.parts[index + 1] in ('quarantine', 'core')
               for index, part in enumerate(candidate.parts[:-1])):
            return True
        for root in forbidden:
            if candidate == root or root in candidate.parents or candidate in root.parents:
                return True
    return False


def parse_yaml(text):
    result = subprocess.run(['ruby', '-e', YAML_READER], input=text,
                            capture_output=True, text=True, check=False)
    if result.returncode:
        # Do not echo private YAML lines from a parser diagnostic.
        raise ValueError('invalid YAML (one document, unique scalar keys, no aliases/custom types required)')
    return json.loads(result.stdout)


def no_update_keys(value):
    if isinstance(value, dict):
        if 'update' in value:
            raise ValueError('config must not contain any update: key')
        for child in value.values():
            no_update_keys(child)
    elif isinstance(value, list):
        for child in value:
            no_update_keys(child)


def validate_config(data, expected, forbidden, canonical=False):
    no_update_keys(data)
    if not isinstance(data, dict) or not isinstance(data.get('collections'), dict):
        raise ValueError('config must contain a collections mapping')
    collections = data['collections']
    if set(collections) != set(COLLECTIONS):
        raise ValueError('config must contain exactly wiki, decisions, sources and bank')
    for name, path in expected.items():
        collection = collections[name]
        if not isinstance(collection, dict) or collection.get('pattern') != MASK:
            raise ValueError('each collection must use the literal **/*.md pattern')
        wanted = '$MEMORY_REPO/' + COLLECTIONS[name][0] if canonical else str(path)
        if collection.get('path') != wanted:
            raise ValueError('collection root is not one of the four approved roots')
        if unsafe_path(path, forbidden) or path.resolve() != path:
            raise ValueError('collection root resolves outside its approved memory directory')
    models = data.get('models')
    if not isinstance(models, dict) or any(not isinstance(models.get(key), str) or not models[key]
                                           for key in MODELS):
        raise ValueError('config requires explicit embed, rerank and generate model pins')


def proposed_config():
    lines = ['# Proposed qmd config: review and commit this file yourself.', 'collections:']
    for name, (relative, label) in COLLECTIONS.items():
        lines += [f'  {name}:', f'    path: "$MEMORY_REPO/{relative}"',
                  f'    pattern: "{MASK}"', '    context:', f'      "": {json.dumps(label)}']
    lines += ['models:'] + [f'  {key}: {json.dumps(value)}' for key, value in MODELS.items()]
    return '\n'.join(lines) + '\n'


def render_config(text, spans, expected):
    lines = text.splitlines(keepends=True)
    edits = []
    for span in spans:
        if span['line'] != span['end_line'] or span['style'] not in (1, 2, 3):
            raise ValueError('collection paths must be single-line plain or quoted scalars')
        start = sum(len(line) for line in lines[:span['line']]) + span['column']
        end = sum(len(line) for line in lines[:span['end_line']]) + span['end_column']
        path = str(expected[span['name']])
        replacement = "'" + path.replace("'", "''") + "'" if span['style'] == 2 else json.dumps(path, ensure_ascii=False)
        edits.append((start, end, replacement))
    if len(edits) != len(COLLECTIONS):
        raise ValueError('config must have four explicit collection path scalars')
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return HEADER + text


def read_index(database):
    if not database.is_file():
        raise ValueError('named index does not exist')
    wal = Path(str(database) + '-wal')
    if wal.exists() and wal.stat().st_size:
        raise ValueError('index has an active WAL; finish the qmd refresh and retry')
    # Immutable reads cannot create journal/SHM sidecars or migrate qmd's store.
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


def rebuild_guard(repo, database):
    processes = subprocess.run(['pgrep', '-f', r'(^|/)(qmd|qmd[.]js|qmd[.]ts)([[:space:]]|$)'],
                               capture_output=True, text=True, check=False)
    if processes.returncode == 0:
        raise ValueError('refusing --rebuild: a qmd process is running; stop it and retry')
    if processes.returncode != 1:
        raise ValueError('refusing --rebuild: could not check running qmd processes')
    common = Path(command('git', '-C', repo, 'rev-parse', '--git-common-dir', capture=True).strip())
    common = common if common.is_absolute() else repo / common
    lock = common / 'memory-mcp-writer.lock'
    if lock.exists() or lock.is_symlink():
        raise ValueError('refusing --rebuild: memory-mcp writer lock is held; finish the writer and retry')
    wal = Path(str(database) + '-wal')
    if wal.exists() and wal.stat().st_size:
        raise ValueError('refusing --rebuild: index has an active WAL; finish the qmd refresh and retry')
    for path in (database, wal, Path(str(database) + '-shm')):
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError('refusing --rebuild: named index/sidecar is not a regular file')


def install_launcher(binary):
    local = Path.home() / '.local/bin/qmd'
    if local == binary:
        return
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
    modes.add_argument('--check', action='store_true', help='read-only config, version, paths and embed-age doctor')
    modes.add_argument('--no-embed', action='store_true', help='install/configure/update, but skip embedding')
    modes.add_argument('--rebuild', action='store_true', help='discard only this index/sidecars, then update and embed')
    args = parser.parse_args()
    repo, expected, forbidden = memory_paths()
    canonical = repo / 'qmd/dailydriver.yml'
    if canonical.is_symlink() or canonical.parent.is_symlink():
        raise ValueError('canonical qmd config/directory must not be a symlink')
    for variable in ('INDEX_PATH', 'QMD_CONFIG_DIR', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME',
                     'QMD_EMBED_MODEL', 'QMD_RERANK_MODEL', 'QMD_GENERATE_MODEL'):
        if os.environ.get(variable):
            raise ValueError(f'unset {variable} to use the canonical dailydriver config and cache')
    exists = canonical.exists()
    if args.check and not exists:
        raise ValueError('canonical qmd config is missing (run the installer to propose it)')
    text = canonical.read_bytes().decode('utf-8') if exists else proposed_config()
    parsed = parse_yaml(text)
    validate_config(parsed['config'], expected, forbidden, canonical=True)
    rendered = render_config(text, parsed['paths'], expected)
    validate_config(parse_yaml(rendered)['config'], expected, forbidden)
    home = Path.home().resolve()
    config = home / '.config/qmd/dailydriver.yml'
    if config.resolve() != config:
        raise ValueError('installed qmd config/directory must not be a symlink')
    database = home / '.cache/qmd/dailydriver.sqlite'
    if args.rebuild:
        rebuild_guard(repo, database)
    # Config validation precedes npm/brew installation and all writes.
    if not exists:
        canonical.parent.mkdir(parents=True, exist_ok=True)
        with canonical.open('x', encoding='utf-8') as proposal:
            proposal.write(text)
        print('Review and commit it yourself: cd $MEMORY_REPO && git add qmd/ && git commit -m "qmd: index config"')
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
    if args.check:
        if not config.exists():
            errors.append('installed config is missing')
        elif config.read_bytes() != rendered.encode('utf-8'):
            errors.append('installed config differs from the rendered canonical config')
        age = 'unknown'
        try:
            collections, last_embed = read_index(database)
            validate_config({'collections': collections, 'models': parsed['config']['models']}, expected, forbidden)
            age = embed_age(last_embed)
        except (ValueError, sqlite3.Error) as error:
            errors.append(str(error))
        for error in errors:
            print('ERROR: ' + error, file=sys.stderr)
        print(f'qmd: check {"FAILED" if errors else "OK"} (pin={args.version}; index={INDEX}; last embed age={age})')
        return 1 if errors else 0
    if errors:
        raise ValueError('; '.join(errors))
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists() or config.read_bytes() != rendered.encode('utf-8'):
        config.write_bytes(rendered.encode('utf-8'))
    install_launcher(binary)
    if args.rebuild:
        # Recheck after installation, immediately before the narrowly scoped deletion.
        rebuild_guard(repo, database)
        for path in (database, Path(str(database) + '-wal'), Path(str(database) + '-shm')):
            if path.exists():
                path.unlink()
    qmd = (binary, '--index', INDEX)
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
