# Adding to the BestOne model — step-by-step with templates

Three scopes, smallest to largest. In all cases: containers need **four** quoted fields
(`"name" "description" "technology" "tags"` — an empty `""` technology is fine), relationships carry
provenance tags, and you **lint before render**. See the `structurizr-c4` skill for why.

---

## 1. A new service in an existing sub-domain

Edit the sub-domain fragment (e.g. `model/logistics/inbound/inbound.dsl`). Add a container inside the
`softwareSystem { … }` block:

```
in_new_service = container "new-service" "What it does. Exposed: /path/ if HTTP-facing." "" "Service"
```

Add its persistence to the sub-domain's DB container if it has one (already present as `in_pg` etc.),
and its relationships:

- **Intra-sub-domain** edges live in the fragment (both endpoints are containers of this system):
  ```
  in_new_service -> in_goodsin_api "Calls for goods-in status" "http"
  ```
- **To the backbone / other sub-domains / externals** — put in `model/logistics/logistics.rels.dsl`:
  ```
  in_new_service -> inf_on_prem_bestcorp_oracle_erp "Reads order lines" "oracle · SOME_USER"
  in_new_service -> kt_log_inbound_cdc "Produces" "log.inbound.cdc.transport.4" "Event"
  in_new_service -> ob_masterdata_api "Reads master data" "http" "Declared"
  ```
  Untagged = observed; add `Declared`/`Inferred`; `Event` for Kafka, `Queue` for RabbitMQ/PubSub.

That's it — no view changes needed; it appears in the existing `Inbound_Detail` container view.
Optionally add a `Focus_new_service` view in `workspace.dsl`.

---

## 2. A new sub-domain in an existing domain

Create `model/<domain>/<sub>/<sub>.dsl`:

```
# <sub>.dsl — <one-line purpose>
<sub> = softwareSystem "<Domain> — <Sub>" "<what this sub-domain is>." "Subdomain,<Sub>" {
    <pfx>_service_a = container "service-a" "…" "" "Service"
    <pfx>_service_b = container "service-b" "…" "" "Service"
    <pfx>_pg = container "Cloud SQL Postgres (per-service DBs)" "Each service owns its own DB." "" "Database"

    # intra-sub-domain relationships
    <pfx>_service_a -> <pfx>_service_b "…" "http"
}
```

Wire it into `workspace.dsl` — **inside** the domain group so grouping works via include:

```
group "BestOne" {
    group "<Domain>" {
        !include model/<domain>/inbound/inbound.dsl
        !include model/<domain>/<sub>/<sub>.dsl          # <-- new
    }
}
```

Add a container view so it's drillable:

```
container <sub> "<Sub>_Detail" "<Domain> <Sub> — services (detail)" {
    include *
    autolayout lr
}
```

Add a style for the `<Sub>` tag if you want a distinct colour (see the styles block).

---

## 3. A whole new domain (e.g. Buying, Sales)

1. Pick an id prefix (Buying → `by_`, Sales → `sa_`). Record it in `SKILL.md`'s prefix table + README.
2. Create `model/<domain>/` with one fragment per sub-domain (as in §2) and a
   `model/<domain>/<domain>.rels.dsl` for its internal cross-sub-domain edges.
3. In `workspace.dsl`, add a sibling group inside `BestOne` and include the fragments:
   ```
   group "BestOne" {
       group "Logistics" { … }
       group "Buying" {
           !include model/buying/<sub>/<sub>.dsl
           …
       }
   }
   !include model/buying/buying.rels.dsl
   ```
4. Add inter-domain edges in `model/cross-domain.dsl` (included last, after all domains are defined):
   ```
   sa_salesorder_service -> in_goodsin_api "Release-to-logistics" "Kafka" "Event"
   ```
   Any existing `ref_*` placeholder that this domain actually is (e.g. `ref_bi4_sales_cores`) should
   now be replaced by the real containers, and edges re-pointed to them.
5. Add container views for the new sub-domains and a domain style/colour.
6. Lint, then render.

---

## Reconciling a current-state map into the model

When a sub-domain is (re)mapped via the observed+declared method, you get a merged backbone/diff of
nodes and edges. Translate them:

- Each **service** → a container (home = its authoritative sub-domain).
- Each **datastore** → shared L0 system if genuinely shared, else a per-sub-domain DB container.
- Each **topic/queue** → a container inside the relevant bus system; edges become
  service→topic / topic→service with `Event`/`Queue` tags.
- Each **external** → an `ext_` system; each **unmapped cross-ref** → a `ref_` placeholder.
- Carry the observed/declared/inferred provenance onto every edge.

Keep the merge deterministic (dedupe by canonical name, not by identifier — the same real service can
appear under different ids across sources) and drop-detect (every input node/edge survives into the
model). Then lint.
