#!/usr/bin/env bash
# Provision the MCP servers declared in MCP/servers.json.
#
# Called by "01 - Setup Mac Environment.sh"; safe to run on its own.
#
# For each declared server: clone (or fetch) a DEPLOYMENT copy at its pinned
# ref, build it, then register it with Claude Desktop, Claude Code and Pi.
#
# Rules this script exists to enforce:
#   1. NEVER hand-edit ~/.claude.json. It holds ~73 KB of live project and
#      session state; a stray write would destroy it. Claude Code is mutated
#      only through its own `claude mcp` CLI, and Pi only through `pi mcp`.
#   2. NEVER write a versioned node path into a host config. GUI hosts launch
#      with a minimal PATH, so they need an absolute command - but an nvm path
#      such as ~/.nvm/versions/node/v24.16.0/bin/node breaks the moment that
#      version is removed, and the host fails with ENOENT. Every host is pointed
#      at ~/.local/bin/mcp-node instead, which follows nvm's `default` alias.
#   3. NEVER run a host from a development checkout. `dir` is a deployment-only
#      copy that this script moves between tags. Pointing it at a working copy
#      would detach it from its branch on every run, and make every host run
#      whatever was last built there. A checkout that is on a branch is refused.

set -euo pipefail

cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
MANIFEST="servers.json"
[ -f "$MANIFEST" ] || {
	echo "ERROR: $MANIFEST not found next to this script." >&2
	exit 1
}

DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
PI_SETTINGS="$HOME/.pi/agent/settings.json"
LAUNCHER="$HOME/.local/bin/mcp-node"

# node is still required: servers are built with npm, and mcp-node needs a node to find.
if ! command -v node >/dev/null 2>&1; then
	echo "WARNING: 'node' is not on PATH - skipping MCP provisioning entirely." >&2
	exit 0
fi

# Install (or refresh) the launcher every host is pointed at.
mkdir -p "$(dirname "$LAUNCHER")"
if ! cmp -s mcp-node "$LAUNCHER" 2>/dev/null; then
	cp mcp-node "$LAUNCHER"
	chmod 755 "$LAUNCHER"
	echo "Installed launcher: $LAUNCHER"
fi
echo "Hosts will launch servers via: $LAUNCHER"

# pi-mcp-adapter replaces Pi's built-in MCP support, which is what this script
# registers with. Warn rather than edit settings: removing a package is the
# user's call.
if [ -f "$PI_SETTINGS" ] && grep -q '"npm:pi-mcp-adapter"' "$PI_SETTINGS"; then
	echo "WARNING: pi-mcp-adapter is installed and replaces Pi's built-in MCP support, so the" >&2
	echo "         Pi registrations below will not be read. Remove it: pi remove npm:pi-mcp-adapter" >&2
fi

server_count="$(python3 -c 'import json,sys; print(len(json.load(open("servers.json"))["servers"]))')"
[ "$server_count" -gt 0 ] || {
	echo "No MCP servers declared - nothing to do."
	exit 0
}

for i in $(seq 0 $((server_count - 1))); do
	# Read one server's fields as shell-safe assignments.
	eval "$(
		python3 - "$i" <<'PY'
import json, shlex, sys, os
s = json.load(open("servers.json"))["servers"][int(sys.argv[1])]
d = os.path.expandvars(s["dir"])
print(f'SRV_NAME={shlex.quote(s["name"])}')
print(f'SRV_REPO={shlex.quote(s["repo"])}')
print(f'SRV_REF={shlex.quote(s["ref"])}')
print(f'SRV_DIR={shlex.quote(d)}')
print(f'SRV_ENTRY={shlex.quote(s["entry"])}')
print(f'SRV_POST={shlex.quote(s.get("postInstall", ""))}')
print(f'SRV_BUILD={shlex.quote(" && ".join(s.get("build", [])))}')
print(f'SRV_DESC={shlex.quote(s.get("description", ""))}')
print(f'SRV_PI_PACKAGE={"true" if s.get("piPackage") else "false"}')
print(f'SRV_SUPERSEDES={shlex.quote(" ".join(s.get("supersedes", [])))}')
PY
	)"

	echo
	echo "=== MCP server: $SRV_NAME ($SRV_REF) ==="

	# --- deployment checkout at the pinned ref (mirrors the AI-Skills block in the setup script)
	if [ -d "$SRV_DIR/.git" ]; then
		if branch="$(git -C "$SRV_DIR" symbolic-ref -q --short HEAD)"; then
			echo "WARNING: $SRV_DIR is on branch '$branch', so it looks like a development checkout." >&2
			echo "         This installer only manages deployment copies - skipping $SRV_NAME." >&2
			echo "         Point \"dir\" in servers.json somewhere else (see MCP/README.md)." >&2
			continue
		fi
		git -C "$SRV_DIR" fetch --tags --prune origin || echo "WARNING: could not fetch $SRV_NAME updates." >&2
	elif [ -e "$SRV_DIR" ]; then
		echo "ERROR: $SRV_DIR exists but is not a Git checkout - skipping $SRV_NAME." >&2
		continue
	else
		mkdir -p "$(dirname "$SRV_DIR")"
		git clone "$SRV_REPO" "$SRV_DIR" || {
			echo "WARNING: could not clone $SRV_NAME (check your GitHub SSH key) - skipping." >&2
			continue
		}
	fi

	if ! git -C "$SRV_DIR" checkout --detach "$SRV_REF" >/dev/null 2>&1; then
		echo "WARNING: could not check out $SRV_REF for $SRV_NAME - skipping build and registration." >&2
		continue
	fi

	# --- build
	if ! (cd "$SRV_DIR" && eval "$SRV_BUILD"); then
		echo "WARNING: build failed for $SRV_NAME - leaving it unregistered." >&2
		continue
	fi

	ENTRY_PATH="$SRV_DIR/$SRV_ENTRY"
	if [ ! -f "$ENTRY_PATH" ]; then
		echo "WARNING: $SRV_NAME built but $ENTRY_PATH is missing - leaving it unregistered." >&2
		continue
	fi

	# --- the host entry, built once and reused by every registration
	SERVER_JSON="$(
		python3 - "$i" "$LAUNCHER" "$ENTRY_PATH" <<'PY'
