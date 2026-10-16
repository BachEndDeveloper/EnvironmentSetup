#!/usr/bin/env python3
"""Temporary registry tests; never touches HOME or starts a host."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

helper = Path(__file__).resolve().parent.parent / "MCP/set-pi-protocol.py"
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "mcp.json"
    original = {"unknown": ["preserve"], "mcpServers": {
        "target": {"command": "fixture", "env": {"TOKEN": "synthetic-secret"}, "excludeTools": ["write"]},
        "other": {"url": "https://example.invalid", "auth": "oauth"}}}
    path.write_text(json.dumps(original))
    path.chmod(0o600)

    def run(version, name="target"):
        result = subprocess.run([sys.executable, str(helper), str(path), name, version], capture_output=True, text=True)
        assert "synthetic-secret" not in result.stdout + result.stderr
        return result

    for version in ("auto", "legacy", "2026-07-28"):
        assert run(version).returncode == 0
        expected = json.loads(json.dumps(original))
        expected["mcpServers"]["target"]["protocolVersion"] = version
        assert json.loads(path.read_text()) == expected
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        before = path.read_bytes(), path.stat().st_mtime_ns
        assert run(version).returncode == 0
        assert (path.read_bytes(), path.stat().st_mtime_ns) == before
    for raw in ('{ "synthetic-secret": broken', '{}', '{"mcpServers":{"target":null}}'):
        path.write_text(raw)
        assert run("auto").returncode != 0
        assert path.read_text() == raw
    path.write_text(json.dumps(original))
    before = path.read_bytes()
    assert run("unsupported").returncode != 0
    assert run("auto", "missing").returncode != 0
    assert path.read_bytes() == before
    path.unlink()
    assert run("auto").returncode != 0 and not path.exists()
    assert list(Path(tmp).iterdir()) == []
print("PASS: protocol patch preserves unrelated fields/permissions, is idempotent, fails safely without credential output, and leaves no temporary files")
