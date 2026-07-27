#!/usr/bin/env bash
# Setup Mac

# Fail fast and loudly: stop at the first failing command, treat unset variables as
# errors, and surface failures from inside a pipeline. Steps that are *expected* to
# fail benignly are guarded individually with `|| true` or an explicit warning, so the
# tolerance is visible at the call site instead of being global.
set -euo pipefail

# Run from the repository root regardless of the caller's working directory - every
# cp/brew bundle below uses repo-relative paths. `pwd -P` normalises the directory path
# (it resolves symlinked *parent directories*, not a symlink to the script file itself),
# so the Brewfile check below is what actually catches a wrong tree - including a
# symlinked entry point and the stdin case where BASH_SOURCE is unset.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 1
cd -- "$script_dir" || exit 1
[ -f Brewfile ] || {
	echo "ERROR: run this script from the repository root (Brewfile not found)." >&2
	exit 1
}

# Install Homebrew
if ! command -v brew >/dev/null 2>&1; then
	# Assign first: `bash -c "$(curl ...)"` silently succeeds when curl fails, because the
	# empty command substitution becomes `bash -c ""` (rc 0). Neither -e nor pipefail sees it.
	brew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	/bin/bash -c "$brew_installer"
	# Same trap once more: `eval "$(... shellenv)"` collapses to `eval ""` (rc 0) when brew
	# is absent or fails - which, combined with the tolerated `brew bundle` below, would
	# silently skip the ENTIRE Brewfile while reporting success. Check the binary exists,
	# then assign first so `set -e` actually sees a failing shellenv.
	[ -x /opt/homebrew/bin/brew ] || {
		echo "ERROR: Homebrew install did not produce /opt/homebrew/bin/brew." >&2
		exit 1
	}
	brew_env="$(/opt/homebrew/bin/brew shellenv)"
	eval "$brew_env"
else
	# A stale formula index is not worth aborting the whole machine setup for - the same
	# tolerance the Brewfile step below already gets.
	brew update || echo "WARNING: brew update failed - continuing with the cached formula index." >&2
	echo "HOMEBREW updated!"
fi

# Install / upgrade all declared Homebrew taps, formulae, casks and fonts (see Brewfile).
# brew bundle exits non-zero if ANY single package fails (untrusted tap, renamed cask,
# transient download). One bad package must not abort the whole machine setup.
BREW_BUNDLE_FAILED=0
# Print the reminder from an EXIT trap rather than at the end of the script: any later
# step that aborts the run would otherwise swallow it, which is exactly when it matters.
trap '[ "${BREW_BUNDLE_FAILED:-0}" = "1" ] && echo "REMINDER: brew bundle did not complete cleanly - re-run '\''brew bundle --upgrade --file=\"Brewfile\"'\''." >&2' EXIT
if ! brew bundle --upgrade --file="Brewfile"; then
	BREW_BUNDLE_FAILED=1
	echo "WARNING: brew bundle reported failures (see above) - continuing." >&2
fi

# --- Languages & runtimes ---

# Node via nvm, defaulting to LTS (.zshrc loads nvm; install nvm here if missing).
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
	echo "Installing nvm"
	curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# nvm.sh is not written against `set -e`/`set -u`, so relax them for the source only. The
# wrapper deliberately covers just the `.` line: the nvm calls below run fine under -eu.
set +eu
. "$NVM_DIR/nvm.sh"
set -eu
command -v nvm >/dev/null 2>&1 || {
	echo "ERROR: nvm not available after sourcing $NVM_DIR/nvm.sh" >&2
	exit 1
}
nvm install --lts
nvm alias default 'lts/*'

# --- AI coding agents ---

# GitHub Copilot CLI — standalone binary to ~/.local/bin (no Node required).
curl -fsSL https://gh.io/copilot-install | bash

# Claude Code CLI — native installer; auto-updates in the background (no Node required).
curl -fsSL https://claude.ai/install.sh | sh

# Pi coding agent CLI — npm-only (nvm/Node installed above; --ignore-scripts per pi.dev docs).
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# hunk — review-first terminal diff viewer for agentic coders (https://github.com/modem-dev/hunk).
# npm global (needs Node 18+, installed above); provides the `hunk` command (hunk diff / hunk show).
npm install -g hunkdiff

# Python managed by uv (uv installed via the Brewfile above). Installs the latest stable CPython.
# uv comes from the Brewfile, whose failure is tolerated above - so check for it rather than
# aborting the whole run (config restore, Neovim and the skills bootstrap all come after this).
if command -v uv >/dev/null 2>&1; then
	uv python install
else
	echo "WARNING: uv not found (it comes from the Brewfile) - skipping the Python install." >&2
