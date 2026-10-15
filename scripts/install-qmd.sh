#!/usr/bin/env bash
# Standalone qmd provisioning; the portable config belongs in the private data repo.
set -euo pipefail
umask 077
QMD_VERSION=2.8.3
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$script_dir/qmd-install.py" "$QMD_VERSION" "$@"
