# Pi coding-agent configuration

Backup of the non-secret [Pi](https://pi.dev) configuration restored on a new machine. Personal and shared skills are **not** stored here: they are versioned in the private [AI-Skills](https://github.com/BachEndDeveloper/AI-Skills) repository and installed by the main setup script.

## Files

- `settings.json` — global Pi preferences, provider/model defaults, Pi package list, and the upstream dotnet- and Aspire-skills paths. It contains no secrets.
- `models.json` — custom Azure AI Foundry provider/model catalog. It contains no API keys; the Foundry hostname is templated as `YOUR-FOUNDRY-RESOURCE`.
- `extensions/supacode/index.ts` — Supacode↔Pi integration extension retained as a fallback. Supacode itself is installed through the Homebrew cask in the root `Brewfile`.

## What the macOS setup script restores

1. It backs up existing `~/.pi/agent/settings.json` and `models.json`.
2. It copies this directory's `settings.json`, `models.json`, and local extensions into `~/.pi/agent/`.
3. Earlier in the script, it clones the private AI-Skills repository at its pinned tag and registers it as a Pi package. That package is the sole source for repository-managed skills.
4. It clones the upstream dotnet and Aspire skills repositories into `~/pi-skills/`, because this configuration references both paths.

No skill directory is copied from this repository into `~/.agents/skills` or `~/.pi/agent/skills`.

## After setup

1. Run `pi` and complete `/login` for each provider. `auth.json` is intentionally never committed.
2. Replace `YOUR-FOUNDRY-RESOURCE` in `~/.pi/agent/models.json` if Azure AI Foundry is required.
3. Pi installs declared packages automatically on first launch; use `pi update --extensions` to force reconciliation.
4. Update personal or shared skills only in the AI-Skills repository. Update the hardcoded tag in `01 - Setup Mac Environment.sh` when adopting a reviewed release.

## Security

No tokens, API keys, browser credentials, or internal documents belong in this repository. Keep the AI-Skills repository private and review every skill change before tagging a release.
