# Phase B — declared enrichment (GitHub via `gh` CLI)

Phase B recovers the couplings Datadog can't see — **async edges, proxied datastores, external
systems, ingress hostnames, and consumer identity** — from repository configuration. These are
`declared` (or `inferred`); the Datadog `observed` backbone stays authoritative where they overlap.

## Mechanics

- `gh` is authenticated with `repo` scope — no MCP GitHub connector or fresh session needed. Reading
  BESTSELLER repos read-only is expected and allowed.
- List a repo tree, then read only the files you need:
  ```
  gh api repos/BESTSELLER/<repo>/git/trees/HEAD?recursive=1        # find the high-signal files
  gh api repos/BESTSELLER/<repo>/contents/<path> --jq .content | base64 -d   # read one file
  ```
- **Never read a whole repo into context.** One subagent per service; ≤ 6 services per fan-out batch;
  each returns a compact structured blob and discards raw content (the §3 contract in SKILL.md).

## High-signal files only

manifest / build file · IaC / Helm chart / `values.yaml` · **broker + integration config** (Kafka
topics produced/consumed, RabbitMQ exchanges/queues/bindings, Pub/Sub) · CODEOWNERS · CI workflow ·
README head · **IngressRoute / gateway CRDs** (host → backend → path prefix) · datasource/DB config ·
external-client config (base URLs, auth mode). Skip application source unless a specific edge needs
confirming.

## What each service subagent must recover

| Step | Recover | Fills the backbone blind spot |
|---|---|---|
| **B1** service → repo (confirm via GitHub team) | inventory | — |
| **B2** **async/event edges** — every bus in use: Kafka topics produced/consumed (CloudEvents type if present), RabbitMQ exchanges/queues, Pub/Sub | async coupling | A3 is sync-only |
| **B3** **consumer identity + owning team** — resolve caller IPs / NAT egress → system via IngressRoute host mapping, asset inventory, or pod-IP→workload | cross-team integrators | A5/A6 give IPs, not names |
| **B4** confirm **non-APM services** (real? prod? owner?) | inventory | A2 shows existence only |
| **B5** external systems (EDI/SaaS/on-prem) + human actors | L0 completeness | — |
| **B6** **ingress hostnames + path prefixes** (when the shared Ambassador hid them in Datadog) | exposure | Datadog ingress blind spot |
| **B7** datastores (schema/table/user) incl. proxied Cloud SQL and on-prem | persistence | A4 proxied-as-localhost gap |

## Structured facts blob (what each subagent RETURNS — keep it compact)

Return JSON in this shape (write it to `model/<sub-domain>-phaseB-<service>.json`, return only a short
summary). Every fact carries `provenance` + `confidence` + a **file citation**.

```
{
  "service": "...", "repo": "...", "team": "...", "generation": "BI4|BI2",
  "prod_confirmed": true, "exposed": {"host": "...", "path_prefix": "/x/"},
  "event_edges":   [{"topic": "...", "direction": "produce|consume", "bus": "kafka|rabbitmq|pubsub",
                     "evidence": "<file>", "provenance": "declared", "confidence": "high"}],
  "internal_edges":[{"target": "...", "verb": "GET /...", "evidence": "...", "provenance": "...", "confidence": "..."}],
  "datastores":    [{"system": "postgres|oracle|...", "instance": "...", "schema": "...", "rw": "r|rw",
                     "evidence": "...", "provenance": "...", "confidence": "..."}],
  "external":      [{"system": "...", "how": "...", "evidence": "...", "provenance": "...", "confidence": "..."}],
  "flags_inferred":[{"claim": "...", "why_uncertain": "...", "needs_signoff": true}]
}
```

## Judgement rules

- **Both ends confirmed ⇒ a real async edge** (e.g. producer topic + a consumer of it in another repo).
  A README that *claims* a consumer but ships no client/config for it is **NOT implemented — do not map
  it** (record as a flagged discrepancy).
- Represent sync and async between the same pair as **two edges of different transport** when both exist.
- An endpoint locked to a caller's client-ID but with **no HTTP client** on the caller side = a
  half-wired path → `inferred / low`, flag for sign-off (don't assert it).
- Telemetry/infra/auth are usually **not integration edges** — keep them as `flags_inferred` notes, not
  edges: Datadog, Vault, LaunchDarkly, Confluent Schema Registry, Entra login / MS-Graph OIDC noise,
  disabled-but-wired components.
- Note ownership discrepancies (e.g. `values.yaml` team vs CODEOWNERS) as open flags.

## Then diff

Diff the declared enrichment against the observed backbone per sub-domain — the **async/broker deltas
are the payoff and the go/no-go signal**. See `references/planning-tracking-and-reconcile.md`.
