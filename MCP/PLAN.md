# MCP provisioning — follow-up plan

Phase F built the provisioning pattern (`servers.json` + `install-mcp-servers.sh`,
see [REVIEW-FINDINGS.md](../REVIEW-FINDINGS.md) finding 8). This plan covers what
came out of using it from the **server side** — the `m365-mcp` repository — on
2026-07-27.

**Nothing here is a redesign.** The pattern holds. These are four concrete
defects and one open decision, ordered by whether they actually break something.

**Status:** drafted 2026-07-27 · items 1 and 2 done on 2026-10-06 (`feat/skills-v0.4.0`); item 3 decided as option (a) and done; item 4 deliberately deferred.

---

## Context the reader will need

`m365-mcp` moved on after Phase F was written:

| Fact | Value |
| --- | --- |
| Repository | `github.com/BachEndDeveloper/m365-mcp` |
| Visibility | **private** |
| Released tags | `v0.1.0`, `v0.2.0`, `v0.3.0` |
| Package / server name | `m365-mcp` (was `m365-personal-productivity`) |
| Documented clone path | `~/source/m365-mcp` |
| Path in `servers.json` | `~/source/m365-personal-productivity-mcp` |

What each tag contains:

- **`v0.1.0`** — portability foundation. **Ships a broken calendar read:**
  `read_resource` on any `calendar:///events/…` URI returns HTTP 400, because the
  `$select` requests `joinWebLink`, which is not a property of the Graph `Event`
  type. The documented search-then-read flow is broken at the second step.
- **`v0.2.0`** — fixes that. Adds calendar times resolved to the local zone,
  `mail:///folders/{idOrName}` reads, and an explicit `order` on email search.
- **`v0.3.0`** — `npm run auth` now offers to submit an admin-consent request for
  the three outstanding scopes after the normal sign-in completes.

---

## 1. Private repository cloned over HTTPS — breaks on a fresh machine

**Severity: high. This is the one that fails silently on the machine this
repository exists to set up.**

```jsonc
// MCP/servers.json
"repo": "https://github.com/BachEndDeveloper/m365-mcp.git"
```

```bash
# 01 - Setup Mac Environment.sh — the AI-Skills precedent
AI_SKILLS_REPO="git@github.com:BachEndDeveloper/AI-Skills.git"
```

`m365-mcp` is **private**. AI-Skills is also private and clones over **SSH** for
exactly this reason — the block even documents the failure mode
(`Permission denied (publickey)` on a machine without a GitHub key).

The HTTPS clone succeeds today only because the developer machine already has
`credential.helper=osxkeychain` populated. The setup script performs no
`gh auth login` and configures no credential helper, so on a genuinely fresh
machine this clone prompts for credentials or fails outright — and the
installer's `|| continue` turns that into a `WARNING` the user scrolls past.

- [x] Change `repo` to `git@github.com:BachEndDeveloper/m365-mcp.git`. *Matches AI-Skills. Note the
      machine this was done on has no GitHub SSH key and clones both repos over HTTPS from the
      keychain; an existing checkout fetches from its own `origin`, so it is unaffected.*
- [ ] Consider whether the installer should distinguish "clone failed because
      auth" from other clone failures. The AI-Skills block names the SSH key
      explicitly in its warning; this one says only "could not clone".

> **Alternative:** make `m365-mcp` public. It carries no secrets — the committed
> tenant id is not one, and there is no client secret — but it does carry a
> corporate tenant identifier, so this is a judgement call rather than an
> obvious win. If it is ever made public, blank `tenantId` in its
> `config.defaults.json` first; that file documents the requirement.

---

## 2. Pinned to `v0.1.0`, the release with the broken calendar read

**Severity: high. One-line data change.**

```jsonc
"ref": "v0.1.0"   // -> "v0.3.0"
```

A machine provisioned today gets the release whose `read_resource` cannot read a
calendar event. `v0.3.0` is current.

- [x] Bump `ref` — to **`v0.4.0`** rather than `v0.3.0`, since `v0.4.0` (2026-10-06) adds the
      `m365-tools` skill, transcripts, availability and several search fixes. Verified from a fresh
      clone: builds and serves 33 tools.
- [x] Note in `MCP/README.md` that bumping a server is a `servers.json` data
      change plus a re-run, so the upgrade path is written down once.

---

## 3. The installer will move a development checkout — OPEN DECISION

**Severity: medium. Needs a decision, not just an edit.**

```jsonc
"dir": "$HOME/source/m365-personal-productivity-mcp"
```

That is the **active development checkout** of `m365-mcp` on the current
machine. The installer runs:

```bash
git -C "$SRV_DIR" checkout --detach "$SRV_REF"
```

On a clean tree that **succeeds**. Running machine setup therefore silently moves
a working repository off `main` onto an old tag. No commits are lost, but the
tree is not where it was left, and the failure is confusing rather than loud.

