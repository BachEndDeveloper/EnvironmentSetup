#!/usr/bin/env python3
"""Exercise the real launcher with fake Node binaries in a temporary HOME."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

launcher = Path(__file__).resolve().parent.parent / "MCP/mcp-node"
with tempfile.TemporaryDirectory(prefix="mcp-launcher-") as tmp:
    home = Path(tmp) / "home with spaces"
    nvm = home / ".nvm"
    (nvm / "alias").mkdir(parents=True)
    versions = nvm / "versions/node"
    probe = "#!/usr/bin/python3\nimport json,os,sys\nprint(json.dumps({'binary':sys.argv[0], 'args':sys.argv[1:], 'path':os.environ['PATH']}))\n"

    def binary(path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(probe)
        path.chmod(0o755)
        return path

    nodes = {v: binary(versions / v / "bin/node") for v in ("v24.9.0", "v24.21.0", "v25.1.0")}
    fallback = binary(home / "fallback/node")
    alias = nvm / "alias/default"
    alias.write_text("v25.1.0\n")
    env = dict(os.environ, HOME=str(home), NVM_DIR=str(nvm), PATH=f"{fallback.parent}:/usr/bin:/bin")
    env.pop("MCP_NODE_MAJOR", None)

    def run(major=None):
        return subprocess.run(["/bin/bash", str(launcher), "fixture.js", "argument with spaces", "--flag"],
                              env=env | ({"MCP_NODE_MAJOR": major} if major is not None else {}),
                              capture_output=True, text=True)

    def expect(path, major=None):
        result = run(major)
        assert result.returncode == 0, result.stderr
        assert result.stderr == ""
        value = json.loads(result.stdout)
        assert value["binary"] == str(path), value
        assert value["args"] == ["fixture.js", "argument with spaces", "--flag"]
        assert value["path"].startswith(f"{home}/.local/bin:{path.parent}:")

    expect(nodes["v24.21.0"], "24")  # Numeric patch order, not lexical; ignore default/newer major.
    expect(nodes["v25.1.0"])
    for invalid in ("24;echo bad", "v24", "24.0", " "):
        result = run(invalid)
        assert result.returncode != 0 and not result.stdout
        assert "numeric Node major" in result.stderr
    result = run("99")
    assert result.returncode != 0 and not result.stdout and "refusing fallback" in result.stderr
    nodes["v24.21.0"].chmod(0o644)
    result = run("24")
    assert result.returncode != 0 and not result.stdout  # Never silently use a different Node.
    alias.write_text("missing-version\n")
    expect(nodes["v25.1.0"])
    alias.unlink()
    expect(nodes["v25.1.0"])
    for path in nodes.values():
        path.unlink()
    expect(fallback)
print("PASS: Node-major pin, numeric patch selection, default/stale alias, PATH fallback, argument/PATH preservation, and fail-closed errors; no real Node launched")
