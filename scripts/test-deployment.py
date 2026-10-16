#!/usr/bin/env python3
"""Sandbox deployment logic with synthetic fixtures and mocked git/npm/Pi/Claude.

Usage: python3 scripts/test-deployment.py /path/to/AI-Skills
Never starts a host, downloads a package, creates a Git tag, or uses the real HOME.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MOCK = r'''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
home = Path(os.environ["HOME"])
assert home.parent.name.startswith("l1-deployment-")
command = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(home.parent / "calls.jsonl", "a") as f:
    f.write(json.dumps([command, args]) + "\n")
def read(path):
    return json.loads(path.read_text()) if path.exists() else {}
def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
def source(package):
    return package if isinstance(package, str) else package["source"]
def normalized(value):
    return os.path.realpath(os.path.join(home / ".pi/agent", os.path.expanduser(value)))
if command == "git":
    if args[0] == "clone":
        failure = os.environ.get("TEST_CLONE_ERROR")
        ssh = args[1].startswith(("git@", "ssh://"))
        if ssh and failure:
            print(failure, file=sys.stderr)
            sys.exit(128)
        if args[1].startswith("https:") and os.environ.get("TEST_FAIL_HTTPS_CLONE"):
            assert os.environ.get("GIT_TERMINAL_PROMPT") == "0"
            print("fatal: Authentication failed for HTTPS", file=sys.stderr)
            sys.exit(128)
        path = Path(args[-1]); (path / ".git").mkdir(parents=True)
        (path / ".branch").write_text("initial-clone")
        if "AI-Skills" in args[1]:
            shutil.copytree(os.environ["TEST_SKILLS_SOURCE"] + "/scripts", path / "scripts")
            (path / "skills/example").mkdir(parents=True)
            (path / "skills/example/SKILL.md").write_text("# Synthetic fixture\n")
        else:
            (path / "dist").mkdir(); (path / "dist/index.js").write_text("// fixture\n")
            (path / "skills/m365-tools").mkdir(parents=True)
            (path / "skills/m365-tools/SKILL.md").write_text("# Fixture\n")
        sys.exit(0)
    assert args[0] == "-C"
    path = Path(args[1]); operation = args[2]
    if operation == "symbolic-ref":
        if (path / ".branch").exists(): print("development"); sys.exit(0)
        sys.exit(1)
    if operation == "status":
        if (path / ".dirty").exists(): print(" M fixture")
    elif operation == "tag":
        if not os.environ.get("TEST_NO_TAGS"): print("v0.6.2\nv0.10.0\nv999.0.0-rc.1")
    elif operation == "describe":
        print((path / ".ref").read_text() if (path / ".ref").exists() else "v0.10.0")
    elif operation == "checkout":
        if os.environ.get("TEST_FAIL_CHECKOUT"): sys.exit(1)
        (path / ".branch").unlink(missing_ok=True)
        (path / ".ref").write_text(args[-1])
    elif operation != "fetch":
        raise RuntimeError("unmocked git operation")
elif command == "pi":
    path = home / ".pi/agent/settings.json"; cfg = read(path)
    if args[0] == "install":
        if os.environ.get("TEST_FAIL_INSTALL"): sys.exit(1)
        packages = cfg.setdefault("packages", [])
        if not any(normalized(source(p)) == normalized(args[1]) for p in packages):
            packages.append(os.path.relpath(args[1], path.parent))
        write(path, cfg)
    elif args[0] == "remove":
        cfg["packages"] = [p for p in cfg.get("packages", []) if normalized(source(p)) != normalized(args[1])]
        write(path, cfg)
    elif args[:2] in (["mcp", "add"], ["mcp", "remove"]):
        if args[1] == "add" and os.environ.get("TEST_FAIL_PI_MCP"): sys.exit(1)
        path = home / ".pi/agent/mcp.json"; cfg = read(path); servers = cfg.setdefault("mcpServers", {})
        name = args[2]
        if args[1] == "remove": servers.pop(name, None)
        else:
            entry = {}
            if "--url" in args: entry["url"] = args[args.index("--url") + 1]
            else:
                index = args.index("--"); entry = {"command": args[index + 1], "args": args[index + 2:]}
                env = dict(args[i + 1].split("=", 1) for i, a in enumerate(args) if a == "--env")
                if env: entry["env"] = env
            if "--description" in args: entry["description"] = args[args.index("--description") + 1]
            servers[name] = entry
        write(path, cfg)
    else: raise RuntimeError("unmocked pi operation")
elif command == "claude":
    if args[:2] == ["mcp", "add-json"] and os.environ.get("TEST_FAIL_CLAUDE_MCP"): sys.exit(1)
    path = home / ".claude.json"; cfg = read(path); servers = cfg.setdefault("mcpServers", {})
    if args[:2] == ["mcp", "remove"]: servers.pop(args[2], None)
    elif args[:2] == ["mcp", "add-json"]: servers[args[2]] = json.loads(args[3])
    else: raise RuntimeError("unmocked claude operation")
    write(path, cfg)
elif command not in ("node", "npm", "npx"):
    raise RuntimeError("unmocked command")
'''


def main():
    skills = Path(sys.argv[1]).resolve()
    setup_source = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="l1-deployment-") as temporary:
        root = Path(temporary).resolve()
        home = root / "home"
        home.mkdir()
        setup = root / "setup"
        for name in ("scripts", "MCP"):
            shutil.copytree(setup_source / name, setup / name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for name in ("git", "pi", "claude", "node", "npm", "npx"):
            executable = bin_dir / name
            executable.write_text(MOCK)
            executable.chmod(0o755)
        env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:/usr/bin:/bin:/opt/homebrew/bin", TEST_SKILLS_SOURCE=str(skills), TMPDIR=str(root))
        # Do not inherit live config/credentials or deployment overrides.
        for key in list(env):
            if key.startswith(("AI_SKILLS_", "M365_", "TEST_FAIL_", "TEST_NO_", "TEST_CLONE_")) or key in ("CLAUDE_SKILLS_DIR", "M365_TOOLS_DIR", "PI_CODING_AGENT_DIR"):
                del env[key]

        def run(script, *args, success=True, extra=None):
            result = subprocess.run(["bash", str(script), *args], env=env | (extra or {}), capture_output=True, text=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result.stdout + result.stderr

        def write(path, data):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data, indent=2) + "\n")

        def snapshot():
            return {str(p.relative_to(home)): p.read_bytes() for p in home.rglob("*") if p.is_file() and not p.is_symlink()}

        pi_settings = home / ".pi/agent/settings.json"
        write(pi_settings, {"packages": ["npm:pi-mcp-adapter", "../../source/AI-Skills", {"source": "~/source/AI-Skills", "skills": ["./skills"]}], "extensions": ["-builtin:mcp"]})
        old_skill = home / ".claude/skills/example"
        old_skill.parent.mkdir(parents=True)
        old_skill.symlink_to(home / "source/AI-Skills/skills/example")
        unrelated = old_skill.parent / "unrelated"
        unrelated.write_text("preserve me")
        deploy = setup / "scripts/install-ai-skills.sh"
        output = run(deploy)
        assert "latest -> v0.10.0" in output
        deployed = home / ".local/share/ai-skills"
        assert old_skill.resolve() == deployed / "skills/example"
        assert unrelated.read_text() == "preserve me"
        packages = json.loads(pi_settings.read_text())["packages"]
        assert packages == ["npm:pi-mcp-adapter", "../../.local/share/ai-skills"]
        before = snapshot()
        assert "0 change(s)." in run(deploy)
        assert snapshot() == before
        print("PASS: install-ai-skills/install-local migrate relative and object packages, relink and repeat idempotently")

        def clone_calls():
            return [args for command, args in
                    (json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines())
                    if command == "git" and args[0] == "clone"]

        assert clone_calls() == [["clone", "git@github.com:BachEndDeveloper/AI-Skills.git", str(deployed)]]
        helper = setup / "scripts/git-clone-with-https-fallback.sh"
        ssh_error = "git@github.com: Permission denied (publickey)."
        for index, repo in enumerate(("git@github.com:fixture/sample.git", "ssh://git@github.com/fixture/sample.git")):
            target = home / f"helper-fallback-{index}"
            before_calls = len(clone_calls())
            output = run(helper, repo, str(target), extra={"TEST_CLONE_ERROR": ssh_error})
            assert "retrying the same repository over HTTPS" in output
            assert clone_calls()[before_calls:] == [["clone", repo, str(target)],
                                                    ["clone", "https://github.com/fixture/sample.git", str(target)]]
        for index, error in enumerate(("Host key verification failed.", "Could not resolve hostname github.com", "Repository not found.")):
            target = home / f"helper-no-retry-{index}"
            before_calls = len(clone_calls())
            run(helper, "git@github.com:fixture/sample.git", str(target), success=False,
                extra={"TEST_CLONE_ERROR": error})
            assert len(clone_calls()) == before_calls + 1 and not target.exists()
        target = home / "helper-https-failure"
        run(helper, "git@github.com:fixture/sample.git", str(target), success=False,
            extra={"TEST_CLONE_ERROR": ssh_error, "TEST_FAIL_HTTPS_CLONE": "1"})
        assert not target.exists()
        # Non-GitHub remotes are never redirected to another host.
        before_calls = len(clone_calls())
        run(helper, "git@example.invalid:fixture/sample.git", str(home / "other-host"), success=False,
            extra={"TEST_CLONE_ERROR": ssh_error})
        assert len(clone_calls()) == before_calls + 1
        print("PASS: SSH succeeds without HTTPS; both GitHub SSH forms retry auth failures only; host-key/DNS/missing-repo/other-host failures never downgrade; HTTPS failures propagate")

        # Default source is the deployment even when the script is invoked from development.
        before = snapshot()
        assert "0 change(s)." in run(skills / "scripts/link-claude-code.sh")
        assert snapshot() == before
        alternate = home / "custom-deployment"
        shutil.copytree(deployed, alternate)
        run(skills / "scripts/link-claude-code.sh", "--apply", extra={"AI_SKILLS_DIR": str(alternate)})
        assert old_skill.resolve() == alternate / "skills/example"
        run(skills / "scripts/link-claude-code.sh", "--apply")
        print("PASS: link-claude-code default dry run is read-only; configurable deployed path works")

        (deployed / ".branch").write_text("development")
        assert "refusing" in run(deploy, success=False).lower()
        run(skills / "scripts/install-local.sh", success=False)
        run(skills / "scripts/link-claude-code.sh", success=False)
        (deployed / ".branch").unlink()
        (deployed / ".dirty").write_text("dirty")
        run(deploy, success=False)
        run(skills / "scripts/install-local.sh", success=False)
        run(skills / "scripts/link-claude-code.sh", success=False)
        (deployed / ".dirty").unlink()
        run(deploy, success=False, extra={"AI_SKILLS_DIR": str(home / "source/AI-Skills")})
        run(deploy, success=False, extra={"TEST_NO_TAGS": "1"})
        run(deploy, success=False, extra={"AI_SKILLS_REF": "main"})
        run(deploy, extra={"AI_SKILLS_REF": "v0.6.2"})
        assert (deployed / ".ref").read_text() == "v0.6.2"
        run(deploy, success=False, extra={"TEST_FAIL_CHECKOUT": "1"})
        write(pi_settings, {"packages": ["../../source/AI-Skills"]})
        before = snapshot()
        run(skills / "scripts/install-local.sh", success=False, extra={"TEST_FAIL_INSTALL": "1"})
        assert snapshot() == before
        # Known old release script installs correctly but does not remove the dev package.
        (deployed / "scripts/install-local.sh").write_text('#!/usr/bin/env bash\nset -e\npi install "$(cd "$(dirname "$0")/.." && pwd)"\n')
        run(deploy)
        assert json.loads(pi_settings.read_text())["packages"] == ["../../.local/share/ai-skills"]
        retry_dir = home / "retry-deployment"
        run(deploy, success=False, extra={"AI_SKILLS_DIR": str(retry_dir), "TEST_NO_TAGS": "1"})
        assert not (retry_dir / ".branch").exists()
        run(deploy, extra={"AI_SKILLS_DIR": str(retry_dir)})
        run(deploy)
        print("PASS: branch/dirty/source/no-tag/pin/failure guards; old-release migration fallback; no-release clone retry")

        fallback_deploy = home / "https-skills"
        before_calls = len(clone_calls())
        output = run(deploy, extra={"AI_SKILLS_DIR": str(fallback_deploy), "TEST_CLONE_ERROR": ssh_error})
        assert "latest -> v0.10.0" in output and (fallback_deploy / ".ref").read_text() == "v0.10.0"
        assert clone_calls()[before_calls:] == [
            ["clone", "git@github.com:BachEndDeveloper/AI-Skills.git", str(fallback_deploy)],
            ["clone", "https://github.com/BachEndDeveloper/AI-Skills.git", str(fallback_deploy)]]
        run(deploy)
        failed_deploy = home / "failed-https-skills"
        run(deploy, success=False, extra={"AI_SKILLS_DIR": str(failed_deploy),
                                         "TEST_CLONE_ERROR": ssh_error, "TEST_FAIL_HTTPS_CLONE": "1"})
        assert not failed_deploy.exists()
        print("PASS: AI-Skills installer uses same-repo HTTPS fallback and release/deployment rules; failed HTTPS clone aborts safely")

        manifest_path = setup / "MCP/servers.json"
        manifest = json.loads(manifest_path.read_text())
        assert len(manifest["servers"]) == 6
        local = [s for s in manifest["servers"] if s.get("type") == "machine-local"]
        doctor = setup / "MCP/install-mcp-servers.sh"
        before = snapshot()
        output = run(doctor, "--check-machine-local", success=False)
        assert all(s["name"] in output for s in local)
        assert "MANUAL:" in output and snapshot() == before
        for reference in {s["configFile"] for s in local}:
            path = Path(reference.replace("$HOME", str(home)))
            entries = {s["name"]: {("url" if s["transport"] == "remote" else "command"): "synthetic-private-sentinel", "auth": "oauth", "excludeTools": ["synthetic-write"], "args": ["--block-tools", "synthetic-write"]} for s in local if s["configFile"] == reference}
            write(path, {"mcpServers": entries, "unrelated": "keep"})
        output = run(doctor, "--check-machine-local")
        assert "synthetic-private-sentinel" not in output
        shared_path = home / ".config/mcp/mcp.json"
        shared_before = shared_path.read_bytes()
        pi_path = home / ".pi/agent/mcp.json"
        local_before = json.loads(pi_path.read_text())["mcpServers"].copy()
        write(home / ".claude.json", {"projects": {"synthetic": "keep"}, "mcpServers": {"m365": {"command": "old"}}})
        before_calls = len(clone_calls())
        run(doctor, extra={"TEST_CLONE_ERROR": ssh_error})
        git_servers = [s for s in manifest["servers"] if s.get("type", "git") == "git"]
        expected = []
        for server in git_servers:
            target = server["dir"].replace("$HOME", str(home))
            expected += [["clone", server["repo"], target],
                         ["clone", server["repo"].replace("git@github.com:", "https://github.com/"), target]]
        assert clone_calls()[before_calls:] == expected
        print("PASS: MCP installer retries each managed Git server over HTTPS after SSH authentication failure")
        before = snapshot()
        output = run(doctor)
        assert "already up to date" in output and snapshot() == before
        assert shared_path.read_bytes() == shared_before
        registrations = json.loads(pi_path.read_text())["mcpServers"]
        assert all(registrations[name] == entry for name, entry in local_before.items())
        assert set(registrations) == {"confluent", "atlassian", "memory", "m365-personal-productivity"}
        for name in ("memory", "m365-personal-productivity"):
            assert registrations[name]["protocolVersion"] == "auto"
        for path in (home / ".claude.json", home / "Library/Application Support/Claude/claude_desktop_config.json"):
            assert all("protocolVersion" not in e for e in json.loads(path.read_text())["mcpServers"].values())
        assert not (home / ".pi/agent/mcp-adapter.json").exists()
        all_names = list(registrations) + list(json.loads(shared_path.read_text())["mcpServers"])
        assert all(all_names.count(s["name"]) == 1 for s in manifest["servers"])
        code = json.loads((home / ".claude.json").read_text())
        assert code["projects"] == {"synthetic": "keep"}
        desktop = json.loads((home / "Library/Application Support/Claude/claude_desktop_config.json").read_text())["mcpServers"]
        # Memory's reviewed host widening changes Desktop only, not Claude Code.
        assert "memory" not in code["mcpServers"]
        assert desktop["memory"]["command"] == str(home / ".local/bin/mcp-node")
        assert desktop["memory"]["args"] == [str(home / ".local/share/mcp/memory-mcp/dist/index.js")]
        assert desktop["memory"]["env"] == registrations["memory"]["env"]
        assert desktop["memory"]["env"]["MEMORY_ALLOW_WRITE"] == "true"
        assert desktop["memory"]["env"]["MEMORY_REMOTE_ALLOWED"] == "private-github"
        assert desktop["memory"]["env"]["MEMORY_REPO"] == str(home / "source/DailyDriver")
        for entry in (desktop["m365-personal-productivity"], code["mcpServers"]["m365-personal-productivity"], registrations["m365-personal-productivity"]):
            assert entry["env"]["MCP_NODE_MAJOR"] == "24"
        print("PASS: six declarations; memory Desktop registration preserves write/remote policy without adding Code; M365 pins Node 24 on all hosts; local OAuth/restrictions preserved")

        output = run(doctor, extra={"M365_TENANT_ID": "synthetic-sensitive-sentinel", "TEST_FAIL_PI_MCP": "1", "TEST_FAIL_CLAUDE_MCP": "1"})
        assert "synthetic-sensitive-sentinel" not in output and "values withheld" in output
        run(doctor)
        print("PASS: failed host registrations do not print machine-local env values")

        # Legacy rollback, pinned revision, omitted default, and invalid policy.
        memory = next(s for s in manifest["servers"] if s["name"] == "memory")
        for version in ("legacy", "2026-07-28"):
            memory["piProtocolVersion"] = version
            write(manifest_path, manifest)
            run(doctor)
            assert json.loads(pi_path.read_text())["mcpServers"]["memory"]["protocolVersion"] == version
        del memory["piProtocolVersion"]
        write(manifest_path, manifest)
        run(doctor)
        assert "protocolVersion" not in json.loads(pi_path.read_text())["mcpServers"]["memory"]
        before_calls = len((root / "calls.jsonl").read_text().splitlines())
        memory["piProtocolVersion"] = "invalid-sensitive-sentinel"
        write(manifest_path, manifest)
        output = run(doctor)
        assert "invalid piProtocolVersion for memory" in output
        assert "invalid-sensitive-sentinel" not in output
        calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()[before_calls:]]
        assert not any(c[0] == "pi" and c[1][:3] == ["mcp", "add", "memory"] for c in calls)
        memory["piProtocolVersion"] = "auto"
        write(manifest_path, manifest)
        run(doctor)
        print("PASS: Pi protocol auto survives reinstall; legacy/pinned/omitted modes work; invalid values rejected before registration; Claude/local entries unchanged")

        # Exercise generic remote support without committing any remote URL value.
        manifest["servers"].append({"name": "synthetic-remote", "type": "remote", "url": "$TEST_REMOTE_URL", "piProtocolVersion": "auto", "hosts": ["pi", "claude-code", "claude-desktop"]})
        write(manifest_path, manifest)
        output = run(doctor)
        assert "url reference is unset" in output
        output = run(doctor, extra={"TEST_REMOTE_URL": "https://example.invalid/mcp"})
        assert "https://example.invalid" not in output
        assert json.loads(pi_path.read_text())["mcpServers"]["synthetic-remote"] == {"url": "https://example.invalid/mcp", "protocolVersion": "auto"}
        assert "protocolVersion" not in json.loads((home / ".claude.json").read_text())["mcpServers"]["synthetic-remote"]
        desktop = home / "Library/Application Support/Claude/claude_desktop_config.json"
        assert "synthetic-remote" not in json.loads(desktop.read_text())["mcpServers"]
        manifest["servers"][-1]["url"] = "https://example.invalid/not-a-reference"
        write(manifest_path, manifest)
        assert "must be an environment-variable reference" in run(doctor)
        print("PASS: remote URL references register in Pi/Code; unset/literal URLs rejected; Desktop remains manual; no URL values logged")
        print("PASS: all deployment tests used temporary HOME and mocked external commands only")


if __name__ == "__main__":
    main()
