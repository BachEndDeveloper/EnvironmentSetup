# ADR: reproducible local search with qmd

**Status:** accepted (DEC-0018). The installer is separate from full machine setup.

## Context and decision

[qmd](https://github.com/tobi/qmd) is an on-device Markdown search engine combining
keyword search, embeddings and optional query expansion/reranking. It ranks
candidates behind memory-mcp; memory-mcp retains provenance, wiki-first ordering,
exclusions and BM25 fallback. See **memory-mcp `docs/features/qmd-hybrid-search.md`**
([sibling checkout](../../memory-mcp/docs/features/qmd-hybrid-search.md)) for the
retrieval design. Do not register qmd's own MCP server or skills with agent hosts.

Keep installation reproducible, but keep topic-specific configuration in the
**private DailyDriver data repository**, never this public repository. The
canonical config is `$MEMORY_REPO/qmd/dailydriver.yml`; **Martin reviews and commits
it himself under DailyDriver's existing guards**. The installer never stages,
commits, pushes, changes remotes or weakens those guards.

## What is installed and pinned

- npm-global **`@tobilu/qmd@2.8.3`**; `QMD_VERSION` in
  `scripts/install-qmd.sh` is the sole installer version variable.
- Homebrew `sqlite`, installed if missing (Homebrew manages its version).
- Explicit upstream v2.8.3 default model URIs in a newly proposed config:
  - `embed`: `hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf`
  - `rerank`: `hf:ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/qwen3-reranker-0.6b-q8_0.gguf`
  - `generate`: `hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf`

Requirements: Node **>=22**, npm, Homebrew, Python 3, macOS Ruby with its
standard-library YAML parser, and Git/pgrep for rebuild safety checks. Ruby's safe
loader allows validation **before** npm/brew installation without adding a parser
package. The npm distribution runs built JavaScript on Node; **Bun is not
required**. Upstream also supports Bun >=1.0 as an alternative runtime.

## Configuration and artifacts

| Artifact | Location | Git / owner |
| --- | --- | --- |
| Canonical config (collections, contexts, model pins) | `$MEMORY_REPO/qmd/dailydriver.yml` | Private DailyDriver only; Martin reviews/commits |
| Rendered host config | `~/.config/qmd/dailydriver.yml` | Generated; never commit or edit directly |
| Named SQLite index and sidecars | `~/.cache/qmd/dailydriver.sqlite{,-wal,-shm}` | Disposable; never copy or commit |
| Downloaded GGUF models | `~/.cache/qmd/models/` | Re-downloadable cache; never copy or commit |

The canonical roots are exactly `$MEMORY_REPO/memory/wiki`,
`$MEMORY_REPO/memory/archive/decisions`, `$MEMORY_REPO/memory/archive/sources`, and
`$MEMORY_REPO/memory/bank`, under collection names `wiki`, `decisions`, `sources`,
`bank`. Each uses `pattern: '**/*.md'`. These literal path tokens are portable:
Martin does not edit machine paths when cloning onto another computer.

The installer validates the canonical YAML first, renders **only the four path
scalars** to absolute roots in the installed copy, then validates the rendered
roots again. All other config bytes (including contexts/comments) are preserved.
The installed file has the header `generated from $MEMORY_REPO/qmd/dailydriver.yml,
do not edit`. Quarantine, core, other roots, extra/missing collections, non-Markdown
masks and **any `update:` key** are refused. Duplicate keys, aliases/custom YAML
types and multiline path scalars are refused rather than interpreted ambiguously.
The explicit `models:` block must specify embedding, reranking and generation.
Conflicting qmd index/config/cache/model environment overrides are refused.

If canonical config exists, it is authoritative: there are **no ad hoc collection
or context mutations**. If absent, the installer writes a safe default proposal
there **uncommitted**, with the four generic contexts and explicit model pins,
uses its validated rendered copy, and prints:

```text
Review and commit it yourself: cd $MEMORY_REPO && git add qmd/ && git commit -m "qmd: index config"
```

No Git mutation is performed. Review local exclusions/secret checks and the
private-remote policy before committing. Do not copy private contexts into this
public repository. Normal installs may repair the host copy, never rewrite an
existing canonical file or write memory content.

## New machine, install and rebuild

1. Install the requirements and clone the private DailyDriver repository using
   the approved private remote. The four memory collection directories must exist.
2. Set `MEMORY_REPO` or the `memoryRepo` key in
   `~/.config/memory-mcp/config.json`; otherwise the installer uses
   `$HOME/source/DailyDriver` (environment wins over settings).
3. From this checkout, run the standalone installer. It also works when invoked
   by an absolute script path from a different working directory:

```sh
bash scripts/install-qmd.sh              # validate/copy config, install, update, embed
bash scripts/install-qmd.sh --no-embed   # same, but defer embeddings/model use
bash scripts/install-qmd.sh --rebuild    # fresh named index from canonical config
bash scripts/install-qmd.sh --check      # read-only doctor; never propose or repair
```

Full macOS setup also calls this installer after MCP/AI-Skills and before the
daily scheduler. No full machine setup is required to install/rebuild qmd.

**Topology changes require a rebuild.** Topology means collection names, root
paths, masks and ignore globs. With an existing index, the installer compares the
installed YAML's topology with the rendered canonical config before normal
installation/update. Different or unknown topology is refused with `--rebuild`
instructions: qmd keeps orphan document/content rows when collections or paths
are removed from its config. Removing any previously indexed collection or path
**ALWAYS requires `--rebuild`**, even when the new canonical config excludes it.
Context labels/comments alone are metadata and do not require a rebuild. No
existing index means a normal fresh build is allowed.

**Go-live installation requires `--rebuild`:** the benchmark index was built
against a lane-worktree root and extra ignore globs, not the final canonical
checkout topology. Do not reuse that index with an ordinary incremental update.

`--rebuild` refuses a running qmd process, an active nonempty WAL or a held
`memory-mcp-writer.lock` in Git's common directory. Stop concurrent search/index
users and finish the memory writer before retrying; do not delete their locks.
It deletes **only** `dailydriver.sqlite` and its `-wal`/`-shm` sidecars, then runs
`qmd --index dailydriver update` and `qmd --index dailydriver embed`. It retains all
models and other named indexes. A failed rebuild can leave qmd unavailable until
retried; memory-mcp's BM25 fallback remains the retrieval fallback.

**Rebuild time:** Measured 2026-10-15 on an Apple M4 Pro (24 GB): **~1 min 16 s** for ~740 documents / ~2,300 chunks (update + embed, models already cached). First run additionally downloads ~2 GB of models.

**Measured full rebuild / hardware:** Apple M4 Pro, 24 GB, macOS: `install-qmd.sh --rebuild` took 1 min 16 s wall time on 2026-10-15 (742 documents, 2,285 chunks, models cached). Cold installs additionally depend on model
network downloads; budget roughly 2 GB for the full model set. `embed` only needs
the embedding model. Models download automatically on first use, never from Git;
search queries/content remain local.

## Check, GUI discovery and upgrade

`--check` validates canonical config, compares the complete rendered host copy,
checks the npm package/CLI version, and prints `topology: matches` or
`topology: differs (rebuild required)`. Topology is read from the installed YAML,
not SQLite's internal collection schema; only embed age is read from SQLite.
Labels-only copy drift still needs an ordinary installer run, not a rebuild.
The doctor also prints latest embedded-chunk age (or `never`). This is not a last-run ledger: a no-op
incremental embed need not update any chunk timestamp. No arbitrary age threshold
is applied. The doctor reads SQLite immutably and refuses an active WAL rather
than creating sidecars or reading a stale checkpoint. It performs no installation,
config repair, Git mutation, update or embed; errors return nonzero.

`mcp-node` adds `~/.local/bin` and the selected nvm Node bin to child PATH for GUI
hosts. The installer maintains a local qmd launcher with resolved absolute
Node/npm-tool paths (unless npm already owns that exact path). No default
`MEMORY_QMD_BIN` entry is needed in `MCP/servers.json`. Deploy the updated
`mcp-node` through the MCP installer; re-run qmd installation after moving/removing
Node or the npm prefix. Unrelated regular launcher files are not overwritten.

To upgrade, review upstream requirements/schema/model changes, change the sole
`QMD_VERSION` variable, update tests/docs, and run the sandbox/static gates.
Existing canonical model pins are **not** silently upgraded: Martin reviews any
model/config changes in DailyDriver separately. Re-run install and `--check`;
use `--rebuild` for a fresh index and re-run the retrieval benchmark before go-live.
Do not back up or migrate SQLite/GGUF files in place of this procedure.

```sh
python3 scripts/test-qmd-install.py
```

This gate uses temporary HOME, real Ruby YAML/Node and mocked npm/qmd/brew/git/
pgrep. No live installation, model download, Git mutation or launchd job occurs.
