#!/usr/bin/env python3
"""Synthetic registry tests; never uses real HOME or starts a host."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

helper = Path(__file__).resolve().parent.parent / "MCP/set-pi-protocol.py"
with tempfile.TemporaryDirectory() as tmp:
    native, adapter = Path(tmp) / "mcp.json", Path(tmp) / "mcp-adapter.json"
    original = {"unknown": ["preserve"], "mcpServers": {
        "target": {"command": "fixture", "env": {"TOKEN": "synthetic-secret"}, "protocolVersion": "auto"},
        "other": {"url": "https://example.invalid", "auth": "oauth"}}}
    native.write_text(json.dumps(original))
    native.chmod(0o600)

    def run(version, name="target"):
        result = subprocess.run([sys.executable, str(helper), str(native), str(adapter), name, version], capture_output=True, text=True)
        assert "synthetic-secret" not in result.stdout + result.stderr
        return result

    for version in ("auto", "legacy", "2026-07-28"):
        assert run(version).returncode == 0
        expected = json.loads(json.dumps(original))
        del expected["mcpServers"]["target"]["protocolVersion"]
        assert json.loads(native.read_text()) == expected
        assert json.loads(adapter.read_text()) == {"mcpServers": {"target": {"protocolVersion": version}}}
        assert stat.S_IMODE(adapter.stat().st_mode) == 0o600
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (native, adapter)]
        assert run(version).returncode == 0
        assert [(p.read_bytes(), p.stat().st_mtime_ns) for p in (native, adapter)] == before
    overlay = {"settings": {"test": True}, "mcpServers": {"other": {"excludeTools": ["write"]}, "target": {"protocolVersion": "auto", "requestTimeoutMs": 1234}}}
    adapter.write_text(json.dumps(overlay))
    adapter.chmod(0o640)
    assert run("").returncode == 0
    del overlay["mcpServers"]["target"]["protocolVersion"]
    assert json.loads(adapter.read_text()) == overlay
    assert stat.S_IMODE(adapter.stat().st_mode) == 0o640
    assert run("auto").returncode == 0
    assert run("").returncode == 0
    # A protocol-only entry is deleted when manifest policy is omitted.
    adapter.write_text('{"mcpServers":{"target":{"protocolVersion":"auto"}}}')
    assert run("").returncode == 0
    assert json.loads(adapter.read_text()) == {"mcpServers": {}}
    for raw in ('{ "synthetic-secret": broken', '[]', '{"mcpServers":[]}', '{"mcpServers":{"target":null}}'):
        adapter.write_text(raw)
        before = native.read_bytes(), adapter.read_bytes()
        assert run("auto").returncode != 0
        assert (native.read_bytes(), adapter.read_bytes()) == before
    adapter.unlink()
    before = native.read_bytes()
    assert run("unsupported").returncode != 0
    assert run("auto", "missing").returncode != 0
    assert native.read_bytes() == before and not adapter.exists()
    native.write_text('{"synthetic-secret":broken')
    assert run("auto").returncode != 0 and not adapter.exists()
    native.unlink()
    assert run("auto").returncode != 0
    assert list(Path(tmp).iterdir()) == []
print("PASS: protocol overrides isolated in adapter registry; native cleanup, preservation, permissions, idempotence, omitted-policy cleanup and malformed-input safety")
