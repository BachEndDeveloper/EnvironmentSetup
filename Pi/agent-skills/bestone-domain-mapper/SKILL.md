---
name: bestone-domain-mapper
description: >-
  Use to map a BESTSELLER (BestOne) domain's or team's current-state architecture — the repeatable
  method that discovers what's actually running in production and prepares it for diagramming. Trigger
  whenever someone wants to map, inventory, audit, or discover a BestOne domain / sub-domain / team's
  services and integrations; to combine Datadog (observed) with GitHub (declared) to find services,
  event/topic edges, datastores, external integrations, and cross-team callers; to freeze a service
  inventory; to plan and track a mapping run in markdown; or to reconcile observed-vs-declared into a
  provenance-tagged model. This is the DISCOVERY layer that produces the data the `bestone-c4-diagrammer`
  skill turns into a diagram. Reach for it for any "map / audit / current-state / where-does-X-integrate"
  request scoped to a BestOne domain or team — especially when it spans many services and must not
  overflow context. It will be reused for every domain and team, so follow it faithfully each time.
---

# BestOne domain mapper

This skill is the **discovery half** of the BestOne architecture toolchain: it maps a domain's
current-state prod architecture and hands a provenance-tagged model to **`bestone-c4-diagrammer`**,
which renders it. Its whole reason to exist is doing this **at scale (70+ services) without context
overflow or hallucination**, and **repeatably** for every BESTSELLER domain and team over time.

## Trust model (the foundation)

**Datadog is authoritative for what it OBSERVES; GitHub fills the blind spots (DECLARED); deductions
are INFERRED and need sign-off. Every element carries provenance.** The headline finding from the
method's validation: Datadog is strong on *outbound* shape + external identities, and weak on *inbound*
caller identity, non-APM services, proxied datastores, and *async* (event/queue) edges. **That
asymmetry is exactly why the GitHub enrichment layer exists** — it recovers the couplings Datadog
can't see.

## The workflow (per domain; repeat per sub-domain)

0. **Set up the run.** Copy `assets/domain-mapping-template.md` into the domain's working folder as
   `PLAN.md`; keep a `RESUME.md` live tracker; start a `method-deltas.md` for this domain's gotchas.
   See `references/planning-tracking-and-reconcile.md`.
1. **Inventory reconciliation — do FIRST, then freeze.** Union three sources (team tags undercount the
   running fleet — always): Datadog team-tag services + a prod-log volume ranking (catches untagged
   live services) + GitHub team repos. Reconcile into `inventory.json`, assign sub-domains by runtime
   evidence, **freeze the count**. Every later batch reconciles mapped-vs-expected against it.
2. **Phase A — observed backbone (Datadog).** The deterministic backbone: services, ingress routing,
   downstream edges, datastores (via raw spans), and cross-team consumers (via distributed tracing).
   Full recipes + the domain-specific facet traps: `references/datadog-phase-a.md`.
3. **Deterministic merge + drop-detection.** Merge per-batch partials **in code**, not by re-reading
   transcripts; assert mapped count == frozen inventory; log any drops.
4. **Phase B — declared enrichment (GitHub, `gh` CLI).** Per-service map-reduce over high-signal files
   to recover async edges (Kafka topics + RabbitMQ/PubSub), datastores, external EDI/SaaS, ingress
   hostnames, and consumer identity+team. Recipes + output schema: `references/github-phase-b.md`.
5. **Diff + reconcile + verify.** Diff declared vs observed (the async/broker deltas are the payoff),
   reconcile into the model, run an adversarial verifier pass (every node/edge traceable? invented
   systems? unsupported inferred?), flag `inferred` for sign-off.
6. **Sign-off checkpoint** with the owner **at the diff, before rendering** — one per sub-domain.
7. **Hand off to `bestone-c4-diagrammer`.** The reconciled, provenance-tagged model (backbone JSON +
   diff) is that skill's input; keep the shapes compatible (see the reconcile reference).

## The anti-overflow / anti-hallucination contract (non-negotiable — this is the core)

This is what lets the method scale; apply it on **every** batch, at any domain size:

- **Per-service map-reduce.** One subagent per service. It reads only **high-signal files** (manifest,
  IaC/Helm, broker config, CODEOWNERS, CI, README head, IngressRoute), returns a **structured facts
  blob**, and discards the raw content. **Never feed a whole repo into any context.**
- **≤ 6 services per fan-out batch.** The orchestrator ingests only the compact blobs, appends them to
  the on-disk partial model, and proceeds. **Raw subagent transcripts never enter orchestrator
  context** — do not tail an agent's transcript/output file.
- **Disk-checkpointed partial models.** After each batch write `model/<sub-domain>-<batch>.json`. The
  model is assembled by **deterministic merge in code**, not by an LLM re-reading transcripts. Context
  can reset safely between batches — the markdown + JSON on disk are the state.
- **Provenance on every element.** `observed` > `declared` > `inferred`. No edge without a source.
  `inferred` is dashed and requires sign-off.
- **Structured-output schema** for subagent returns (shape in `references/github-phase-b.md`): purpose,
  owning team, event edges (topic/exchange + direction + evidence), datastores, external integrations,
  internal edges, prod-deploy evidence — each with provenance + confidence + file citation.
- **Adversarial verifier pass per sub-domain**, and **drop-detection** (mapped == frozen inventory; no
  silent truncation).

If a subagent returns 0 tool calls or echoes an injected reminder instead of working, just **re-run
that batch** — it's intermittent, not systemic. Verify an agent actually wrote its `model/*.json`
before trusting it.

## Plan and track in markdown (why the files are the source of truth)

Because context resets between batches, **the on-disk files ARE the run state**:
- `inventory.json` — the frozen authoritative prod scope (source of truth for batches + drop-detection).
- `PLAN.md` — the procedure, batch map, and sign-off checkpoints (copied from the template).
- `RESUME.md` — the live tracker: what's done, what's next, locked findings. Written so a fresh session
  can resume with zero context. Update it at every checkpoint.
- `method-deltas.md` — this domain's deviations from the runbook (the facet traps, ingress quirks,
  exclusions). Read it before any Datadog/GitHub work on that domain.
- `model/*.json` — the observed/declared partials and merged backbone.

## Provenance taxonomy (carried through to the diagram)

`observed` (untagged; Datadog) · `declared` (repo config) · `inferred` (deduced — dashed, sign-off) ·
`Event` (Kafka, async) · `Queue` (RabbitMQ / Pub-Sub, async). These map 1:1 onto the relationship tags
the `bestone-c4-diagrammer` skill expects.

## References

- `references/datadog-phase-a.md` — Phase A recipes (A1–A6), normalization rules, unresolved-caller
  handling, and the **facet/co-tenancy traps** that waste the most time.
- `references/github-phase-b.md` — `gh` CLI enrichment, high-signal file list, the structured facts
  schema, async-edge recovery.
- `references/planning-tracking-and-reconcile.md` — inventory freeze, the markdown discipline,
  deterministic merge + drop-detection, diff/reconcile/verify, sign-off, and the hand-off shape.
- `assets/domain-mapping-template.md` — the blanked §1–§9 plan to copy into each new domain folder.
