---
name: structurizr-c4
description: >-
  Use this skill for any generic (non-BestOne) work with the Structurizr DSL or the C4 model. Trigger
  it whenever a request names Structurizr, C4, or a `.dsl`/`workspace.dsl` file, or asks to model
  software systems/services/microservices "as diagrams-as-code" — as long as it isn't about BestOne's
  own architecture workspace (that has its own skill). Use it to: start a new model and decide where to
  begin; add, edit, or review an element (service, container, database, message topic/queue, person,
  integration edge); build or drill into landscape, context, container, or component views, including
  double-click navigation into a system's containers; decide what belongs at which C4 level ("context
  or a level down?") or untangle a spaghetti model into clean levels; and fix DSL parse/render problems
  (nested-group separator error, lost styling, missing implied relationships). Skip generic
  Mermaid/PlantUML/cloud-icon diagrams, ER diagrams, flowcharts, and prose-only architecture talk.
---

# Structurizr C4 modelling

This skill exists to prevent the two ways C4 diagrams go wrong: **putting detail at the wrong
altitude** (violating C4 leveling), and **DSL that parses cleanly but renders wrong** because of
Structurizr's non-obvious rules. Both cost real time to discover by eye; the guidance below and the
bundled `scripts/lint_dsl.py` catch them up front.

## C4 leveling — the discipline that matters most

Each level answers a different question, and mixing them is the most common way an architecture
diagram becomes misleading rather than clarifying.

- **Level 0/1 — System Landscape / System Context:** software systems + people + the integrations
  between them. This level is about *systems*, not their internals.
- **Level 2 — Container:** the separately deployable/runnable units *inside one system* — apps,
  services, databases, message brokers — plus the external systems those units talk to.
- **Level 3 — Component:** the internals of a single container.

When you're unsure where something belongs, ask: **"Is this a system another team could depend on,
or an implementation detail of one system?"** Implementation detail drops a level. Concretely:

- A **per-service database** is *not* a landscape system — it's a container inside its owning
  system. Drawing `Domain → PostgreSQL` at L0 falsely implies one shared database. Model each
  service's store as a container (or one "per-service DBs" container per sub-domain if you don't
  have finer detail — and say so in its description).
- A **shared system-of-record** that many systems genuinely depend on (a company ERP, a warehouse
  platform) legitimately *is* a landscape system.
- A **message bus** (Kafka / RabbitMQ / Pub/Sub) is **one integration system at L0**. The individual
  **topics/queues are containers inside it** — drill into the bus to see producer → topic → consumer.
  This keeps the landscape clean while preserving the event detail one level down.
- **Ubiquitous cross-cutting infra** (schema registry, feature flags, telemetry, auth token
  endpoints) is usually noise at L0. Prefer to **omit it and document the omission** in a comment or
  README, so reviewers see it was a deliberate choice, not an oversight. That transparency is also
  what earns sign-off from the teams whose systems you're drawing.

Let the facts show complexity; don't editorialize. A clean, honestly-leveled landscape reveals things
like "everything depends on one on-prem database" or "three parallel message buses" on its own —
which is far more persuasive to reviewers than annotations telling them the system is complicated.

## The DSL's sharp edges (it parses, but renders wrong)

These are the traps that waste debugging time. Internalize them.

**1. `container` has an extra positional argument that `softwareSystem` does not.**
```
softwareSystem "name" "description" "tags"
container      "name" "description" "technology" "tags"
```
If you write `container "goodsin-api" "Goods-in API" "Service"`, then `"Service"` becomes the
**technology** and the element gets **no tags at all** — so none of your `element "Service"` styles
apply and it renders as a plain default box. This is silent: it parses fine. Always give containers
four fields; use an empty string for technology when you don't have one:
```
container "goodsin-api" "Goods-in API" "" "Service"
container "orders" "order topic" "Kafka topic" "Topic"
```
If you'd rather not count positional fields at all, tag in the container **body** instead — this is
immune to the slot trap regardless of how many positional args a given element type takes:
```
orders = container "orders" "order topic" "Kafka topic" {
    tags "Topic"
}
```
The lint script flags any container with fewer than four quoted fields.

**2. Nested groups require a separator property.** `group "BestOne" { group "Logistics" { … } }`
errors with *"To use nested groups, please define a model property named
structurizr.groupSeparator"* unless the model declares it:
```
model {
    properties {
        "structurizr.groupSeparator" "/"
    }
    ...
}
```

**3. Style blocks can't be one-liners.** `element "Topic" { shape Pipe }` on a single line fails
with *"Too many tokens"*. Put each property on its own line inside the braces.

**4. Don't force `shape` on the catch-all `element "Element"`.** It applies to every element and
competes with per-tag shapes; in some builds the base style wins, flattening your pipes and cylinders
back to boxes. Put `shape` on the specific tags that need it (`Topic → Pipe`, `Database → Cylinder`,
`Bus → Pipe`) and leave the universal `Element` style for things like `fontSize`.

**5. Roll relationships up with `!impliedRelationships true`** (workspace-level directive). Then a
relationship between two containers implies one between their parent systems, so a system landscape
shows domain↔domain coupling *derived from* the container-level detail — no manual duplicate edges.

**6. `!include` works inside a `group { }` block.** This is the mechanism for keeping one model in
many files *and* getting the grouping: the aggregate workspace opens the group and includes the
fragment, and the included systems land inside that group.

**7. Focus one element:** `container <system> "key" { include ->id-> }` renders that element plus its
directly-connected neighbours. Great for per-service views without hand-listing everything.

**8. Exclude by tag to declutter:** `exclude "element.tag==Topic"` (quote the expression).

## Multi-file models — one source of truth

For anything beyond a small workspace, author the model **once** as `!include` fragments and have a
single aggregate `workspace.dsl` include them and define the views. Do **not** define the model twice
(e.g. a per-domain workspace *and* an aggregate) — the two copies drift, which is exactly the failure
a single model prevents. Give each fragment a unique identifier prefix (e.g. `in_`, `ob_`, `ext_`) so
fragments compose without id collisions. Put cross-cutting relationships (edges between fragments) in
their own included file so each fragment stays independently readable.

## Views — give a path from overview to detail

- One `systemLandscape` (the L0 overview).
- One `container` view per system — Structurizr's double-click navigation into a system's containers
  is automatic once the view exists.
- A `container` view of each message bus, so topic-level producer/consumer flows are one drill-down
  away.
- Focus views (`include ->id->`) for hub elements people will want to isolate.

## Styling — legible defaults

Buses and topics → `Pipe`; databases/datastores → `Cylinder`; people → `Person`; external systems a
distinct fill; group/domain boxes a larger `fontSize`. Put purpose on the relationship *description*
and the mechanism (protocol, topic, volume) on the relationship *technology* — the technology renders
under the label, which is a good place to name the specific topic/queue on an edge to a bus.

## Before you render — lint

You often can't render on the spot, and you can't eyeball hundreds of relationships. Run the linter
first; a clean result means Structurizr will at least parse and style correctly:
```
python scripts/lint_dsl.py path/to/workspace.dsl
```
It inlines includes and checks brace balance, duplicate ids, undefined relationship endpoints, the
container tag-slot trap, and view targets. Fix everything it flags, then hand off to render.

## Rendering notes

Structurizr Lite (Docker) serves **one** `workspace.dsl` at a time and can cache computed layouts — if
a change doesn't appear, reload fully or restart the container. The renderer is the user's to run; this
skill doesn't install anything. When `autolayout` is set, layout recomputes on load so new elements
appear; a stale view usually means a cache, not a model error (confirm with the linter).
