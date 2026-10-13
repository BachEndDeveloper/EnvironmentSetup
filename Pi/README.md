# Pi coding-agent configuration

Backup of the non-secret [Pi](https://pi.dev) configuration restored on a new machine. Personal and shared skills are **not** stored here: they are versioned in the private [AI-Skills](https://github.com/BachEndDeveloper/AI-Skills) repository and installed by the main setup script.

## Files

- `settings.json` — global Pi preferences, provider/model defaults, Pi package list, and the upstream dotnet- and Aspire-skills paths. It contains no secrets.
- `models.json` — custom Azure AI Foundry provider/model catalog. It contains no API keys; the Foundry hostname is templated as `YOUR-FOUNDRY-RESOURCE`.
- `extensions/supacode/index.ts` — Supacode↔Pi integration extension retained as a fallback. Supacode itself is installed through the Homebrew cask in the root `Brewfile`.

## What the macOS setup script restores

1. It backs up existing `~/.pi/agent/settings.json` and `models.json`.
2. It copies this directory's `settings.json`, `models.json`, and local extensions into `~/.pi/agent/`.
3. After restoring settings, it deploys AI-Skills to `~/.local/share/ai-skills` at its newest stable release tag, registers that copy as a Pi package and removes the old `../../source/AI-Skills` entry via Pi's CLI. That deployment is the sole source for repository-managed skills; the development checkout stays untouched.
4. It clones the upstream dotnet and Aspire skills repositories into `~/pi-skills/`, because this configuration references both paths.
5. It provisions the managed MCP deployments in [`../MCP/servers.json`](../MCP/servers.json), registers them through `pi mcp add` in `~/.pi/agent/mcp.json`, and checks four additional machine-local registrations. Pi uses **pi-mcp-adapter**, declared in `settings.json`, with `-builtin:mcp` disabling the built-in runtime. The adapter reads that registry and `~/.config/mcp/mcp.json`; Code/Desktop registration follows each server's host list. No machine-local OAuth/restriction values are rewritten.

No skill directory is copied from this repository into `~/.agents/skills` or `~/.pi/agent/skills`.

## After setup

1. Run `pi` and complete `/login` for each provider. `auth.json` is intentionally never committed.
2. Replace `YOUR-FOUNDRY-RESOURCE` in `~/.pi/agent/models.json` if Azure AI Foundry is required.
3. **Sign in to each MCP server that needs it.** This is the same class of one-time interactive step as `/login` above — the setup script provisions the servers but deliberately stores no tokens. For the m365 server:

   ```sh
   cd ~/.local/share/mcp/m365-mcp
   npm run auth     # browser sign-in; then offers to request admin consent
   npm run doctor   # confirm before relying on it
   ```

   `npm run auth` performs the normal sign-in and then **asks whether to submit an admin-consent request** for scopes the tenant has not granted, which opens a second browser window. That second window will not return a token — that is the expected outcome, since the point is Entra's approval screen. Use `npm run auth -- --skip-pending` to never be asked, which is what an unattended run wants.

   That directory is the deployment copy the hosts run, not a development checkout; the token it creates is stored per user, so it also covers any working copy you develop in. Use `/mcp` inside Pi to confirm the adapter connected; `pi mcp list` is the native CLI's view. See [../MCP/README.md](../MCP/README.md).
4. Pi installs declared packages automatically on first launch; use `pi update --extensions` to force reconciliation.
5. Develop skills only in the AI-Skills development repository, release, then run EnvironmentSetup's `scripts/install-ai-skills.sh` to advance the deployment and both hosts. `AI_SKILLS_REF=latest` follows stable releases; export an exact tag to hold back. Reload/restart hosts.
6. Complete the machine-local Confluent/remote setup and interactive OAuth described in [../MCP/README.md](../MCP/README.md); `bash MCP/install-mcp-servers.sh --check-machine-local` reports missing references without printing values.
7. Scheduling is not configured by this setup. The old Cowork tasks remain paused; any replacement needs separate owner approval, released skills, memory/m365, bounded writes and failure visibility.

## Security

No tokens, API keys, browser credentials, or internal documents belong in this repository. Keep the AI-Skills repository private and review every skill change before tagging a release.
