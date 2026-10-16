# MCP server provisioning

`servers.json` is the declarative inventory: **six servers**, with released Git deployments,
remote URL references, and machine-local registrations. Adding a server is a data change,
not a new installer branch. `install-mcp-servers.sh` deploys/builds managed servers and registers
them; `check-machine-local.py` checks the manual prerequisites without probing servers or printing
configuration values. `mcp-node` is installed to `~/.local/bin/mcp-node` for local Node servers.

## Hosts and Pi's adapter

| Host | Registration mechanism |
| --- | --- |
| Claude Desktop | Surgical merge of `mcpServers` in `~/Library/Application Support/Claude/claude_desktop_config.json`, backup first; remote connectors are manual |
| Claude Code | `claude mcp add-json <name> <json> --scope user`; never hand-edit `~/.claude.json` |
| Pi | `pi mcp add <name> -- <command> <args>` (or `--url`), writing `~/.pi/agent/mcp.json` |

**Pi uses `npm:pi-mcp-adapter`, with `-builtin:mcp` in `extensions`.** The setup restores both
settings; it does not remove the adapter. Verified against installed adapter **5.3.0** and Pi
**1.2.0**: `config.ts` discovers `~/.config/mcp/mcp.json` and, on Pi 0.99+ (MCP API present),
`~/.pi/agent/mcp.json`. `index.ts` enables that discovery based on Pi's MCP API, independently of
whether the built-in extension is enabled. The native CLI still writes `mcp.json`; disabling the
built-in runtime does not disable its registration command. Adapter overrides can also live in
`~/.pi/agent/mcp-adapter.json`, and project/`.agents` configs may override global entries.

The installer keeps **m365 and memory in the proven `~/.pi/agent/mcp.json` path**. It does not
move them to the adapter override file, migrate the four local references, or rewrite their OAuth
and restriction fields. Keep each name unique across discovered registries; an override can
shadow a managed entry. Older adapters/Pi versions with different discovery are not supported by
this model: update them before using it. Use the adapter's interactive `/mcp` view to verify the
actual runtime; `pi mcp list` is the native CLI's health view, not proof of adapter health.

## Pi protocol negotiation (SDK v2 servers)

`piProtocolVersion` in a managed server's `servers.json` entry controls only
Pi's adapter, not Claude Desktop or Code:

| Value | Behaviour |
| --- | --- |
| `auto` | Probe for MCP 2026-07-28 and fall back to the legacy handshake |
| `2026-07-28` | Pin the new revision; no legacy fallback |
| `legacy` | Use the 2025-era handshake (rollback) |
| omitted | Native CLI default; no adapter protocol override |

The manifest selects `auto` for **memory-mcp v0.9.0+** and **m365-mcp v0.7.0+**.
Both releases serve modern and legacy clients. The setting was verified with
Pi **1.3.0** and pi-mcp-adapter **5.3.1**; upgrade older installations first.
Use `legacy` when holding a machine on an older release if probe latency is unwanted.

`pi mcp add` cannot express this adapter extension. After successful CLI
registration, `set-pi-protocol.py` atomically adds just `protocolVersion` to that
entry in `~/.pi/agent/mcp.json`, preserving other fields and file permissions.
Missing/malformed registries or entries fail closed without printing their contents.
Invalid manifest values are rejected before deployment/registration; machine-local
entries cannot opt into managed protocol changes. Re-running setup re-applies the
policy rather than silently resetting it. This does not migrate any registry.

After installation, restart Pi and inspect `/mcp`. `pi mcp list` is a separate
CLI health check. Actual approval-dialog acceptance must be checked interactively
on throwaway data; sandbox tests cannot prove the host rendered the dialog.
Removing `protocolVersion` locally is a temporary rollback; set `piProtocolVersion`
to `legacy` in the manifest for a rollback that survives reinstallation.

Validation (temporary HOME, no real server/auth/write):

```sh
python3 scripts/test-pi-protocol.py
python3 scripts/test-mcp-node.py
python3 scripts/test-deployment.py /path/to/AI-Skills
bash -n MCP/install-mcp-servers.sh MCP/mcp-node
shellcheck MCP/install-mcp-servers.sh MCP/mcp-node
git diff --check
```

## Inventory and manual prerequisites

