#!/usr/bin/env node
// Opt-in integration against an installed pi-mcp-adapter, no server starts.
// Usage: node scripts/test-pi-adapter-protocol.mjs /path/to/pi-mcp-adapter/dist/config.js
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

if (!process.argv[2]) throw new Error('Pass the installed adapter dist/config.js path');
const modulePath = path.resolve(process.argv[2]);
const helper = new URL('../MCP/set-pi-protocol.py', import.meta.url);
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'adapter-protocol-'));
try {
    process.env.HOME = root;
    process.env.PI_CODING_AGENT_DIR = path.join(root, '.pi/agent');
    process.env.XDG_CONFIG_HOME = path.join(root, '.config');
    const dir = process.env.PI_CODING_AGENT_DIR;
    fs.mkdirSync(dir, { recursive: true });
    const native = path.join(dir, 'mcp.json');
    const overlay = path.join(dir, 'mcp-adapter.json');
    fs.writeFileSync(native, JSON.stringify({ mcpServers: {
        fixture: { command: '/synthetic/node', args: ['fixture.js'], env: { TEST: 'synthetic' }, protocolVersion: 'auto' }
    }}));
    const { setPiMcpConfigEnabled, loadMcpConfig, translatePiMcpServer } = await import(pathToFileURL(modulePath));
    setPiMcpConfigEnabled(true);
    // Prove the regression: the native importer drops this adapter-only field.
    const translated = translatePiMcpServer('fixture', JSON.parse(fs.readFileSync(native)).mcpServers.fixture);
    assert.equal(translated.entry.protocolVersion, undefined);
    assert.ok(translated.ignored.includes('protocolVersion'));
    for (const version of ['auto', 'legacy', '2026-07-28', '']) {
        execFileSync('python3', [helper.pathname, native, overlay, 'fixture', version]);
        const effective = loadMcpConfig(undefined, root).mcpServers.fixture;
        assert.equal(effective.protocolVersion, version || undefined);
        assert.equal(effective.command, '/synthetic/node');
        assert.deepEqual(effective.args, ['fixture.js']);
        assert.deepEqual(effective.env, { TEST: 'synthetic' });
        assert.equal(JSON.parse(fs.readFileSync(native)).mcpServers.fixture.protocolVersion, undefined);
    }
    console.log('PASS: installed adapter drops native protocolVersion; helper-produced partial overrides resolve auto/legacy/pinned/omitted correctly and inherit command/args/env; no servers launched');
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
