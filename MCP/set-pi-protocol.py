#!/usr/bin/env python3
"""Set one adapter-only protocolVersion after pi mcp add (no secret output)."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def main():
    if len(sys.argv) != 4 or sys.argv[3] not in ("legacy", "auto", "2026-07-28"):
        raise ValueError("invalid arguments")
    path, name, version = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    # Refuse malformed/missing registries or entries instead of replacing them.
    data = json.loads(path.read_text())
    entry = data["mcpServers"][name]
    if not isinstance(entry, dict):
        raise ValueError("invalid entry")
    if entry.get("protocolVersion") == version:
        return
    entry["protocolVersion"] = version
    mode = stat.S_IMODE(path.stat().st_mode)
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


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError):
        # Registry contents and JSON parse exceptions can contain credentials.
        print("ERROR: could not set Pi protocolVersion; registry left unchanged.", file=sys.stderr)
        sys.exit(1)