The installer already refuses a directory that exists and is *not* a git
checkout — the genuinely ambiguous case. A checkout sitting on a branch is the
same class of ambiguity and is currently not detected.

**Decided 2026-10-06: option (a).** `dir` is now `$HOME/.local/share/mcp/m365-mcp`, a
deployment-only copy. The installer refuses a checkout that is on a branch, so pointing `dir` back at
a working copy fails loudly instead of detaching it. Two consequences were handled with it:

- The email signature was only looked for next to the code, so the deployment copy would have sent
  mail unsigned. m365-mcp `v0.4.1` reads it from the per-user data directory, beside the token
  cache, which every copy shares.
- Claude Code was found registered against a removed Node (`v24.16.0`, `ENOENT`). Every host now
  launches through `~/.local/bin/mcp-node`, and the installer re-registers instead of leaving an
  existing entry as-is.

Pick one:

- [x] **(a) Separate the deployment checkout from the development one.** Point
      `dir` at something like `$HOME/.local/share/mcp/m365-mcp`, so provisioning
      never touches a working tree. Costs a second clone on a dev machine;
      removes the whole category of problem.
- [ ] **(b) Refuse to touch a checkout that is on a branch.** Detect
      `git symbolic-ref -q HEAD` and skip with a warning if it resolves, on the
      grounds that a branch means someone is working there. Keeps one clone;
      leaves a dev machine partly unprovisioned by design.
- [ ] **(c) Keep current behaviour, document it loudly.** Cheapest, and
      defensible if the dev checkout is expected to *be* the deployed copy — but
      it means `npm run auth` and the registered host config point at a tree
      whose contents change as you work.

Whichever is chosen, record it in `MCP/README.md`; a future reader will
otherwise re-derive this from a confusing `git status`.

---

## 4. Three names for one thing

**Severity: cosmetic. Fold into whichever change touches `servers.json`.**

| Where | Value |
| --- | --- |
| `servers.json` `name` | `m365-personal-productivity` |
| `servers.json` `dir` | `…/m365-personal-productivity-mcp` |
| Server's own `serverInfo.name` | `m365-mcp` |
| Server's own docs | clone to `~/source/m365-mcp` |

Nothing breaks — hosts key servers by the config name, not by `serverInfo.name`
— but the registered entry, the directory and the server disagree.

- [ ] Rename `name` to `m365-mcp`.
- [ ] Align `dir` with the decision in item 3.

> **Renaming `name` is not free.** It is the key under `mcpServers` in both
> Claude hosts. Changing it leaves the old entry in place and adds a second one,
> so the old key has to be removed by hand (`claude mcp remove
> m365-personal-productivity --scope user`, and the corresponding key in Claude
> Desktop's config). Worth doing once, deliberately, rather than discovering two
> registrations later.

---

## 5. `npm run auth` is now interactive in a new way

Not a defect — a heads-up for whoever runs provisioning next.

The installer prints `NEXT: cd <dir> && npm run auth`. As of `v0.3.0` that
command does the normal browser sign-in **and then asks** whether to submit an
admin-consent request for three still-ungranted scopes
(`OnlineMeetingTranscript.Read.All`, `OnlineMeetings.Read`,
`ChannelMessage.Read.All`), which opens a second browser window.

- [x] Document the sign-in step beside Pi's `/login` steps — it is the same class
      of one-time interactive act. Done in `Pi/README.md` "After setup".
- [ ] If provisioning is ever run unattended, use
      `npm run auth -- --skip-pending` so it cannot block on a prompt.
      Consider whether the installer should pass that automatically, since it
      has no way to know whether a human is watching.

The two requests are deliberately separate: Entra consent is all-or-nothing per
request, so folding the ungranted scopes into the main sign-in would return no
token at all. Measured against the tenant:

```
Tasks.ReadWrite + Mail.ReadWrite                           -> token issued
ChannelMessage.Read.All                                    -> AADSTS65001
Tasks.ReadWrite + Mail.ReadWrite + ChannelMessage.Read.All -> AADSTS65001
```

---

## Verification standing

Phase F was verified by execution against a sandbox `HOME` with a stubbed
`claude` CLI, and that verification still stands for the installer's mechanics.

**None of the changes above are verifiable on a machine that is already set up.**
Item 1 in particular only fails where there is no cached credential, which is by
definition not this machine. Treat "setup works end to end" as unproven until the
script is run somewhere genuinely fresh.

The same limitation is recorded on the server side in
`m365-mcp/docs/NEW-MACHINE.md`, and for the same reason.

---

## Suggested order

1. **Item 2** (`ref` -> `v0.3.0`) — one line, removes a known-broken release.
2. **Item 1** (SSH URL) — one line, removes the fresh-machine failure.
3. **Item 3** — decide, then implement; item 4 rides along with it.
4. Re-run `bash MCP/install-mcp-servers.sh` and confirm idempotency is intact.

Items 1 and 2 are independent of the decision in item 3 and can land first.
