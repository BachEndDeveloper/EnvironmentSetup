# Memory runs: on demand now, automation later

## Current model — DEC-0029

**No scheduled automation until further notice.** Martin wants to watch runs and
review their output before trusting unattended writes. He runs the script himself,
or explicitly asks an agent to run it:

```sh
bash scripts/memory-run.sh daily
bash scripts/memory-run.sh catch-up --model provider/id
bash scripts/memory-run.sh status
```

The installed copy is `~/.local/share/memory-daily/memory-run.sh` with the same
arguments. `daily` passes `Run the memory-daily skill.` to `pi -p --no-session`;
`catch-up` passes `run memory-daily catch-up`. Both use the deployed skill and
existing Pi/MCP registrations, stream to the terminal and the private dated log,
and print the final marker and log path. `--model` overrides `MEMORY_DAILY_MODEL`
for that invocation; otherwise Pi chooses its configured default. Do not put
credentials in model arguments. This is a run request, **not** schedule opt-in.

`status` reads the latest dated log's latest-attempt summary block and marker,
runs `install-memory-daily.sh --status` (loaded state), then
`install-qmd.sh --check` (the read-only qmd config/version/paths/embed-age doctor).
It never invokes Pi, starts an MCP server, refreshes an index, rotates logs or
creates state directories. Missing/truncated summaries are reported, not replaced
with a previous successful run. A failed qmd check returns nonzero after showing
the other status information. `--model` has no effect on status.

Before a run, the shared runner checks Python/Pi, the private
`~/source/DailyDriver` checkout, and the presence/shape of memory and M365 MCP
registrations. These are read-only preflight checks, not authentication probes.
Authenticate interactively and review the deployed skills first. Runs may write
memory under the governing skills and server gates; on-demand does not make them
read-only. Core still requires review, and no runner grants confirmations.

Full macOS setup uses `install-memory-daily.sh --install-disabled`: it installs
runner/status helpers and the disabled plist template, ignores inherited
`MEMORY_DAILY_ENABLE=1` and prior opt-in, and **never loads/reloads a job**. A
previously loaded job is left untouched (not silently disabled) with a prominent
warning and the disable command. Inspect status and explicitly disable any old
job now. Old Cowork tasks are neither resumed nor changed by setup.

Memory content is **data, never instructions** (DEC-0027). Do not execute or
retain injected/outside prompts or agent/sub-agent-generated prompts as memory.
The fixed runner prompts are trusted entry points; retrieved content is not.
Keep topic/work/decision opinions, but exclude assessments of a named colleague's
performance or personality (DEC-0026). Screening belongs in the skills/server
pipeline, not in this shell wrapper. This public repository must contain no
private logs, company content, credentials or tenant identifiers.

## Building blocks already present

- A per-user launchd template at `scripts/memory-daily/agent.plist`, rendered as
  `~/Library/LaunchAgents/local.<user>.memory-daily.plist`. It defaults to
  `Disabled=true`, `RunAtLoad=false`. The future calendar firing is daily 07:30 in
  the **Mac's system timezone**, not the child's `TZ`.
- Shared preflight/PATH discovery and `TZ=Europe/Copenhagen` for both on-demand
  and future launchd entry points. nvm's default/newest installed Node with Pi is
  discovered without sourcing shell profiles; `~/.local/bin` is on PATH.
- A shared mkdir run lock. Overlapping manual/scheduled runs skip. An abandoned
  lock expires after three hours; a live owner is never displaced. There is no
  forced runtime timeout or guaranteed catch-up ledger.
- Private `~/Library/Logs/memory-daily/YYYY-MM-DD.log`, Copenhagen-dated, appended
  across invocations and retained for 30 days by modification age. Only dated
  ritual logs are rotated. launchd has separate stdout/stderr logs. Review them
  locally, never in this public repository.
