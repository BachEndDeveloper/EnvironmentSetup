---
name: bestone-c4-diagrammer
description: >-
  Use for any work on **BestOne's own architecture model** — the `bestone-architecture` Structurizr/C4
  workspace that maps BestOne's domains, sub-domains, services, databases, Kafka/RabbitMQ/PubSub topics,
  and integrations. Trigger whenever a request names BestOne (or a BestOne domain like Buying, Sales,
  Sourcing, Logistics, BOSS) together with its diagram, C4 model, or Structurizr workspace: adding or
  updating a service, sub-domain, database, topic, or integration; onboarding or reconciling a
  newly-mapped domain; building a focused container or landscape view; or asking how BestOne's diagram
  is kept current and maintained as teams ship services. This is the BestOne-specific layer — prefer it
  over the generic `structurizr-c4` skill whenever the target is BestOne's model, and consult
  `structurizr-c4` alongside it for raw DSL mechanics.
---

# BestOne C4 diagrammer

This skill encodes **how BestOne represents its architecture as one navigable C4 model**. It assumes
the general Structurizr/C4 mechanics from the **`structurizr-c4`** skill (the container tag-slot trap,
nested-group separators, implied relationships, the lint script, C4 leveling) — read that first when
you're actually writing DSL. This skill is the BestOne-specific layer on top.

The canonical model lives in the **`bestone-architecture/`** workspace (under `Chief Architect/`).
It is the single source of truth. The older per-sub-domain standalone DSLs (in
`logistics-current-state/`) are the provenance the model was bootstrapped from — treat the unified
workspace as authoritative going forward, and keep the standalones as-is unless asked otherwise.

## The model in one picture

BestOne is one Structurizr workspace assembled from `!include` fragments, so the model is defined
once and rendered from a single aggregate `workspace.dsl`.

```
bestone-architecture/
  workspace.dsl                 # aggregate: !includes fragments, defines views + styles. Render THIS.
  model/
    _globals.dsl                # actors; shared datastores/on-prem; buses (Kafka+topics, RabbitMQ, PubSub); externals; refs
    <domain>/                   # e.g. logistics/  (a business domain = a group)
      <subdomain>/<subdomain>.dsl   # e.g. inbound/inbound.dsl  (a sub-domain = a softwareSystem of containers)
      <domain>.rels.dsl         # cross-sub-domain + service→backbone relationships within the domain
    boss/boss.dsl               # an adjacent domain (touchpoints only until mapped)
    cross-domain.dsl            # relationships BETWEEN domains (included last)
  README.md                     # conventions + what's at each level + what's omitted
```

## C4 mapping (BestOne's leveling decisions)

| BestOne concept | C4 element | How it appears |
|---|---|---|
| Enterprise (BestOne) | outer `group` | boundary on the landscape |
| Domain (Logistics, Buying, Sales, BOSS, …) | nested `group` | boundary inside BestOne |
| **Sub-domain** (Inbound, Outbound, Shared, Brokers, Legacy) | **softwareSystem** | box on the landscape — double-click to drill in |
| **Service** (the ~65 microservices) | **container** inside its sub-domain | seen when you drill into the sub-domain |
| Message bus (Confluent Kafka, RabbitMQ, GCP Pub/Sub) | **softwareSystem** at L0 | one box the domains integrate with |
| **Kafka topic** | **container inside the Confluent Kafka system** | drill into Kafka to see producer→topic→consumer |
| **Per-service database** | **container inside its sub-domain** | never a landscape box |
| Shared system-of-record (on-prem Oracle ERP, Snowflake, IWACS) | softwareSystem at L0 | genuinely shared → stays at L0 |
| External partner / SaaS | softwareSystem at L0 | the external surface |
| Component (intra-service) | not yet modelled | future level |

Nested groups require `properties { "structurizr.groupSeparator" "/" }` in the model (see
`structurizr-c4`). `!impliedRelationships true` is on, so service↔service and service↔bus container
edges roll up to sub-domain↔sub-domain / sub-domain↔bus on the landscape.

### What lives at L0 vs gets pushed down vs omitted

This is the discipline that keeps the landscape honest and earns architect sign-off:
- **L0:** sub-domains, other domains, the three buses (as systems), shared systems-of-record, and
  external partners.
- **Pushed to container level:** per-service databases (one `*_pg` / `*_db` container per sub-domain,
  or per service if known); Kafka topics (containers in the Kafka system); per-service blob stores.
