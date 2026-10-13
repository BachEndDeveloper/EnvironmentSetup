#!/usr/bin/env bash
# Deploy a released AI-Skills copy; never detach the development checkout.
set -euo pipefail
setup_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AI_SKILLS_REPO="git@github.com:BachEndDeveloper/AI-Skills.git"
AI_SKILLS_REF="${AI_SKILLS_REF:-latest}"
AI_SKILLS_DIR="${AI_SKILLS_DIR:-$HOME/.local/share/ai-skills}"

if [[ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$AI_SKILLS_DIR")" == "$(python3 -c 'import os; print(os.path.realpath(os.path.expanduser("~/source/AI-Skills")))')" ]]; then
	echo "ERROR: AI_SKILLS_DIR must be a deployment copy, not ~/source/AI-Skills." >&2
	exit 1
fi
if [[ -d "$AI_SKILLS_DIR/.git" ]]; then
	if branch="$(git -C "$AI_SKILLS_DIR" symbolic-ref -q --short HEAD)"; then
		echo "ERROR: AI_SKILLS_DIR is on branch '$branch'; refusing a development checkout." >&2
		exit 1
	fi
	if [[ -n "$(git -C "$AI_SKILLS_DIR" status --porcelain)" ]]; then
		echo "ERROR: AI_SKILLS_DIR has local changes; refusing to overwrite them." >&2
		exit 1
	fi
	git -C "$AI_SKILLS_DIR" fetch --tags --prune origin || echo "WARNING: could not fetch AI-Skills updates; using local tags." >&2
elif [[ -e "$AI_SKILLS_DIR" ]]; then
	echo "ERROR: AI_SKILLS_DIR exists but is not a Git checkout." >&2
	exit 1
else
	mkdir -p "$(dirname "$AI_SKILLS_DIR")"
	git clone "$AI_SKILLS_REPO" "$AI_SKILLS_DIR"
	# A failed release resolution must remain retryable, not look like a dev branch.
	git -C "$AI_SKILLS_DIR" checkout --detach HEAD
fi
ref="$(bash "$setup_dir/scripts/resolve-release.sh" "$AI_SKILLS_DIR" "$AI_SKILLS_REF")"
[[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: AI-Skills requires a stable vX.Y.Z tag." >&2; exit 1; }
echo "AI-Skills: $AI_SKILLS_REF -> $ref"
git -C "$AI_SKILLS_DIR" checkout --detach "$ref"
env AI_SKILLS_DIR="$AI_SKILLS_DIR" bash "$AI_SKILLS_DIR/scripts/install-local.sh"
# Also migrate when adopting a release predating install-local.sh's migration logic.
if python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.pi/agent/settings.json")
settings = json.load(open(path)) if os.path.exists(path) else {}
base = os.path.dirname(path)
dev = os.path.realpath(os.path.expanduser("~/source/AI-Skills"))
for package in settings.get("packages", []):
    source = package if isinstance(package, str) else package.get("source", "")
    if source.startswith(("npm:", "git:", "https:", "ssh:")):
        continue
    if os.path.realpath(os.path.join(base, os.path.expanduser(source))) == dev:
        raise SystemExit(0)
raise SystemExit(1)
PY
then
	pi remove "$HOME/source/AI-Skills"
fi
env AI_SKILLS_DIR="$AI_SKILLS_DIR" bash "$AI_SKILLS_DIR/scripts/link-claude-code.sh" --apply
