#!/usr/bin/env bash
# Future launchd entry point; deliberately shares all run guards with memory-run.sh.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/memory-daily/common.sh
source "$script_dir/common.sh"
memory_daily_run 'Run the memory-daily skill.'