fi

# .NET SDK is installed manually via the official installer (not Homebrew) - see README "## .NET / C#".
# The Aspire CLI needs the .NET SDK, so only install it once dotnet is on PATH.
if command -v dotnet >/dev/null 2>&1; then
	# .NET Aspire CLI -> installs to ~/.aspire/bin (already on PATH via .zshrc).
	curl -fsSL https://aspire.dev/install.sh | bash
else
	echo "WARNING: .NET SDK not found - skipping Aspire CLI." >&2
	echo "         Install .NET (see README '## .NET / C#'), then re-run this script." >&2
fi

# Fonts are installed via the Brewfile (font-monaspace, font-monaspice-nerd-font, font-monaspace-frozen).
# Editor font: "Monaspace Neon"  |  Terminal font: "MonaspiceNe Nerd Font"

# Copy Oh My Posh theme and zsh config (back up any existing .zshrc first)
cp OhMyPosh/custom-theme-oh-my-posh.json "$HOME/"
# NOTE: `[ test ] && cmd` aborts the script under `set -e` when the test is false, so
# every backup-if-present below is written as a full `if` block.
if [ -f "$HOME/.zshrc" ]; then
	cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi
cp Zsh/.zshrc "$HOME/.zshrc"

# Copy VS Code settings (correct macOS path)
VSCODE_USER="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE_USER"
cp VSCode/settings.json "$VSCODE_USER/settings.json"

# Copy Ghostty terminal config (replaces the retired iTerm2 setup)
mkdir -p "$HOME/.config/ghostty"
cp ghostty/config "$HOME/.config/ghostty/config"

# Copy Yazi file manager config (preview tooling installed via Brewfile)
mkdir -p "$HOME/.config/yazi"
cp yazi/yazi.toml "$HOME/.config/yazi/yazi.toml"

# Restore my Neovim / LazyVim config (vendored in nvim/ - see nvim/README.md).
# The config declares WHAT I run - my LazyVim extras and Mason LSPs/formatters - and the
# sync below installs the LATEST LazyVim plus every plugin/extra it declares (no version
# pinning, so I get current versions at the time I run this). Needs neovim + ripgrep (Brewfile).
if [ -d "$HOME/.config/nvim" ]; then
	nvim_backup="$HOME/.config/nvim.backup-$(date +%Y%m%d%H%M%S)"
	echo "Backing up existing ~/.config/nvim to $nvim_backup"
	mv "$HOME/.config/nvim" "$nvim_backup"
fi
mkdir -p "$HOME/.config/nvim"
cp -R nvim/. "$HOME/.config/nvim/"
# Install the latest LazyVim + all declared plugins/extras (Lazy sync). Mason installs the
# LSPs/formatters listed in lua/plugins/mason-tools.lua on the first interactive 'nvim' launch.
if command -v nvim >/dev/null 2>&1; then
	echo "Installing Neovim plugins (Lazy sync, latest versions)..."
	nvim --headless "+Lazy! sync" +qa || echo "WARNING: 'Lazy sync' failed - run ':Lazy sync' inside nvim."
else
	echo "WARNING: nvim not found - skipping plugin install (the Brewfile installs neovim)." >&2
fi

