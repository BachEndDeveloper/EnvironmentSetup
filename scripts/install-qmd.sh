#!/usr/bin/env bash
# qmd is only a local ranking engine behind memory-mcp, never a host MCP server.
set -euo pipefail
QMD_VERSION=2.8.3
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$script_dir/qmd-install.py" "$QMD_VERSION" "$@"
