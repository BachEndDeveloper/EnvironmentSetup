#!/usr/bin/env bash
# Shared headless ritual: on-demand and future launchd runs use the same guards.
set -euo pipefail
umask 077
export TZ=Europe/Copenhagen
export PATH="$HOME/.local/bin:${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
state_dir="$HOME/.local/share/memory-daily"
log_dir="$HOME/Library/Logs/memory-daily"
lock_dir="$state_dir/run.lock"
output=""
owns_lock=false
failure_reported=false
stream_output=false
final_line=""
log_file=""

notify() {
	local script
	if [[ "$1" == partial ]]; then
		script='display notification "Some steps were skipped. Check ~/Library/Logs/memory-daily." with title "Daily memory run: partial"'
	else
		script='display notification "Check ~/Library/Logs/memory-daily." with title "Daily memory run failed" sound name "Basso"'
	fi
	osascript -e "$script" || printf 'WARNING: macOS notification could not be delivered.\n' >&2
}

fail() {
	printf 'FAILED: %s\n' "$1" >&2
	failure_reported=true
	notify failed
	exit "${2:-1}"
}

finish() {
	local status=$?
	if [[ "$status" != 0 && "$failure_reported" == false ]]; then
		printf 'FAILED: wrapper exited with status %s.\n' "$status" >&2
		notify failed
	fi
	if $stream_output; then
		printf 'Final marker: %s\nLog: %s\n' "${final_line:-none (run did not produce a terminal marker)}" "$log_file"
	fi
	[[ -z "$output" ]] || rm -f -- "$output"
	if $owns_lock && [[ "$(cat "$lock_dir/pid" 2>/dev/null)" == "$$" ]]; then
		rm -rf -- "$lock_dir"
	fi
}
memory_daily_run() {
local prompt="$1"
stream_output="${2:-false}"
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$log_dir" "$state_dir"
log_file="$log_dir/$(date +%Y-%m-%d).log"
if $stream_output; then
	exec > >(tee -a "$log_file") 2>&1
else
	exec >>"$log_file" 2>&1
fi
printf '\nSTART: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
# Only the dated ritual logs are rotated; unrelated files are left alone.
find "$log_dir" -type f -name '????-??-??.log' -mtime +29 -delete
command -v python3 >/dev/null 2>&1 || fail 'python3 is required for read-only preflight and locking.'

# launchd does not source .zshrc/nvm. Prefer nvm's concrete default, otherwise
# the newest installed Node version containing Pi, without running shell profiles.
nvm_bin="$(python3 - <<'PY'
import os
from pathlib import Path
root = Path.home() / '.nvm'
candidates = [p / 'bin' for p in (root / 'versions/node').glob('v*')
              if (p / 'bin/pi').is_file() and os.access(p / 'bin/pi', os.X_OK)
              and os.access(p / 'bin/node', os.X_OK)]
def version(path):
    try:
        return tuple(int(n) for n in path.parent.name[1:].split('.'))
    except ValueError:
        return ()
alias = root / 'alias/default'
default = root / 'versions/node' / alias.read_text().strip() / 'bin' if alias.is_file() else None
print(default if default in candidates else max(candidates, key=version) if candidates else '')
PY
)"
[[ -z "$nvm_bin" ]] || export PATH="$HOME/.local/bin:$nvm_bin:$PATH"
command -v pi >/dev/null 2>&1 || fail 'pi is not on PATH; install and authenticate Pi first.'

# mkdir is the run lock. The short flock guard serializes stale recovery so two
# contenders cannot remove a newly acquired lock. Live owners are never displaced.
if RUN_PID="$$" python3 - "$state_dir" <<'PY'
import fcntl
import os
import shutil
import sys
import time
from pathlib import Path
state = Path(sys.argv[1])
lock = state / 'run.lock'
with (state / '.lock-guard').open('a') as guard:
    fcntl.flock(guard, fcntl.LOCK_EX)
    if lock.exists():
        if time.time() - lock.stat().st_mtime < 3 * 60 * 60:
            sys.exit(2)
        try:
            pid = int((lock / 'pid').read_text())
        except (OSError, ValueError):
            pid = 0
        if pid > 0:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            except PermissionError:
                sys.exit(2)
            else:
                sys.exit(2)
        shutil.rmtree(lock)
    lock.mkdir(mode=0o700)
    (lock / 'pid').write_text(os.environ['RUN_PID'] + '\n')
PY
then
	owns_lock=true
else
	lock_status=$?
	if [[ "$lock_status" == 2 ]]; then
		printf 'SKIPPED: another run owns the lock (abandoned locks expire after 3h).\n'
		exit 0
	fi
	fail 'could not acquire the run lock.'
fi

[[ -d "$HOME/source/DailyDriver" && -e "$HOME/source/DailyDriver/.git" ]] || fail 'DailyDriver checkout is missing at ~/source/DailyDriver.'
# Read config only: no pi mcp list, server startup, auth probe or config mutation.
if ! python3 - <<'PY'
import json
from pathlib import Path
home = Path.home()
servers = {}
for relative in ('.config/mcp/mcp.json', '.pi/agent/mcp.json', '.pi/agent/mcp-adapter.json'):
    path = home / relative
    if not path.exists():
        continue
    try:
        config = json.loads(path.read_text())
        entries = config.get('mcpServers', {})
        if not isinstance(entries, dict):
            raise ValueError()
        servers.update(entries)
    except (OSError, ValueError, AttributeError):
        print('Preflight: invalid MCP registry (values withheld).')
        raise SystemExit(1)
for name in ('memory', 'm365-personal-productivity'):
    entry = servers.get(name)
    if not isinstance(entry, dict) or not any(isinstance(entry.get(k), str) and entry[k].strip() for k in ('command', 'url')):
        print(f'Preflight: missing/invalid {name} registration (auth/health not checked).')
        raise SystemExit(1)
PY
then
	fail 'memory and m365 must be registered in Pi; see MCP/README.md.'
fi

cd "$state_dir"
output="$(mktemp "$state_dir/output.XXXXXX")"
args=(-p --no-session)
[[ -z "${MEMORY_DAILY_MODEL:-}" ]] || args+=(--model "$MEMORY_DAILY_MODEL")
pi_status=0
pi "${args[@]}" "$prompt" 2>&1 | tee "$output" || pi_status=$?
final_line="$(sed '/^[[:space:]]*$/d' "$output" | tail -n 1)"
[[ "$final_line" == MEMORY-DAILY:* ]] || final_line=""
[[ "$pi_status" == 0 ]] || fail "Pi/output logging exited with status $pi_status." "$pi_status"
if grep -Eq '^MEMORY-DAILY: FAILED([[:space:]]|$)' "$output"; then
	fail 'the routine reported failure.'
fi
# Inspect this invocation, not earlier runs appended to today's log. The marker
# must be the final non-blank line, so a truncated/crashed run cannot look healthy.
if [[ "$final_line" == 'MEMORY-DAILY: OK' ]]; then
	printf 'COMPLETED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
elif [[ "$final_line" =~ ^MEMORY-DAILY:\ PARTIAL\ [0-9]+\ step\(s\)\ skipped$ ]]; then
	notify partial
else
	fail 'the routine did not end with a valid MEMORY-DAILY marker.'
fi
}
