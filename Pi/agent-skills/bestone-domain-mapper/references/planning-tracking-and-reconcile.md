# Planning, tracking, and reconciling (the markdown discipline)

Because context resets between batches, **the files on disk are the run state.** This is what makes a
70-service mapping resumable and hallucination-resistant. Set these up at the start of every domain.

## The files (source of truth)

| File | Role | When written |
|---|---|---|
| `inventory.json` | **FROZEN** authoritative prod scope — one row per service `{name, sub_domain, repo, team_tag?, prod_confirmed, enrich, batch_id, note}` | Once, after inventory reconciliation; then frozen |
| `PLAN.md` | procedure, scope config (§1), batch map (§5), sign-off checkpoints (§7). Copied from `assets/domain-mapping-template.md` | Start; refined as batches finalize |
| `RESUME.md` | the **live tracker** — one-line status, done/next, locked findings, open flags. Written so a fresh session resumes with zero prior context | Updated at **every** checkpoint |
| `method-deltas.md` | this domain's deviations from the runbook (facet traps, ingress quirks, exclusions). **Read before any Datadog/GitHub work** | Start; append as you discover deltas |
| `model/*.json` | per-batch observed/declared partials + merged backbone + diff | Each batch |

Keep the working folder self-contained. Convert relative dates to absolute in these files.

## Step 1 — inventory reconciliation, then FREEZE

Team tags always undercount the running fleet — proven repeatedly. Union three sources:
1. `search_datadog_services` per team tag.
2. `analyze_datadog_logs` `env:prod` grouped by service, **volume-ranked** — catches untagged live
   services (brokers, expansion services) the tags miss.
3. `gh api orgs/BESTSELLER/teams/<slug>/repos` for the repo → sub-domain split.

Reconcile into `inventory.json`. Assign untagged/unassigned services to a sub-domain by **runtime
evidence** (what they call / are called by); leave genuinely ambiguous ones `shared` and flag. Mark
live legacy (e.g. BI2) as **observed-only** (`enrich:false`) — they get a Phase-A node with their
Datadog edges but **no Phase-B enrichment**. **Freeze the count.** Sign-off checkpoint #1 is the frozen
inventory + the ambiguous assignments.

## Step 2 — deterministic merge + drop-detection

Merge the per-batch partials **in code** (a small script), never by an LLM re-reading transcripts:
- **Canonicalise by NAME, not identifier** — the same real service/datastore can appear under different
  ids or label variants across batches/sources (e.g. an ERP node labelled two ways). Dedupe on a
  normalised name; merge `used_by` lists; keep the richest description.
- Dedupe edges by (from, to, type, transport, direction).
- **Drop-detection:** assert merged service count == frozen inventory count; emit any dropped services
  or edges explicitly. A clean run reports `drop_detection.clean == true`. Never truncate silently.

## Step 3 — diff, reconcile, verify

- **Diff** declared (Phase B) vs observed (Phase A) per sub-domain. Classify externals into *confirmed*
  (observed) vs *new* (declared-only); capture ingress-hostname recovery; surface the async/broker
  deltas (the payoff).
- **Reconcile** observed + declared into the sub-domain model. Observed wins where they overlap;
  declared adds the blind-spot edges; inferred is dashed and flagged.
- **Adversarial verifier pass:** is every node/edge traceable to a source? Any invented system? Any
  `inferred` element with no support? This feeds the go/no-go and the sign-off list.

## Step 4 — sign-off checkpoints (owner)

1. Frozen `inventory.json` + ambiguous sub-domain assignments.
2..n. **Each sub-domain's diff, before rendering.**
Final: service→system rollup, all `inferred` edges, legacy-boundary treatment.

Stop at each checkpoint; update `RESUME.md`; don't render or fan out the next track until the owner
greenlights (the established per-track cadence).

## Step 5 — hand off to `bestone-c4-diagrammer`

The reconciled, provenance-tagged model **is** the diagrammer's input. Keep shapes compatible:
- Services → containers in their sub-domain; datastores → shared L0 system if truly shared, else a
  per-sub-domain DB container; topics/queues → containers inside the relevant bus system.
- Carry `observed` (untagged) / `declared` / `inferred` / `Event` / `Queue` straight onto the
  relationship tags. Unmapped cross-domain targets become `ref_*` placeholders.
- Then follow the `bestone-c4-diagrammer` skill to build/extend the unified `bestone-architecture`
  workspace, and lint before rendering.

## Definition of done (per sub-domain, then domain)

- [ ] Prod-scoped; no dev/test-only artefacts.
- [ ] Mapped count == frozen inventory; drops/unresolved logged.
- [ ] Cross-team integrators named with owning team; unresolved prod callers shown as first-class nodes.
- [ ] Async coupling (every bus in use) recovered and diffed.
- [ ] Every element tagged provenance + confidence; `inferred` signed off.
- [ ] Reconciled model handed to `bestone-c4-diagrammer`; workspace renders cleanly (owner validates).
