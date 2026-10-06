# MCP server provisioning

Declares the [MCP](https://modelcontextprotocol.io/) servers this machine runs, and installs them.

- **`servers.json`** — the declarative list. Adding a second or third server is a **data change
  here**, not a code change in the installer.
- **`install-mcp-servers.sh`** — clones each server at its pinned ref, builds it, and registers it
  with the MCP hosts. Called by `01 - Setup Mac Environment.sh`; safe to run on its own.

## How the three hosts are wired

Only **two** hosts need registering, because Pi imports from them:

| Host | How it learns about a server |
| --- | --- |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` — merged by this installer |
| Claude Code | `claude mcp add-json <name> <json> --scope user` — its **own CLI**, never hand-edited |
| Pi | nothing to do: `~/.pi/agent/mcp.json` is `{"imports": ["claude-code", "claude-desktop"]}` |

The installer verifies that last point and warns if the imports are missing, since Pi would then
silently see no servers.

## Two rules this installer exists to enforce

**1. Never hand-edit `~/.claude.json`.** That file is ~73 KB and holds Claude Code's live project
and session state, not just configuration. A whole-file write would destroy it. All Claude Code
mutation goes through `claude mcp add-json --scope user`, and existing servers are left alone
rather than overwritten. Claude Desktop's config *is* edited directly — it is small and
configuration-only — but only the `mcpServers` key is touched and a `.backup` is written first.

**2. Never hardcode an interpreter path in this repository.** Both host configs previously
contained `/Users/<name>/.nvm/versions/node/v24.16.0/bin/node`, which breaks on another machine and
after every Node upgrade.

The subtlety: the generated host config genuinely **needs** an absolute path, because GUI hosts such
as Claude Desktop launch with a minimal `PATH` and cannot find an nvm-managed `node`. So the
installer resolves `command -v node` **at install time** and writes that. The repository stays
generic; the generated config is machine-specific and regenerated on every run.

> **After `nvm install --lts`, re-run this installer** so the recorded interpreter points at the new
> Node. Otherwise the hosts keep launching a version you may later remove.

## Secrets and org-specific values

Nothing secret is stored here. `servers.json` carries an empty `env` block on purpose: the m365
server ships a `config.defaults.json` with a non-secret tenant id, so a fresh clone runs with no host
`env` block at all.

To override the tenant on a given machine, export it before running setup — it is read from the
environment and never committed:

```sh
M365_TENANT_ID=<your-tenant-id> bash "01 - Setup Mac Environment.sh"
```

Auth tokens are never handled here. Each server's own sign-in step is printed as a `NEXT:` line at
the end of its install (for m365: `npm run auth`), and the resulting token cache stays in the
server's own checkout.

## Adding another server

Append to `servers.json`:

```json
{
  "name": "my-server",
  "repo": "https://github.com/me/my-mcp.git",
  "ref": "v1.2.0",
  "dir": "$HOME/source/my-mcp",
  "build": ["npm ci", "npm run build"],
  "entry": "dist/index.js",
  "postInstall": "npm run auth",
  "piPackage": false,
  "env": {}
}
```

`dir` is expanded with `$HOME`, `ref` is checked out detached (pin a tag, not a branch), and `entry`
is relative to the checkout. Re-run `bash MCP/install-mcp-servers.sh`.

Set `"piPackage": true` when the server ships agent skills (a `pi` manifest in its `package.json`):
the installer then runs `pi install <dir>` so Pi loads them, exactly as the setup script does for
AI-Skills. m365-mcp uses this for its `m365-tools` skill. Claude hosts have no package mechanism; the
`m365-martin` skill in AI-Skills tells them where to read `m365-tools` instead.

**Upgrading a server** is a data change: bump `ref` here and re-run the installer. A machine whose
checkout already exists fetches tags and moves to the new ref.

## Behaviour

- **Idempotent.** A second run reports `already up to date` / `already registered` and changes
  nothing.
- **Non-fatal.** Every failure — clone, checkout, build, missing `claude` CLI — prints a `WARNING`
  and moves on, so one broken server cannot cost you the rest of the machine setup. The one hard
  stop is a target directory that exists but is not a git checkout, which is a genuinely ambiguous
  state.
- **Skipped entirely** when `node` is not on `PATH`.

## Verifying

```sh
claude mcp list                                   # Claude Code's view, with health checks
cd ~/source/m365-personal-productivity-mcp && npm run doctor   # the m365 server's own diagnosis
```