# Restore Claude Code customizations (settings + statusline footer + hooks).
# settings.json uses `node` from PATH and "$HOME/.claude/hooks/..." rather than absolute paths,
# so it is portable across machines and Node versions - see ClaudeCode/README.md.
# The GSD hooks themselves are NOT vendored here (they belong to the get-shit-done setup), so
# warn loudly if they are missing instead of leaving Claude Code silently hookless.
if [ -d "$HOME/.claude" ]; then
	if [ -f "$HOME/.claude/settings.json" ]; then
		cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup"
	fi
	cp ClaudeCode/settings.json "$HOME/.claude/settings.json"
	mkdir -p "$HOME/.claude/hooks"
	cp ClaudeCode/hooks/* "$HOME/.claude/hooks/" 2>/dev/null || true

	# Every hook command in settings.json must resolve, or it fails silently at runtime.
	missing_hooks=""
	for hook in gsd-check-update.js gsd-session-state.sh gsd-context-monitor.js \
		gsd-read-injection-scanner.js gsd-phase-boundary.sh gsd-prompt-guard.js \
		gsd-read-guard.js gsd-workflow-guard.js gsd-validate-commit.sh gsd-statusline.js; do
		[ -f "$HOME/.claude/hooks/$hook" ] || missing_hooks="$missing_hooks $hook"
	done
	if [ -n "$missing_hooks" ]; then
		echo "WARNING: Claude Code hooks referenced by settings.json are missing from ~/.claude/hooks:" >&2
		for hook in $missing_hooks; do echo "           - $hook" >&2; done
		echo "         Reinstall the GSD setup to restore them (see ClaudeCode/README.md)." >&2
	fi
	if ! command -v node >/dev/null 2>&1; then
		echo "WARNING: 'node' is not on PATH - the Claude Code hooks and statusline will not run." >&2
	fi
fi

# Restore Pi coding agent customizations (settings + custom provider/model catalog + local
# extensions/skills). NO secrets are vendored: run 'pi' then /login per provider, and set your
# Azure AI Foundry resource name in ~/.pi/agent/models.json (templated). See Pi/README.md.
PI_DIR="$HOME/.pi/agent"
if command -v pi >/dev/null 2>&1 || [ -d "$PI_DIR" ]; then
	mkdir -p "$PI_DIR/extensions"
	if [ -f "$PI_DIR/settings.json" ]; then
		cp "$PI_DIR/settings.json" "$PI_DIR/settings.json.backup"
	fi
	if [ -f "$PI_DIR/models.json" ]; then
		cp "$PI_DIR/models.json" "$PI_DIR/models.json.backup"
	fi
	cp Pi/settings.json "$PI_DIR/settings.json"
	cp Pi/models.json "$PI_DIR/models.json"
	cp -R Pi/extensions/. "$PI_DIR/extensions/"
	echo "Pi config restored. Declared packages install on first 'pi' launch (or 'pi update --extensions')."
	echo "         Remember: 'pi' + /login per provider, and set your Foundry resource in ~/.pi/agent/models.json."
fi

# Personal AI skills — private, version-pinned source of truth for Pi skills.
# This runs after Pi settings are restored so `pi install` records the package persistently.
# Update the repository URL or release tag here when the personal library moves or releases.
AI_SKILLS_REPO="git@github.com:BachEndDeveloper/AI-Skills.git"
AI_SKILLS_REF="v0.3.0"
AI_SKILLS_DIR="${AI_SKILLS_DIR:-$HOME/source/AI-Skills}"

if [[ -d "$AI_SKILLS_DIR/.git" ]]; then
	git -C "$AI_SKILLS_DIR" fetch --tags --prune origin || echo "WARNING: could not fetch AI-Skills updates." >&2
elif [[ -e "$AI_SKILLS_DIR" ]]; then
	echo "ERROR: $AI_SKILLS_DIR exists but is not a Git checkout." >&2
	exit 1
else
	mkdir -p "$(dirname "$AI_SKILLS_DIR")"
	# A fresh machine without a GitHub SSH key is the documented normal case: this clone
	# fails with `Permission denied (publickey)` (exit 128) and must not take the upstream
	# skills clones and the final reminders down with it.
	git clone "$AI_SKILLS_REPO" "$AI_SKILLS_DIR" || echo "WARNING: could not clone AI-Skills (check your GitHub SSH key) - skipping the skills bootstrap." >&2
fi

# The checkout and the local install are guarded for the same reason as the clone above:
# a missing tag or a half-set-up machine must not skip the upstream skills clones and the
# final reminders below, which are themselves deliberately tolerant.
# NOTE: `set -e` is IGNORED inside a subshell used as an `if` condition, so each step
# below carries its own explicit `|| exit 1` rather than relying on it.
if ! (
	git -C "$AI_SKILLS_DIR" checkout --detach "$AI_SKILLS_REF" || exit 1
	bash "$AI_SKILLS_DIR/scripts/install-local.sh" || exit 1
); then
	echo "WARNING: AI-Skills bootstrap failed - check your GitHub SSH key and that tag $AI_SKILLS_REF exists, then re-run." >&2
fi

# External skills referenced by Pi settings.json. Keep upstream-managed skills out of the
# shared snapshot so their repositories can evolve independently.
PI_SKILLS_DIR="$HOME/pi-skills"
if [ ! -d "$PI_SKILLS_DIR/dotnet-skills" ]; then
	mkdir -p "$PI_SKILLS_DIR"
	git clone https://github.com/dotnet/skills.git "$PI_SKILLS_DIR/dotnet-skills" || echo "WARNING: failed to clone dotnet/skills." >&2
fi
if [ ! -d "$PI_SKILLS_DIR/aspire-skills" ]; then
	mkdir -p "$PI_SKILLS_DIR"
	git clone https://github.com/microsoft/aspire-skills.git "$PI_SKILLS_DIR/aspire-skills" || echo "WARNING: failed to clone microsoft/aspire-skills." >&2
fi

echo "Done. In Rider: set editor font to 'Monaspace Neon' (ligatures on) and terminal font to 'MonaspiceNe Nerd Font'."