- **Omitted as ubiquitous infra** (documented in the README, not silently dropped): schema registry
  (part of Kafka), feature-flag SaaS, telemetry, auth token endpoints. Reinstate on request.

Let the model show the complexity through facts — a shared on-prem ERP every sub-domain depends on,
three parallel buses, a still-live legacy backbone. Don't annotate "this is over-complicated";
a clean, correctly-leveled diagram makes that case on its own, and stays defensible in review.

## Identifier prefixes (so fragments compose without collisions)

Every id carries a prefix encoding its class. Keep this consistent — the lint script and readability
both depend on it.

| Prefix | Meaning | Example |
|---|---|---|
| `in_ ob_ sh_ br_ lg_` | Logistics sub-domain services (Inbound/Outbound/Shared/Brokers/Legacy) | `in_goodsin_api` |
| `bo_` | BOSS domain systems | `bo_orbis` |
| `kt_` | Kafka topic (container in `bus_kafka`) | `kt_log_packingnote_cdc` |
| `bus_` | a message bus system | `bus_rabbitmq` |
| `inf_` | shared datastore / on-prem / ingress system | `inf_on_prem_bestcorp_oracle_erp` |
| `ext_` | external partner / SaaS | `ext_shopify` |
| `ref_` | reference to an unmapped / other-domain element | `ref_bi4_sales_cores` |
| `per_` | actor (person) | `per_warehouse_office_users` |

New domains get their own prefixes (e.g. Buying → `by_`, Sales → `sa_`). `ref_*` nodes resolve into
real systems as their owning domain gets mapped.

## Provenance / trust model

Every relationship carries how much we trust it, via relationship tags (styled distinctly):
- **untagged = observed** — seen in production telemetry (the default; most trustworthy).
- **`Declared`** — from repository configuration.
- **`Inferred`** — deduced, not directly seen.
- **`Event`** — asynchronous over Kafka (dashed).
- **`Queue`** — asynchronous over RabbitMQ / Pub/Sub (dashed).

Preserve these when you add or edit edges — they're the point of a *current-state* map. Put the edge
*purpose* in the description and the *mechanism* (protocol, topic/queue name, volume) in the
technology field; naming the specific topic on an edge to a bus makes flows followable.

## Views

- `BestOne_Landscape` — the L0 overview (domains + buses + shared systems + externals).
- `<Subdomain>_Detail` — a container view per sub-domain (its services + their DBs + what they touch).
- `Kafka_Topics` — the Confluent Kafka container view (topics + producers/consumers across domains).
- `Focus_*` — per-service focus views (`include ->service->`).
- `BOSS_*` / per-domain context views for adjacent domains.

## Adding or changing something

Read **`references/adding-a-domain.md`** for the step-by-step (with DSL templates) covering: a new
service in an existing sub-domain, a new sub-domain, and a whole new domain. The short version:

- **New service** → add a `container` (four fields! `"name" "desc" "tech" "Service"`) to the
  sub-domain fragment; add its relationships (intra-domain in the fragment, cross-domain in
  `<domain>.rels.dsl` or `cross-domain.dsl`, with provenance tags).
- **New sub-domain** → new `model/<domain>/<sub>/<sub>.dsl` with a `softwareSystem { containers }`;
  `!include` it inside the domain group in `workspace.dsl`; add a `<Subdomain>_Detail` container view.
- **New domain** → new `model/<domain>/` folder + a `group "<Domain>"` in `workspace.dsl` that
  includes its fragments; inter-domain edges go in `cross-domain.dsl`; give it an id prefix.

## Always lint before handing off to render

Run the `structurizr-c4` linter on `workspace.dsl` after any change:
```
python <path-to>/structurizr-c4/scripts/lint_dsl.py bestone-architecture/workspace.dsl
```
A clean result (elements found, 0 undefined endpoints, balanced braces, no container tag-slot
warnings) means Structurizr will parse and style it correctly. Rendering is done by the user in
Structurizr Lite (one workspace at a time; restart if a change doesn't show — likely a layout cache).

## Keep the docs in step

When the model changes materially, update `bestone-architecture/README.md` — especially the "what's
at L0 vs container vs omitted" section and any new domain/prefix. That README is what lets a domain
architect challenge a *specific* modelling call rather than the whole diagram, which is how the map
earns acceptance.