| Name | Model | Hosts | Machine-local registration / prerequisite |
| --- | --- | --- | --- |
| `m365-personal-productivity` | Released Git deployment | Desktop, Code, Pi | `~/.local/share/mcp/m365-mcp`; interactive sign-in |
| `memory` | Released Git deployment | Pi, Desktop | `~/.local/share/mcp/memory-mcp`; private data repo and write policy |
| `confluent` | Machine-local stdio reference | Pi | Entry in `$HOME/.pi/agent/mcp.json`; npm installation and private YAML config |
| `atlassian` | Machine-local remote reference | Pi | Entry in `$HOME/.pi/agent/mcp.json`; local URL and interactive OAuth |
| `datadog` | Machine-local adapter remote reference | Pi | Entry in `$HOME/.config/mcp/mcp.json`; local URL and OAuth |
| `atlassian-rovo` | Machine-local adapter remote reference | Pi | Entry in `$HOME/.config/mcp/mcp.json`; local URL, OAuth and reviewed `excludeTools` |

These four references deliberately contain **no URL, credential or org configuration values**.
Their existing registrations are retained byte-for-byte. On a new machine:

1. Install an approved/pinned `@confluentinc/mcp-confluent` release into
   `$HOME/.local/share/mcp-confluent` (the surveyed installation was 1.5.0). Create its private
   `$HOME/.local/share/mcp-confluent/config.yaml` locally using the upstream instructions. Register
   `confluent` with `mcp-node`, the package's `dist/index.js`, `--config` pointing at that YAML file,
   and a reviewed `--block-tools` list. Do not drop the existing mutation restrictions.
2. Register `atlassian` with its local remote URL in Pi's global `mcp.json`, then sign in using the
   adapter's interactive OAuth flow. Do not put that URL in this repository.
3. Create/restore the `datadog` and `atlassian-rovo` entries under `mcpServers` in the shared registry
   `$HOME/.config/mcp/mcp.json`, using the adapter/upstream instructions, then sign in interactively.
   Retain `auth`, lifecycle/timeouts and Rovo's reviewed `excludeTools`. The two Atlassian names
   are distinct existing registrations, not aliases to collapse without owner approval.
4. Run the read-only check below; inspect adapter health interactively afterwards. Config presence
   is **not** auth validity or proof that every mutation path is denied.

```sh
bash MCP/install-mcp-servers.sh --check-machine-local
# Nonzero if any referenced entry is missing/invalid; names and $HOME paths only.
```

The ordinary installer emits the same missing-entry warnings/manual steps and continues. It
never installs the Confluent npm package, supplies org values, signs in or resumes scheduled tasks.
A fresh machine is not a complete authenticated replica until these manual steps are done.

## Deployment rules

1. **Never hand-edit `~/.claude.json`.** It contains live project/session state. Use Claude's CLI.
   Desktop's configuration-only file is merged with a backup. `supersedes` removes older keys for
   managed servers in each selected host. Machine-local entries are not mutated.
