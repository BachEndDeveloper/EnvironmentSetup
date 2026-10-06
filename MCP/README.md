# MCP server provisioning

Declares the [MCP](https://modelcontextprotocol.io/) servers this machine runs, and installs them.

- **`servers.json`** — the declarative list. Adding a second or third server is a **data change
  here**, not a code change in the installer.
- **`install-mcp-servers.sh`** — keeps a deployment copy of each server at its pinned ref, builds
  it, and registers it with the MCP hosts.
- **`mcp-node`** — the launcher every host is pointed at. Installed to `~/.local/bin/mcp-node`. Called by `01 - Setup Mac Environment.sh`; safe to run on its own.

## How the three hosts are wired

All three hosts are registered, each through the mechanism it owns:

| Host | How it learns about a server |
| --- | --- |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` — merged by this installer |
| Claude Code | `claude mcp add-json <name> <json> --scope user` — its **own CLI**, never hand-edited |
| Pi | `pi mcp add <name> -- <command> <args>` — its **own CLI**, writing `~/.pi/agent/mcp.json` |

Pi uses its **built-in** MCP support. An earlier version of this setup relied on the
`pi-mcp-adapter` package, which let Pi import servers from the two Claude hosts. That package
replaces the built-in support while installed, and the built-in `mcp.json` has no import mechanism,
so it is no longer used: the installer registers Pi directly and warns if the adapter is still
installed.

Older host keys for a server can be listed in `supersedes`; the installer removes them from every
host so a machine never ends up with the same server registered twice.

## Three rules this installer exists to enforce

**1. Never hand-edit `~/.claude.json`.** That file is ~73 KB and holds Claude Code's live project
and session state, not just configuration. A whole-file write would destroy it. All Claude Code
mutation goes through `claude mcp`, and Pi through `pi mcp`. Existing entries are re-registered on
every run, so a changed path or launcher actually lands — leaving them "as-is" is how a stale entry
pointing at a removed Node survived before. Claude Desktop's config *is* edited directly — it is small and
configuration-only — but only the `mcpServers` key is touched and a `.backup` is written first.

**2. Never write a versioned Node path into a host config.** GUI hosts such as Claude Desktop
launch with a minimal `PATH`, so a host config needs an absolute command. But an nvm path such as
`~/.nvm/versions/node/v24.16.0/bin/node` breaks the moment that version is removed — the host then
fails with `ENOENT`, which is exactly what happened to the Claude Code entry on the development
machine. Every host is therefore pointed at **`~/.local/bin/mcp-node`**, a small launcher that
follows nvm's `default` alias (falling back to the newest installed version, then `PATH`). Upgrading
Node no longer requires re-running anything.

**3. Never run a host from a development checkout.** `dir` is a **deployment-only** copy, by default
under `~/.local/share/mcp/`. The installer moves it between tags and rebuilds it; hosts run its
`dist/`. If `dir` were the checkout you develop in, every setup run would detach it from its branch,
and every `npm run build` you ran mid-change would be live in every host. The installer refuses a
checkout that is on a branch, for that reason.

Develop in `~/source/<repo>` as usual. To ship: tag a release there, bump `ref` in `servers.json`,
re-run the installer.

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
the end of its install (for m365: `npm run auth`). The resulting token cache is stored **per user**,
not in any checkout — for m365, `~/Library/Application Support/m365-mcp/` — so the deployment copy
and a development checkout share one sign-in. The m365 email signature lives there too.

## Adding another server

Append to `servers.json`:

```json
{
  "name": "my-server",
  "repo": "https://github.com/me/my-mcp.git",
  "ref": "v1.2.0",
  "dir": "$HOME/.local/share/mcp/my-mcp",
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

- **Idempotent.** A second run changes nothing on disk: Claude Desktop reports `already up to date`,
  and Claude Code and Pi are re-registered with the same entry.
- **Non-fatal.** Every failure — clone, checkout, build, missing `claude` CLI — prints a `WARNING`
  and moves on, so one broken server cannot cost you the rest of the machine setup. A server is
  skipped when its `dir` exists but is not a git checkout, or is a checkout on a branch — both mean
  the directory is not one this installer owns.
- **Skipped entirely** when `node` is not on `PATH`.

## Verifying

```sh
claude mcp list                                   # Claude Code's view, with health checks
cd ~/.local/share/mcp/m365-mcp && npm run doctor   # the m365 server's own diagnosis
pi mcp list                                         # Pi: state and tool count per server
```
