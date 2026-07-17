# Phase A — the observed backbone (Datadog)

Datadog is authoritative for what it observes. Phase A builds a deterministic `observed` backbone; do
**not** trust the service catalog alone — it under-counts. Union multiple sources.

**Skill discovery first.** At the start of a Datadog session, in parallel: `load_datadog_skill('datadog/traces')`
and `list_datadog_skills(query=...)` with your topic keywords; load any clearly-matching skill it
points to. Also load `datadog/visualizations` if you'll chart anything. Skip re-loading a domain
whose skill you've already loaded this session.

## The A1–A6 sources (union them)

| Step | Query | Yields | Blind spot it covers |
|---|---|---|---|
| **A1 Owned services** | `search_datadog_services` `team:<tag>` | APM services + repo links | — |
| **A2 Namespace + ingress routing** | `analyze_datadog_logs` on the ingress/traefik service in the namespace, group by service name / request host / env | Every ingress-exposed service incl. **non-APM ones**, with public hostnames | Services missing from A1 |
| **A3 Outbound edges** | `search_datadog_service_dependencies(service=X, direction=downstream)` per service | Sync HTTP calls (internal + external) | — |
| **A4 Datastores / proxied deps** | raw `search_datadog_spans` / `aggregate_spans` per service; inspect `type:sql` / `type:queue` spans, `resource_name`, `operation_name`, `peer.hostname`, `db.instance`, `db.user` | Databases + sidecar-proxied deps | Dependency search shows these as `localhost` and misses them |
| **A5 Consumers (REQUIRED)** | Two-tier (below) | Named cross-team callers + owning team; residual unnamed IPs | `direction=upstream` is useless behind a shared ingress |
| **A6 pod-to-pod (fallback)** | `analyze_cloud_network_monitoring` (needs CNM permission) | In-cluster callers tracing missed | Only for residue IPs |

### A5 consumer identity — two-tier, validated
- **A5a PRIMARY — distributed tracing.** Trace context propagates *through* the ingress, so a caller's
  outbound span records the target host. Query everyone calling the domain's host:
  `aggregate_spans(query="@http.url_details.host:<service-host>", group_by=[service, team], COUNT)`.
  This names cross-team integrators **with owning team**. Exclude self-referential rows. A service may
  carry **two `team` tags** → rows duplicate per team; dedupe.
- **A5b RECONCILE — ingress client-IPs.** Filter the ingress by destination service + `env:prod`, group
  by client IP. Any IP with real volume **not** explained by a named A5a service = an uninstrumented
  caller — only that residue needs resolving.
- **A6/asset-inventory (residue only).** Internal `10.x` pod IPs resolve via k8s (pod→ownerRef→team).
  External egress IPs behind Cloud NAT do **not** resolve from the target cluster — CNM (all clusters
  report to the same Datadog org) is the mechanism that attributes them to the source workload; it's
  often permission-blocked. Free-text searching a pod IP across logs does **not** resolve it.

## Deterministic normalization (apply after A1–A5)
1. Drop infra/proxy nodes: the ingress controller, `metadata.google.internal`, `spring-boot-admin`
   (actuator poller — appears as a universal upstream), and platform sidecars.
2. Collapse peer hostnames → system + env: `keepr-dev.bestseller.tech` → `keepr` (dev).
3. Canonicalise external SaaS by host (`login.microsoftonline.com`→Microsoft Entra ID,
   `storage.googleapis.com`→GCS, `api.mailjet.com`→Mailjet, `*.confluent.cloud`→Confluent, …).
4. **Prod-only** scoping (env facet). Re-verify any dev/test-observed edge in prod or drop it.
5. **Exclude health/probe endpoints** when classifying edges (`/health*`, `/actuator/health`, `/ping`,
   `/ready`, `/live`, `/status`). k8s probes hit the pod directly and bypass ingress (absent from
   ingress logs) but DO appear in a service's own spans — apply the filter to span-derived edges.

## Facet & co-tenancy traps (these waste the most time — check the domain's `method-deltas.md`)

These are real deltas seen on BESTSELLER domains. Expect them; record any new ones in `method-deltas.md`.

- **`@db.*` / `@messaging.*` are NOT aggregatable facets** (0 buckets). Get datastores from **raw
  `type:sql` spans** (`resource_name` / `operation_name` — note `operation_name`, not `operationname`).
  Get messaging from **raw `type:queue` spans**, same fields. Custom-instrumented queue/DB work may use
  bespoke operation names (`getFromQueueOut`, `Consumer_save`) invisible to `type:queue`/`type:sql` —
  fall back to the service-dependency graph + the `*-oracle`/DBM companion services + raw span reads.
- **`@peer.service` is unreliable** — polluted by shared **Confluent Schema Registry** (`psrc-*.confluent.cloud`,
  makes unrelated co-tenants look coupled) and **Entra** `login.microsoftonline.com` auth noise. Exclude
  both as artifacts. Distinguish real Microsoft Graph/SharePoint traffic from Entra OIDC-userinfo login
  noise before drawing an edge.
- **Single shared Ambassador/Emissary ingress host** may front the whole domain (not per-service
  traefik), and its **access logs may not ship to Datadog** — so there's **no per-service public
  hostname and no client-IP reconcile from Datadog**. Recover hostnames/paths and caller identity in
  **Phase B** from repo IngressRoute CRDs. Add a URL-path filter to A5 for per-target attribution.
- **Consumer identity is the hard blind spot** — often not derivable from Datadog alone. This is the
  single strongest argument for the Phase B enrichment layer; treat A5 as "name who you can, list the
  rest as residue," not "must fully resolve in Datadog."
- **A shared k8s namespace** can span the whole domain → namespace can't scope a sub-domain; rely on the
  frozen inventory's team-tag assignment instead.

## Backbone output shape (`model/<sub-domain>-<batch>.json`, merged to `<sub-domain>-backbone.json`)
Top-level keys used by the merge + the diagrammer hand-off: `batch`, `layer`, `meta`, `services[]`
(name/team/version/prod_confirmed/role), `datastores[]` (name/system/hosting/db_instance/db_users/
used_by/schemas_observed), `brokers[]` (name/type/bootstrap/note), `edges[]` (from/to/type/transport/
direction/evidence/provenance/confidence), `consumers[]` (target/caller/team/calls_7d/transport/via/
note), `unresolved_ips[]`, `infra_excluded[]` (node/reason), `findings{}`. Every edge carries
`provenance` + `confidence`. **Unresolved prod callers are kept as first-class `Unresolved integrator ·
<IP>` nodes** with call volume + top endpoints — documented, never dropped.
