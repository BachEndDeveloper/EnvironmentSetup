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
#      only through its own `claude mcp` CLI. Pi registrations use `pi mcp`
#      in ~/.pi/agent/mcp.json, which pi-mcp-adapter also discovers.
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

if [[ "${1:-}" == "--check-machine-local" ]]; then
	python3 check-machine-local.py
	exit $?
fi

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

# Pi keeps the adapter, which discovers Pi's global mcp.json on Pi 0.99+.
# The shared registry's machine-local entries are checked, never rewritten.

if [ -f "$PI_SETTINGS" ] && grep -q '"npm:pi-mcp-adapter"' "$PI_SETTINGS"; then
	echo "Pi: pi-mcp-adapter reads ~/.pi/agent/mcp.json and ~/.config/mcp/mcp.json (built-in MCP must be disabled)."
else
	echo "WARNING: pi-mcp-adapter not declared in Pi settings; restore Pi/settings.json with setup before using adapter-only entries." >&2
fi

server_count="$(python3 -c 'import json,sys; print(len(json.load(open("servers.json"))["servers"]))')"
[ "$server_count" -gt 0 ] || {
	echo "No MCP servers declared - nothing to do."
	exit 0
}

for i in $(seq 0 $((server_count - 1))); do
	# Read one server's fields as shell-safe assignments.
	if ! assignments="$(
		python3 - "$i" <<'PY'
import json, shlex, sys, os, re
s = json.load(open("servers.json"))["servers"][int(sys.argv[1])]
kind = s.get("type", "git")
if kind not in ("git", "remote", "machine-local"):
    raise SystemExit(f"unknown server type for {s['name']}")
if kind == "git" and any(not s.get(key) for key in ("dir", "repo", "ref", "entry")):
    raise SystemExit(f"missing Git deployment fields for {s['name']}")
if kind == "remote":
    if not re.fullmatch(r"\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\})", s.get("url", "")):
        raise SystemExit(f"remote url must be an environment-variable reference for {s['name']}")
    if s.get("env") or s.get("piPackage"):
        raise SystemExit(f"remote entries do not support env/piPackage; use machine-local config for {s['name']}")
d = os.path.expandvars(s.get("dir", ""))
print(f'SRV_TYPE={shlex.quote(kind)}')
print(f'SRV_NAME={shlex.quote(s["name"])}')
print(f'SRV_REPO={shlex.quote(s.get("repo", ""))}')
print(f'SRV_REF={shlex.quote(s.get("ref", ""))}')
print(f'SRV_DIR={shlex.quote(d)}')
print(f'SRV_ENTRY={shlex.quote(s.get("entry", ""))}')
print(f'SRV_POST={shlex.quote(s.get("postInstall", ""))}')
print(f'SRV_BUILD={shlex.quote(" && ".join(s.get("build", [])))}')
print(f'SRV_DESC={shlex.quote(s.get("description", ""))}')
print(f'SRV_PI_PACKAGE={"true" if s.get("piPackage") else "false"}')
print(f'SRV_SUPERSEDES={shlex.quote(" ".join(s.get("supersedes", [])))}')
# Hosts to register with; default is all three. Unknown names fail loudly.
hosts = s.get("hosts", ["claude-desktop", "claude-code", "pi"])
bad = [h for h in hosts if h not in ("claude-desktop", "claude-code", "pi")]
if bad:
    raise SystemExit(f"unknown host(s) {bad} for {s['name']} in servers.json")
