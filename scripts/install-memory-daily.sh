#!/usr/bin/env bash
# Scheduling defaults off; preserve prior opt-in and reload only changed jobs.
set -euo pipefail
umask 077
setup_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
mode=install
[[ "${MEMORY_DAILY_ENABLE:-0}" != 1 ]] || mode=enable
if [[ "$#" -gt 1 ]]; then
	echo 'Usage: install-memory-daily.sh [--enable|--disable|--status]' >&2
	exit 1
fi
case "${1:-}" in
	'') ;;
	--enable) mode=enable ;;
	--disable) mode=disable ;;
	--status) mode=status ;;
	--help|-h)
		echo 'Usage: install-memory-daily.sh [--enable|--disable|--status]'
		echo 'Default: preserve scheduling state (off for new installs). MEMORY_DAILY_ENABLE=1 enables it.'
		exit 0 ;;
	*) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
esac

label="$(python3 - <<'PY'
import os
import re
user = re.sub(r'[^a-z0-9-]', '-', os.environ.get('USER', '').lower()).strip('-')
if not user:
    raise SystemExit('ERROR: USER must identify the installing user.')
print(f'local.{user}.memory-daily')
PY
)"
state_dir="$HOME/.local/share/memory-daily"
log_dir="$HOME/Library/Logs/memory-daily"
plist="$HOME/Library/LaunchAgents/$label.plist"
target="gui/$(id -u)/$label"
# Installer-owned opt-in state avoids querying launchd on unchanged installs.
# Use --status for actual loaded state; manage enable/disable through this script.
enabled_file="$state_dir/.enabled"

if [[ "$mode" == status ]]; then
	if launchctl print "$target" >/dev/null 2>&1; then
		echo "$label: loaded (daily 07:30; RunAtLoad=false)."
	else
		echo "$label: unloaded. Enable with: bash scripts/install-memory-daily.sh --enable"
	fi
	exit 0
fi
if [[ "$mode" == disable ]]; then
	if launchctl print "$target" >/dev/null 2>&1; then
		launchctl bootout "$target"
	fi
	# Persist the opt-out across logins; bootout alone would not do that.
	launchctl disable "$target"
	rm -f "$enabled_file"
	echo 'memory-daily: installed, disabled (unloaded) -- enable with scripts/install-memory-daily.sh --enable'
	exit 0
fi

mkdir -p "$state_dir" "$log_dir" "$(dirname "$plist")"
changed=false
if ! cmp -s "$setup_dir/scripts/memory-daily/run.sh" "$state_dir/run.sh"; then
	install -m 700 "$setup_dir/scripts/memory-daily/run.sh" "$state_dir/run.sh"
	changed=true
fi
# Parse the template first, then replace values and serialize: HOME/model values
# are escaped by plistlib, not interpolated into XML or AppleScript.
if python3 - "$setup_dir/scripts/memory-daily/agent.plist" "$plist" "$label" <<'PY'
import os
import plistlib
import sys
from pathlib import Path
home = Path.home()
state = home / '.local/share/memory-daily'
values = {
    '@LABEL@': sys.argv[3],
    '@HOME@': str(home),
    '@RUN_SCRIPT@': str(state / 'run.sh'),
    '@STATE_DIR@': str(state),
    '@LOG_DIR@': str(home / 'Library/Logs/memory-daily'),
    '@PATH@': f'{home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
}
def expand(value):
    if isinstance(value, str):
        for token, replacement in values.items():
            value = value.replace(token, replacement)
        return value
    if isinstance(value, dict):
        return {key: expand(item) for key, item in value.items()}
    if isinstance(value, list):
        return [expand(item) for item in value]
    return value
config = expand(plistlib.loads(Path(sys.argv[1]).read_bytes()))
if os.environ.get('MEMORY_DAILY_MODEL'):
    config['EnvironmentVariables']['MEMORY_DAILY_MODEL'] = os.environ['MEMORY_DAILY_MODEL']
content = plistlib.dumps(config, sort_keys=False)
path = Path(sys.argv[2])
if path.exists() and path.read_bytes() == content:
    raise SystemExit(0)
temporary = path.with_suffix('.plist.tmp')
temporary.write_bytes(content)
temporary.chmod(0o600)
temporary.replace(path)
raise SystemExit(2)  # Changed; reload only if the job was explicitly enabled.
PY
then
	:
else
	render_status=$?
	[[ "$render_status" == 2 ]] || exit "$render_status"
	changed=true
fi

if [[ "$mode" == enable || -e "$enabled_file" ]]; then
	if $changed || [[ ! -e "$enabled_file" ]]; then
		launchctl enable "$target"
		if launchctl print "$target" >/dev/null 2>&1; then
			launchctl bootout "$target"
		fi
		launchctl bootstrap "gui/$(id -u)" "$plist"
		: >"$enabled_file"
	fi
	echo 'memory-daily: enabled (07:30; RunAtLoad=false)'
else
	echo "Installed $state_dir/run.sh and $plist. No launchctl call made."
	echo 'To run once by hand (does not enable scheduling):'
	# shellcheck disable=SC2016 # Print the command for the operator's shell.
	echo '  bash "$HOME/.local/share/memory-daily/run.sh"'
	echo 'memory-daily: installed, disabled -- enable with scripts/install-memory-daily.sh --enable'
fi
