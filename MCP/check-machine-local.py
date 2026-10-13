#!/usr/bin/env python3
"""Check machine-local registry references without emitting their values or probing servers."""
import json
import os
import sys
from pathlib import Path


def check(server):
    name = server["name"]
    reference = server["configFile"]
    if server.get("transport") not in ("remote", "stdio") or server.get("hosts") != ["pi"]:
        print(f"WARNING: {name}: machine-local references require transport remote/stdio and hosts [pi].", file=sys.stderr)
        return False
    if not reference.startswith("$HOME/"):
        print(f"WARNING: {name}: configFile must be a $HOME-relative reference.", file=sys.stderr)
        return False
    path = Path(os.path.expandvars(reference))
    try:
        entry = json.loads(path.read_text()).get("mcpServers", {}).get(name)
        valid = isinstance(entry, dict) and bool(entry.get("url") if server["transport"] == "remote" else entry.get("command"))
    except (OSError, ValueError, AttributeError):
        valid = False
    if not valid:
        print(f"WARNING: {name}: missing/invalid {server['transport']} entry in {reference}.", file=sys.stderr)
        print(f"  MANUAL: {server['manualSetup']}", file=sys.stderr)
        return False
    print(f"  {name}: machine-local {server['transport']} entry present in {reference} (values not displayed; auth/health not checked)")
    return True


if __name__ == "__main__":
    manifest = json.loads(Path(__file__).with_name("servers.json").read_text())
    selected = [s for s in manifest["servers"] if s.get("type") == "machine-local" and (len(sys.argv) == 1 or s["name"] == sys.argv[1])]
    if not selected:
        print("No matching machine-local references.", file=sys.stderr)
        sys.exit(1)
    results = [check(s) for s in selected]
    sys.exit(0 if all(results) else 1)
