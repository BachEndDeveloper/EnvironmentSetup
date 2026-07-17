# Pi coding agent customizations

Backup of my [Pi](https://pi.dev) agent (`~/.pi/agent`) config so settings, packages, custom
providers/models and local resources can be restored after a reinstall.

## Files

- `settings.json` — my global Pi config: theme, default provider/model
  (`foundry-claude` / `claude-opus-4-8`), default thinking level, the `packages` list (npm
  extensions), and the external `skills` path. **No secrets.**
- `models.json` — my custom **provider + model catalog** (Azure AI Foundry endpoints for the
  Claude / GPT models I use). Contains **no API keys** (those live in `auth.json`, which is *not*
  vendored). The Foundry resource hostname is **templated** as
  `https://YOUR-FOUNDRY-RESOURCE.services.ai.azure.com` — replace it with your real resource before
  use (see restore steps).
- `extensions/supacode/index.ts` — the local Supacode↔Pi integration extension, auto-discovered
  from `~/.pi/agent/extensions/`. **Supacode-managed**; vendored here as a fallback.
- `skills/supacode-cli/SKILL.md` — the local Supacode CLI skill, auto-discovered from
  `~/.pi/agent/skills/`. **Supacode-managed**; vendored here as a fallback.
- `agent-skills/` — the complete, user-managed `~/.agents/skills/` collection. This location is
  automatically discovered by Pi and other Agent Skills-compatible coding agents. It includes
  each skill's supporting scripts, references, and assets; package-provided, dotnet, and Aspire
  skills are restored separately from their upstream repositories.

## Packages (extensions) I run

Declared in `settings.json` → `packages`. Pi installs any missing declared packages automatically
on first launch (into `~/.pi/agent/npm/`):

- `npm:pi-web-access`
- `npm:pi-mcp-adapter`
- `npm:context-mode`
- `npm:pi-subagents`
- `npm:pi-lens`
- `npm:@hypabolic/pi-hypa`
- `npm:pi-powerline-footer`

The external skill paths in `settings.json` are cloned by the setup script:

- `~/pi-skills/dotnet-skills/plugins` from [dotnet/skills](https://github.com/dotnet/skills)
- `~/pi-skills/aspire-skills/skills` from [microsoft/aspire-skills](https://github.com/microsoft/aspire-skills)

They remain upstream-managed rather than being duplicated in `agent-skills/`.

## What the Mac setup script does

`01 - Setup Mac Environment.sh` installs Pi (npm global), then:

1. Backs up any existing `~/.pi/agent/settings.json` and `models.json` to `*.backup`.
2. Copies `settings.json` and `models.json` into `~/.pi/agent/`.
3. Copies the Pi-local `extensions/` and `skills/` into `~/.pi/agent/`.
4. Restores the vendored shared skills from `agent-skills/` into `~/.agents/skills/`; Pi discovers
   that location automatically.
5. Clones the external dotnet and Aspire skill repositories into `~/pi-skills/`.

## Manual steps to finish the restore

1. **Log in.** `auth.json` (API keys/tokens) is intentionally not vendored. Run `pi` and use
   `/login` for each provider you use (Anthropic, GitHub Copilot, OpenAI/Codex, Azure Foundry…).
2. **Set the Foundry endpoint.** Edit `~/.pi/agent/models.json` and replace
   `YOUR-FOUNDRY-RESOURCE` with your real Azure AI Foundry resource name.
3. **Install declared packages.** They install automatically on first `pi` launch; to force it,
   run `pi update --extensions`.
4. **External skills.** The setup script clones both repositories automatically. To restore them
   manually, run:

   ```sh
   mkdir -p ~/pi-skills
   git clone https://github.com/dotnet/skills.git ~/pi-skills/dotnet-skills
   git clone https://github.com/microsoft/aspire-skills.git ~/pi-skills/aspire-skills
   ```

5. **Supacode resources** (optional) are restored automatically when you install and connect
   Supacode; the vendored copies here are only a fallback.

## Updating the shared-skill snapshot

After adding or changing a skill, refresh the version committed to this repository before setting
up another Mac. Review it for secrets first, then run from the repository root:

```sh
rsync -a --delete --exclude='.DS_Store' ~/.pi/agent/skills/ Pi/skills/
rsync -a --delete --exclude='.DS_Store' --exclude='/aspire/' --exclude='/aspire-*/' \
  ~/.agents/skills/ Pi/agent-skills/
git add Pi/skills Pi/agent-skills
```

The setup script intentionally does not copy `~/.pi/agent/npm/`: those are package-managed
extensions, reinstalled from `settings.json`. It also does not copy the separately cloned
`dotnet/skills` or `microsoft/aspire-skills` repositories.

## Security

No tokens or API keys are stored in this folder. `auth.json` is never vendored. If you add secrets
to any Pi config, template them out before committing to this public repo (the Azure hostname in
`models.json` is already templated for this reason).