import json, os, sys
s = json.load(open("servers.json"))["servers"][int(sys.argv[1])]
env = dict(s.get("env") or {})
# Optional override, taken from the environment so no real tenant id is ever
# committed to this public repository.
if os.environ.get("M365_TENANT_ID") and s["name"].startswith("m365"):
    env["TENANT_ID"] = os.environ["M365_TENANT_ID"]
entry = {"command": sys.argv[2], "args": [sys.argv[3]]}
if env:
    entry["env"] = env
print(json.dumps(entry))
PY
	)"

	# --- Claude Desktop: small file, surgical merge, backup first
	python3 - "$SRV_NAME" "$SERVER_JSON" "$DESKTOP_CONFIG" "$SRV_SUPERSEDES" <<'PY'
import json, os, shutil, sys
name, entry, path, superseded = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3], sys.argv[4].split()
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    try:
        cfg = json.load(open(path))
    except json.JSONDecodeError:
        print(f"WARNING: {path} is not valid JSON - not touching it.", file=sys.stderr)
        raise SystemExit(0)
else:
    cfg = {}
servers = cfg.setdefault("mcpServers", {})
removed = [old for old in superseded if old in servers]
if servers.get(name) == entry and not removed:
    print(f"  Claude Desktop: {name} already up to date")
    raise SystemExit(0)
if os.path.exists(path):
    shutil.copy2(path, path + ".backup")
for old in removed:
    del servers[old]
servers[name] = entry  # only these keys are touched
json.dump(cfg, open(path, "w"), indent=2)
open(path, "a").write("\n")
print(f"  Claude Desktop: {name} registered" + (f" (removed superseded {', '.join(removed)})" if removed else ""))
PY

	# --- Claude Code: never hand-edited; use its own CLI. Always re-register, so a
	# changed path or launcher actually lands instead of being "left as-is".
	if command -v claude >/dev/null 2>&1; then
		for old in $SRV_SUPERSEDES; do
			claude mcp remove "$old" --scope user >/dev/null 2>&1 && echo "  Claude Code: removed superseded $old"
		done
		claude mcp remove "$SRV_NAME" --scope user >/dev/null 2>&1 || true
		if claude mcp add-json "$SRV_NAME" "$SERVER_JSON" --scope user >/dev/null 2>&1; then
			echo "  Claude Code: $SRV_NAME registered via 'claude mcp add-json --scope user'"
		else
			echo "WARNING: 'claude mcp add-json' failed for $SRV_NAME - add it manually:" >&2
			echo "         claude mcp add-json $SRV_NAME '$SERVER_JSON' --scope user" >&2
		fi
	else
		echo "WARNING: 'claude' CLI not found - $SRV_NAME not registered with Claude Code." >&2
	fi

	# --- Pi: built-in MCP support, through its own CLI. `pi mcp add` replaces an
	# existing entry of the same name, so this is idempotent.
	if command -v pi >/dev/null 2>&1; then
		for old in $SRV_SUPERSEDES; do
			pi mcp remove "$old" >/dev/null 2>&1 && echo "  Pi: removed superseded $old"
		done
		eval "$(
			python3 - "$SERVER_JSON" <<'PY'
import json, shlex, sys
e = json.loads(sys.argv[1])
print("PI_ENV_ARGS=(" + " ".join(shlex.quote(f"--env={k}={v}") for k, v in (e.get("env") or {}).items()) + ")")
PY
		)"
		pi_args=(mcp add "$SRV_NAME")
		[ -n "$SRV_DESC" ] && pi_args+=(--description "$SRV_DESC")
		if pi "${pi_args[@]}" "${PI_ENV_ARGS[@]+"${PI_ENV_ARGS[@]}"}" -- "$LAUNCHER" "$ENTRY_PATH" >/dev/null 2>&1; then
			echo "  Pi: $SRV_NAME registered via 'pi mcp add'"
		else
			echo "WARNING: 'pi mcp add' failed for $SRV_NAME - add it manually:" >&2
			echo "         pi mcp add $SRV_NAME -- $LAUNCHER $ENTRY_PATH" >&2
		fi

		# Skills the server ships (e.g. m365-tools): register the checkout as a Pi
		# package, the same way the setup script registers AI-Skills.
		if [ "$SRV_PI_PACKAGE" = "true" ]; then
			if pi install "$SRV_DIR" >/dev/null 2>&1; then
				echo "  Pi: $SRV_NAME skills registered as a local package"
			else
				echo "WARNING: 'pi install $SRV_DIR' failed - register its skills manually." >&2
			fi
		fi
	else
		echo "WARNING: 'pi' not found - $SRV_NAME not registered with Pi." >&2
	fi

	if [ -n "$SRV_POST" ]; then
		echo "  NEXT: cd \"$SRV_DIR\" && $SRV_POST   (one-time sign-in; the token is stored per user, never in a repo)"
	fi
done
