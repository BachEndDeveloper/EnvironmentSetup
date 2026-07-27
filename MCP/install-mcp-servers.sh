#!/usr/bin/env bash
# Provision the MCP servers declared in MCP/servers.json.
#
# Called by "01 - Setup Mac Environment.sh"; safe to run on its own.
#
# For each declared server: clone (or fetch) at its pinned ref, build it, then
# register it with Claude Desktop and Claude Code. Pi needs no registration -
# ~/.pi/agent/mcp.json imports from both Claude hosts.
#
# Two rules this script exists to enforce:
#   1. NEVER hand-edit ~/.claude.json. It holds ~73 KB of live project and
#      session state; a stray write would destroy it. Claude Code is mutated
#      only through its own `claude mcp add-json` CLI.
#   2. NEVER hardcode an interpreter path into the repository. GUI hosts such as
#      Claude Desktop launch with a minimal PATH and cannot find an nvm-managed
#      `node`, so the absolute path is REQUIRED in the generated host config -
#      but it is resolved here, at install time, and re-resolved on every run.
#      Re-run this after `nvm install --lts` to pick up a new Node.

set -euo pipefail

cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
MANIFEST="servers.json"
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST not found next to this script." >&2; exit 1; }

DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
PI_MCP_CONFIG="$HOME/.pi/agent/mcp.json"

# Resolve this machine's node once. Hosts launched from the GUI do not inherit
# the shell PATH, so the generated config needs the absolute path.
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
	echo "WARNING: 'node' is not on PATH - skipping MCP provisioning entirely." >&2
	exit 0
fi
echo "Using node: $NODE_BIN"

server_count="$(python3 -c 'import json,sys; print(len(json.load(open("servers.json"))["servers"]))')"
[ "$server_count" -gt 0 ] || { echo "No MCP servers declared - nothing to do."; exit 0; }

for i in $(seq 0 $((server_count - 1))); do
	# Read one server's fields as shell-safe assignments.
	eval "$(python3 - "$i" <<'PY'
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
PY
	)"

	echo
	echo "=== MCP server: $SRV_NAME ($SRV_REF) ==="

	# --- checkout at the pinned ref (mirrors the AI-Skills block in the setup script)
	if [ -d "$SRV_DIR/.git" ]; then
		git -C "$SRV_DIR" fetch --tags --prune origin || echo "WARNING: could not fetch $SRV_NAME updates." >&2
	elif [ -e "$SRV_DIR" ]; then
		echo "ERROR: $SRV_DIR exists but is not a Git checkout - skipping $SRV_NAME." >&2
		continue
	else
		mkdir -p "$(dirname "$SRV_DIR")"
		git clone "$SRV_REPO" "$SRV_DIR" || { echo "WARNING: could not clone $SRV_NAME - skipping." >&2; continue; }
	fi

	if ! git -C "$SRV_DIR" checkout --detach "$SRV_REF" >/dev/null 2>&1; then
		echo "WARNING: could not check out $SRV_REF for $SRV_NAME - skipping build and registration." >&2
		continue
	fi

	# --- build
	if ! ( cd "$SRV_DIR" && eval "$SRV_BUILD" ); then
		echo "WARNING: build failed for $SRV_NAME - leaving it unregistered." >&2
		continue
	fi

	ENTRY_PATH="$SRV_DIR/$SRV_ENTRY"
	if [ ! -f "$ENTRY_PATH" ]; then
		echo "WARNING: $SRV_NAME built but $ENTRY_PATH is missing - leaving it unregistered." >&2
		continue
	fi

	# --- the host entry, built once and reused by both registrations
	SERVER_JSON="$(python3 - "$i" "$NODE_BIN" "$ENTRY_PATH" <<'PY'
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
	python3 - "$SRV_NAME" "$SERVER_JSON" "$DESKTOP_CONFIG" <<'PY'
import json, os, shutil, sys
name, entry, path = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    shutil.copy2(path, path + ".backup")
    try:
        cfg = json.load(open(path))
    except json.JSONDecodeError:
        print(f"WARNING: {path} is not valid JSON - not touching it.", file=sys.stderr)
        raise SystemExit(0)
else:
    cfg = {}
cfg.setdefault("mcpServers", {})
if cfg["mcpServers"].get(name) == entry:
    print(f"  Claude Desktop: {name} already up to date")
else:
    cfg["mcpServers"][name] = entry          # only this key is touched
    json.dump(cfg, open(path, "w"), indent=2)
    open(path, "a").write("\n")
    print(f"  Claude Desktop: {name} registered")
PY

	# --- Claude Code: never hand-edited; use its own CLI
	if command -v claude >/dev/null 2>&1; then
		if claude mcp get "$SRV_NAME" >/dev/null 2>&1; then
			echo "  Claude Code: $SRV_NAME already registered (leaving as-is)"
		elif claude mcp add-json "$SRV_NAME" "$SERVER_JSON" --scope user >/dev/null 2>&1; then
			echo "  Claude Code: $SRV_NAME registered via 'claude mcp add-json --scope user'"
		else
			echo "WARNING: 'claude mcp add-json' failed for $SRV_NAME - add it manually:" >&2
			echo "         claude mcp add-json $SRV_NAME '$SERVER_JSON' --scope user" >&2
		fi
	else
		echo "WARNING: 'claude' CLI not found - $SRV_NAME not registered with Claude Code." >&2
	fi

	if [ -n "$SRV_POST" ]; then
		echo "  NEXT: cd \"$SRV_DIR\" && $SRV_POST   (one-time sign-in; no token is stored in this repo)"
	fi
done

# --- Pi: imports from the two Claude hosts rather than declaring its own servers.
if [ -f "$PI_MCP_CONFIG" ]; then
	if python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if {"claude-code","claude-desktop"} <= set(c.get("imports",[])) else 1)' "$PI_MCP_CONFIG"; then
		echo
		echo "Pi: imports from claude-code and claude-desktop - no separate registration needed."
	else
		echo
		echo "WARNING: $PI_MCP_CONFIG does not import from both Claude hosts, so Pi will not see" >&2
		echo "         these servers. Expected: {\"imports\": [\"claude-code\", \"claude-desktop\"]}" >&2
	fi
else
	echo
	echo "WARNING: $PI_MCP_CONFIG not found - Pi will not see these MCP servers." >&2
fi