print(f'SRV_HOSTS={shlex.quote(" ".join(hosts))}')
print(f'SRV_URL={shlex.quote(os.path.expandvars(s.get("url", "")))}')
print(f'SRV_REQUIRES={shlex.quote(chr(10).join(os.path.expandvars(r) for r in s.get("requires", [])))}')
PY
	)"; then
		echo "WARNING: invalid server declaration at index $i - skipping." >&2
		continue
	fi
	eval "$assignments"

	echo
	echo "=== MCP server: $SRV_NAME ($SRV_TYPE) ==="
	if [[ "$SRV_TYPE" == "machine-local" ]]; then
		python3 check-machine-local.py "$SRV_NAME" || true
		continue
	fi

	# --- paths the server needs but this installer never provisions (e.g. a private data repo).
	# Warn, but still install: the server itself refuses to start without them.
	while IFS= read -r required; do
		[ -n "$required" ] || continue
		[ -e "$required" ] || echo "WARNING: $SRV_NAME needs $required, which does not exist yet - restore or clone it, then restart the hosts." >&2
	done <<<"$SRV_REQUIRES"
	# Assigned by the shell-safe manifest projection above.
	# shellcheck disable=SC2153
	wants_host() { [[ " $SRV_HOSTS " == *" $1 "* ]]; }

	if [[ "$SRV_TYPE" == "remote" ]]; then
		if [[ -z "$SRV_URL" || "$SRV_URL" == *'$'* || ! "$SRV_URL" =~ ^https?:// ]]; then
			echo "WARNING: $SRV_NAME url reference is unset - configure it locally and re-run." >&2
			continue
		fi
	else
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
			# Keep a clone retryable even if no release/build is available yet.
			git -C "$SRV_DIR" checkout --detach HEAD >/dev/null 2>&1 || { echo "WARNING: could not detach new $SRV_NAME deployment." >&2; continue; }
		fi

		# --- resolve the release to run: "latest" = highest vX.Y.Z tag; an explicit tag is a hold-back pin
		if ! RESOLVED_REF="$(bash ../scripts/resolve-release.sh "$SRV_DIR" "$SRV_REF")"; then
			echo "WARNING: no release to run for $SRV_NAME - skipping build and registration." >&2
			continue
		fi
		[ "$RESOLVED_REF" = "$SRV_REF" ] || echo "  $SRV_NAME: $SRV_REF -> $RESOLVED_REF"
		SRV_REF="$RESOLVED_REF"

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

	fi

	# --- the host entry, built once and reused by every registration
	SERVER_JSON="$(
		python3 - "$i" "$LAUNCHER" "${ENTRY_PATH:-}" <<'PY'
import json, os, sys
s = json.load(open("servers.json"))["servers"][int(sys.argv[1])]
# Expand $HOME and similar here: GUI hosts pass env values through literally.
env = {k: os.path.expandvars(str(v)) for k, v in (s.get("env") or {}).items()}
# Optional override, taken from the environment so no real tenant id is ever
# committed to this public repository.
if os.environ.get("M365_TENANT_ID") and s["name"].startswith("m365"):
    env["TENANT_ID"] = os.environ["M365_TENANT_ID"]
entry = {"url": os.path.expandvars(s["url"])} if s.get("type") == "remote" else {"command": sys.argv[2], "args": [sys.argv[3]]}
if env:
    entry["env"] = env
print(json.dumps(entry))
PY
	)"

	# --- Claude Desktop: small file, surgical merge, backup first
	if [[ "$SRV_TYPE" == "remote" ]]; then
		echo "  Claude Desktop: remote connector setup is manual (not written to local MCP config)"
	elif ! wants_host claude-desktop; then
		echo "  Claude Desktop: skipped (not in this server's hosts)"
	else
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
	fi

	# --- Claude Code: never hand-edited; use its own CLI. Always re-register, so a
	# changed path or launcher actually lands instead of being "left as-is".
	if ! wants_host claude-code; then
		echo "  Claude Code: skipped (not in this server's hosts)"
	elif command -v claude >/dev/null 2>&1; then
		for old in $SRV_SUPERSEDES; do
			claude mcp remove "$old" --scope user >/dev/null 2>&1 && echo "  Claude Code: removed superseded $old" || true
		done
		claude mcp remove "$SRV_NAME" --scope user >/dev/null 2>&1 || true
		if claude mcp add-json "$SRV_NAME" "$SERVER_JSON" --scope user >/dev/null 2>&1; then
			echo "  Claude Code: $SRV_NAME registered via 'claude mcp add-json --scope user'"
		else
			echo "WARNING: 'claude mcp add-json' failed for $SRV_NAME - add it manually:" >&2
			echo "         Check the machine-local config and use claude mcp add-json for $SRV_NAME (values withheld)." >&2
		fi
	else
		echo "WARNING: 'claude' CLI not found - $SRV_NAME not registered with Claude Code." >&2
	fi

	# --- Pi: register in mcp.json through its CLI; the adapter reads this registry. `pi mcp add` replaces an
	# existing entry of the same name, so this is idempotent.
	if ! wants_host pi; then
		echo "  Pi: skipped (not in this server's hosts)"
	elif command -v pi >/dev/null 2>&1; then
		for old in $SRV_SUPERSEDES; do
			pi mcp remove "$old" >/dev/null 2>&1 && echo "  Pi: removed superseded $old" || true
		done
		eval "$(
			python3 - "$SERVER_JSON" <<'PY'
import json, shlex, sys
e = json.loads(sys.argv[1])
# `pi mcp add` takes `--env KEY=VALUE` as two arguments; the `--env=KEY=VALUE` form is rejected.
print("PI_ENV_ARGS=(" + " ".join(f"--env {shlex.quote(f'{k}={v}')}" for k, v in (e.get("env") or {}).items()) + ")")
PY
		)"
		pi_args=(mcp add "$SRV_NAME")
		[ -n "$SRV_DESC" ] && pi_args+=(--description "$SRV_DESC")
		if [[ "$SRV_TYPE" == "remote" ]]; then
			pi_args+=(--url "$SRV_URL")
		else
			pi_args+=("${PI_ENV_ARGS[@]+"${PI_ENV_ARGS[@]}"}" -- "$LAUNCHER" "$ENTRY_PATH")
		fi
		if pi "${pi_args[@]}" >/dev/null 2>&1; then
			echo "  Pi: $SRV_NAME registered via 'pi mcp add'"
		else
			echo "WARNING: 'pi mcp add' failed for $SRV_NAME - add it manually:" >&2
			echo "         Check the machine-local config and use pi mcp add for $SRV_NAME (values withheld)." >&2
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
