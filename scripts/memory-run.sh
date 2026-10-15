#!/usr/bin/env bash
# On-demand only: reading status or running once never enables a schedule.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { echo 'Usage: memory-run.sh daily|catch-up|status [--model provider/id]'; }
mode="${1:-}"
case "$mode" in
	daily|catch-up|status) shift ;;
	--help|-h) usage; exit 0 ;;
	*) usage >&2; exit 1 ;;
esac
if [[ "$#" -gt 0 ]]; then
	if [[ "$#" != 2 || "$1" != --model || -z "$2" || "$2" == -* ]]; then
		usage >&2
		exit 1
	fi
	export MEMORY_DAILY_MODEL="$2"
fi
# The library is adjacent to the launchd entry point in source and deployment.
common="$script_dir/memory-daily/common.sh"
[[ -f "$common" ]] || common="$script_dir/common.sh"
# shellcheck source=scripts/memory-daily/common.sh
source "$common"

if [[ "$mode" == status ]]; then
	# Treat log content as data, never as shell input. Only the latest attempt's
	# summary is shown, so a failed/truncated run cannot inherit an earlier OK.
	python3 - "$log_dir" <<'PY'
import sys
from pathlib import Path
logs = sorted(Path(sys.argv[1]).glob('????-??-??.log'))
if not logs:
    print('Latest run: no dated log found.')
else:
    latest = logs[-1]
    print(f'Log: {latest}')
    lines = latest.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith('START: ')]
    attempt = lines[starts[-1]:] if starts else lines
    summaries = [i for i, line in enumerate(attempt) if line.startswith('Memory daily ')]
    if summaries:
        for line in attempt[summaries[-1]:]:
            if line.startswith(('MEMORY-DAILY:', 'COMPLETED:', 'FAILED:', 'Final marker:', 'Log:')):
                break
            if line.strip() not in ('```', '```text'):
                print(line)
    else:
        print('Summary: unavailable for latest attempt.')
    markers = [line for line in attempt if line.startswith('MEMORY-DAILY:')]
    failures = [line for line in attempt if line.startswith('FAILED:')]
    print(markers[-1] if markers else 'Final marker: unavailable for latest attempt.')
    if failures:
        print(failures[-1])
PY
	status=0
	bash "$script_dir/install-memory-daily.sh" --status || status=$?
	bash "$script_dir/install-qmd.sh" --check || status=$?
	exit "$status"
fi
prompt='Run the memory-daily skill.'
[[ "$mode" != catch-up ]] || prompt='run memory-daily catch-up'
memory_daily_run "$prompt" true