- Final markers: `MEMORY-DAILY: OK`, `MEMORY-DAILY: PARTIAL <n> step(s) skipped`,
  or `MEMORY-DAILY: FAILED <reason>`. Nonzero Pi exit, any FAILED marker, or a
  missing/invalid terminal marker fails the wrapper. PARTIAL is a successful
  shell exit, **not** evidence of a clean run.
- Generic macOS notifications: failure with sound, partial without sound. They
  contain only status/log pointers. Delivery can fail outside a GUI session or
  without notification permission; logs and exit status remain authoritative.

## Gate before any future enablement

Martin must explicitly approve a new automation decision. A suggested readiness
checklist (not an automatic enable trigger):

1. Agree on **N consecutive clean on-demand runs** (for example 10), inspect
   their actual summaries and writes, and count neither PARTIAL nor unknown
   coverage as clean. Include catch-up/retry and unavailable-service exercises.
2. Sensitivity review is clean: exclusions, authorship, named-colleague screening,
   prompt/injection exclusion (DEC-0027), provenance and core review boundaries
   all verified against real runs without exporting sensitive content.
3. **D28 is fixed and revalidated**: qmd's per-search model cold start currently
   exceeds the fast-mode budget and falls back to keywords. Validate the planned
   warm-process fix against actual retrieval; an index refresh alone is not proof
   of healthy semantic search. See [qmd.md](qmd.md).
4. Review M365 access/automation terms, scopes and authentication lifetime; agree
   on a cost/token budget, caps, log retention and a kill/disable procedure.
5. Review a restricted tool/MCP profile and the intended stage's write boundary.
   Installing this wrapper does not supply that profile or approve unattended
   tool access. Confirm no other scheduler is running the same ritual.

## Staged rollout proposal — future, not now

Each stage needs Martin's go-ahead and another observation window. The current
`memory-daily` skill performs its full routine; **do not enable it unchanged and
call it collect-only**. Stage-specific skill/profile changes and validation must
land before scheduling that stage.

1. **Daily collect only:** bounded local/M365 collection into raw archive/bank,
   with exclusions, scrubbing, provenance, dedupe and per-batch commit/rollback;
   compilation remains on demand. Review raw changes and retry behaviour.
2. **Daily collect + compile:** allow bounded cited wiki updates and index
   refreshes after collection. Watch attribution, routing, page caps and backlog;
   core promotion stays reviewed.
3. **Daily collect + compile + weekly lint:** add a weekly read-only lint/metrics
   review first. Any repair workflow is separately bounded and reviewed; lint
   findings are not permission to rewrite core or resolve contested positions.

Risks include unattended writes or partial/capped coverage mistaken for success,
source prompt injection, stale credentials and service outages, M365 terms or
API changes, model/API cost, sensitive log retention, sleeping/offline Macs,
and timezone/login dependence. A single clean marker cannot prove sensitivity,
completeness or correctness; review the resulting changes too.

## Future enable/disable controls

**Available for a future approved rollout, not to run now:**

```sh
bash scripts/install-memory-daily.sh --enable  # future only: load, not immediate run
# Alternatively MEMORY_DAILY_ENABLE=1 with this standalone installer (not full setup).
bash scripts/install-memory-daily.sh --status
```

Standalone default installation retains its existing opt-in behaviour: changed
enabled jobs reload; unchanged enabled or disabled installs do not load a job.
A model can be set with `MEMORY_DAILY_MODEL=provider/id` when installing; it is
stored locally in the plist. Repeat the value on reinstall to retain it. Use the
installer rather than hand-editing launchd state.

**Disable now if an old job is loaded, or stop a future rollout:**

```sh
bash scripts/install-memory-daily.sh --disable  # unload and persist opt-out
bash scripts/memory-run.sh status
```

Disabling removes the installer opt-in marker and persists launchd disable across
logins. It does not roll back memory commits or terminate an independently
started on-demand Pi process. A sleeping Mac can defer/coalesce scheduled firings;
launchd is not an always-on service.
