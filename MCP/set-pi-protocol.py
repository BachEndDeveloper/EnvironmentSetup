#!/usr/bin/env python3
"""Keep protocol policy in adapter overrides, never in Pi's native registry."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def save(path, data):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as out:
            temporary = out.name
            os.chmod(temporary, mode)
            json.dump(data, out, indent=2)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if len(sys.argv) != 5 or sys.argv[4] not in ("", "legacy", "auto", "2026-07-28"):
        raise ValueError("invalid arguments")
    native_path, adapter_path = map(Path, sys.argv[1:3])
    name, version = sys.argv[3:5]
    if native_path.resolve() == adapter_path.resolve():
        raise ValueError("distinct registries required")
    native = json.loads(native_path.read_text())
    entry = native["mcpServers"][name]
    if not isinstance(entry, dict):
        raise ValueError("invalid native entry")
    adapter = json.loads(adapter_path.read_text()) if adapter_path.exists() else {}
    if not isinstance(adapter, dict):
        raise ValueError("invalid adapter config")
    servers = adapter.get("mcpServers", {})
    if not isinstance(servers, dict):
        raise ValueError("invalid adapter server map")
    override = servers.get(name, {})
    if not isinstance(override, dict):
        raise ValueError("invalid adapter entry")
    # Validate both documents before writing either. Do not copy command/env/auth.
    before = json.dumps(adapter, sort_keys=True)
    if version:
        override["protocolVersion"] = version
        servers[name] = override
        adapter["mcpServers"] = servers
    else:
        override.pop("protocolVersion", None)
        if not override:
            servers.pop(name, None)
    if json.dumps(adapter, sort_keys=True) != before:
        save(adapter_path, adapter)
    if "protocolVersion" in entry:
        del entry["protocolVersion"]
        save(native_path, native)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError):
        # JSON exceptions can contain credentials. Never print their details.
        print("ERROR: could not reconcile Pi protocol policy; check registry structure (values withheld).", file=sys.stderr)
        sys.exit(1)