2. **Never store a versioned Node path in host config.** `mcp-node` follows nvm's `default` alias,
   then the newest installed version, then `PATH`, avoiding stale `ENOENT` errors. It adds
   `~/.local/bin` and that Node's bin directory to child `PATH` so memory-mcp can find qmd even
   from GUI hosts. A server may set `MCP_NODE_MAJOR` to select the newest installed nvm patch
   of a supported Node major, failing closed if unavailable; M365 selects Node 24 to match
   its declared engine rather than inheriting a newer global default. The qmd installer supplies a stable local launcher for custom npm prefixes;
   no `MEMORY_QMD_BIN` manifest entry is required (see root README's **Local search (qmd)**).
3. **Never run a host from a development checkout.** `dir` is deployment-only, detached at a
   release, normally under `~/.local/share/mcp`. A branched checkout or non-Git directory is refused.
   Develop in `~/source/<repo>`, release, then re-run the installer. AI-Skills follows the same
   separate-release-copy model at `~/.local/share/ai-skills`; see [../RELEASES.md](../RELEASES.md).

New managed Git clones try SSH first. On SSH authentication failure (including
no loaded key), the shared `scripts/git-clone-with-https-fallback.sh` helper retries
the **same GitHub repository** over HTTPS, with local Git credential helpers and
no embedded credentials or terminal password prompts. Private repos still need
GitHub authorisation. Host-key verification, DNS/network and missing-repository
failures do not trigger fallback. Existing origins/fetch behaviour are unchanged.
Both-transport clone failure warns and skips that server; no release/build/host
registration proceeds for that new deployment.

The launcher sandbox checks major/patch selection, default/stale aliases,
argument and PATH preservation, and fail-closed errors without launching real
Node. Deployment tests assert that memory is registered in Desktop and Pi but
not Code, that its write/remote policy and private repo path are preserved, and
that M365 selects Node 24 on every configured host. These are configuration
checks, not proof of live Desktop connectivity or approval-dialog behaviour.

## Capability gates and machine-local settings

No secrets, tenant ids or internal URLs belong here. For an M365 tenant override, export
`M365_TENANT_ID` before running the installer; it is not committed or printed in fallback commands.
Auth tokens are never handled by this installer. Each managed server prints a `NEXT:` sign-in
step; m365's cache/signature live per user in `~/Library/Application Support/m365-mcp/`, shared
between development and deployment copies.

M365 gates default off: `ALLOW_SEND` enables sending/meeting-invite capabilities, `ALLOW_DELETE`
enables deletion/Deleted Items filing, and `ALLOW_RULES` enables mailbox-rule writes. Preview and
confirmation requirements still apply; capability availability is not permission for unattended
mailbox mutation. Fixed tool counts are omitted because they depend on the deployed release.

Set non-secret capability policy in `servers.json`, **with owner approval**, not by editing a host
entry: the installer constructs one env block for all selected hosts, replacing hand-added values.
`ALLOW_DELETE=false` is explicit; sending/rule gates remain default-off. This is not a per-host
policy mechanism.

Memory is registered in **Pi and Claude Desktop**. Its configured write gate
permits automatic attributed bank claims and authored archive decisions via `memory_record`.
Core writes still require staged preview and confirmation. Inbound is cited with its source, never
presented as the owner's view (repo contract §2a / INV-7). Private DailyDriver is provisioned by
full setup before MCP installation, never by this standalone installer. Missing `requires` paths
warn; the server itself refuses unsafe/missing data configuration.

## Adding a server: schema

The default `type` is `git` (existing entries need no migration):

```json
{
  "name": "my-server",
  "repo": "https://github.com/me/my-mcp.git",
  "ref": "latest",
  "dir": "$HOME/.local/share/mcp/my-mcp",
  "build": ["npm ci", "npm run build"],
  "entry": "dist/index.js",
  "postInstall": "npm run auth",
  "piPackage": false,
  "env": {}
}
```

`ref=latest` means the highest stable `vX.Y.Z`, resolved after fetching by
`scripts/resolve-release.sh`; an exact tag holds a deployment back. `piPackage=true` registers
server-shipped skills, such as `m365-tools`, from the deployment via `pi install <dir>`.

For a remote server requiring only a URL, use an **environment-variable reference**, not a URL
value. The installer supports this in Code and Pi; Desktop's connector setup is manual:

```json
{
  "name": "my-remote",
  "type": "remote",
  "url": "$MY_MCP_URL",
  "hosts": ["pi", "claude-code"]
}
```

Export the URL locally before installing. Unset references and literal URLs are refused without
printing values. Auth and additional restrictions remain manual; if the entry needs OAuth fields,
headers, lifecycle settings or tool restrictions, use a machine-local reference instead so they
are not overwritten:

```json
{
  "name": "my-local-registration",
  "type": "machine-local",
  "transport": "remote",
  "hosts": ["pi"],
  "configFile": "$HOME/.config/mcp/mcp.json",
  "manualSetup": "Create the remote entry and complete interactive authentication locally."
}
```

`transport` is `remote` (requires `url`) or `stdio` (requires `command`); the entry's key must equal
`name`. `configFile` must be `$HOME`-relative and point at an adapter-discovered registry; the
installer only checks presence/shape. Never commit the file's values. These entries are Pi-only.

Common Git/remote fields: `hosts` selects `claude-desktop`, `claude-code`, `pi` (default all),
`supersedes` lists older keys, and `requires` lists external prerequisite paths. Omitted hosts are
not unregistered. Git `env` and paths expand environment references before registration because
GUI hosts do not expand them. Remote entries do not support `env` or `piPackage`.

## Behaviour and validation

- Re-runs converge: Desktop skips unchanged registrations; Code/Pi are re-registered identically;
  machine-local configs are only read. Git fetch/build work can still occur.
- Clone/release/build/registration failures warn and continue, so one server does not abort full
  setup. Registration failure does not establish host health; check the warnings. This is not a
  transactional installer: an existing host entry may survive a failed rebuild.
- Provisioning is skipped when Node is absent; `--check-machine-local` needs only Python and is
  read-only, even with Node absent.

```sh
python3 scripts/test-deployment.py /path/to/AI-Skills  # temp HOME, mocked external commands
claude mcp list                                     # Code's health view (run only after approval)
# In interactive Pi: /mcp                            # adapter runtime health and OAuth
cd ~/.local/share/mcp/m365-mcp && npm run doctor
# Current deployment (not development checkout):
git -C ~/.local/share/mcp/memory-mcp describe --tags --exact-match HEAD
```

Live setup/auth/health checks require operator approval; sandbox tests do not attest live auth.
