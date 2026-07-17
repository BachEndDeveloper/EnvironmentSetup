# Current-State Mapping — `<DOMAIN>` (template)

> Copy this file into a new domain folder as `PLAN.md`, refill `§1` and `§5`, then run `§2 → §6`.
> The **§3 contract is domain-agnostic** — it is what prevents context overflow / hallucination at any
> size. Batch rule stays **≤6 services/batch**; number of batches scales with the inventory.
> Detail lives in the `bestone-domain-mapper` skill: `references/datadog-phase-a.md` (Phase A recipes +
> facet traps), `references/github-phase-b.md` (enrichment + output schema),
> `references/planning-tracking-and-reconcile.md` (inventory freeze, merge, diff, sign-off).

## Context
Restate: why map `<DOMAIN>` now, what validation/decision it feeds, and the intended output (a
provenance-tagged model handed to `bestone-c4-diagrammer`). Note sub-domains if any: `<sub-A>`, `<sub-B>`.
Locked decisions: **scope boundary**, **sequencing** (which sub-domain first), **output structure**.

## §1 Scope config
| Item | Value |
|---|---|
| Datadog team tags | `<team-tag>`, `<team-tag>-<sub-domain>` … |
| GitHub org / teams | `BESTSELLER` / `<team-slug>` … |
| K8s namespace / clusters | `<namespace>` on `<cluster>-{dev,test,prod}` — **prod only** = `<cluster>-prod` |
| Repo pattern | `<repo-glob>` |
| Must-add: untagged live services | (from prod-log ranking — team tags always undercount) |
| Exclude | archived, forks, legacy estate, libs/infra plumbing |
| Sub-domain split signal | team tag / naming / CODEOWNERS / namespace — pick the reliable one |

List **complexity flags** that drive extra effort: event buses in use (Kafka/RabbitMQ/PubSub), external
SaaS/EDI, GraphQL, mixed generations (BI4/BI2), non-Java stacks.

## §2 Inventory reconciliation (do FIRST, freeze before batching)
Union three sources — never trust team tags alone:
1. `search_datadog_services` per team tag.
2. `analyze_datadog_logs` `env:prod` GROUP BY service, volume-ranked (catches untagged live services).
3. `gh api orgs/BESTSELLER/teams/<slug>/repos` for repo→sub-domain split.
Reconcile into `inventory.json`: `{name, sub_domain, repo, team_tag?, prod_confirmed, enrich, batch_id}`.
Triage untagged/unassigned by runtime evidence; leave ambiguous as `shared` and flag. Mark live legacy
`enrich:false` (observed-only). **Freeze the count** — every batch reconciles mapped-vs-expected.

## §3 Anti-overflow / anti-hallucination contract (non-negotiable, domain-agnostic)
- **Per-service map-reduce:** one subagent per service; reads only high-signal files; returns a
  structured facts blob; discards raw. Never feed a whole repo.
- **≤6 services per fan-out batch.** Orchestrator ingests only compact blobs; raw transcripts never
  enter its context (don't tail agent output files).
- **Disk-checkpointed partials:** write `model/<sub-domain>-<batch>.json` per batch; merge in code.
- **Provenance on every element:** `observed` > `declared` > `inferred`. `inferred` = dashed + sign-off.
- **Structured-output schema** for returns (see `references/github-phase-b.md`).
- **Adversarial verifier pass** per sub-domain; **drop-detection** (mapped == frozen inventory).

## §4 Per-batch procedure (Phase A/B/C)
Per sub-domain, in order: **A** observed backbone (Datadog, prod-only, name cross-team consumers) →
**B** declared enrichment (GitHub `gh` CLI, ≤6/batch, recover async edges for every bus in use) →
**diff** declared vs observed → **C** reconcile + verifier + flag inferred → **checkpoint with owner at
the diff** before rendering.

## §5 Batch map (finalize against `inventory.json`)
Group services into ≤6-service functional clusters per sub-domain; add batches for shared cores and
external integrators. Table: `<batch-id> | cluster | services`.

## §6 Reconcile & hand off
Reconcile observed + declared into the model; carry provenance tags. Then hand the model to
`bestone-c4-diagrammer` to build/extend the unified `bestone-architecture` workspace (sub-domain =
system, service = container, topics inside the bus system, per-service DBs as containers). Lint before
render. The workspace is the single canonical output.

## §7 Sign-off checkpoints (owner)
1. Frozen `inventory.json` + ambiguous sub-domain assignments.
2..n. Each sub-domain's diff before rendering.
Final: service→system rollup, all `inferred` edges, legacy-boundary treatment.

## §8 Definition of done
Prod-scoped; mapped==inventory count; cross-team integrators named; async coupling recovered + diffed;
every element provenance+confidence tagged; inferred signed off; model handed off and workspace renders.

## §9 Progress tracker
Keep a live checkbox list here per batch (A done / B done / diff / reconciled). Mirror status into
`RESUME.md` so a fresh session can resume with zero context.
