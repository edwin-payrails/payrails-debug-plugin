# Grafana reference

Grafana is Payrails' observability stack — logs (Loki), metrics (Prometheus), traces
(Tempo), dashboards, and alerts. We query it through the **Grafana MCP** (the hosted Grafana
Cloud MCP, declared as `grafana` in `.mcp.json`). Its tools are exposed to you directly
(`query_loki_logs`, `query_prometheus`, `search_dashboards`, the `tempo_*` trace tools, etc.) —
use them for every Grafana operation.

## Grafana instance

- **Grafana Cloud:** `https://payrails.grafana.net` — the single stack for logs, metrics,
  traces, and dashboards. *(The old self-hosted `grafana.telemetry.payrails.io` was retired in
  June 2026; ignore older references to it.)*

## Who manages access

- **Quang Ngo** (`@Quang` in Slack) — platform lead; manages Grafana Cloud roles/permissions.
  Access/permission problems are an admin grant from him, not a config fix.

## Prerequisite — the Grafana MCP must be connected + authorized

The `grafana` MCP authenticates via **browser OAuth** on first use. If its tools aren't
available yet, the agent will surface an authorize URL — open it, **Allow** (Read access; "Write
access — you don't have permission" is expected and fine, we only read). Confirm in `/mcp` that
`grafana` is **Connected**. This requires the Grafana **Assistant** role (admin-granted by the
platform team); if authorization is denied, that's a role grant — ping Quang, not a config fix.

## How to use the MCP (read this first)

- **Use the `grafana` MCP tools** for every Grafana operation — they're already exposed to you.
- **Operating principle — try the documented patterns first, then adapt.** The patterns below
  are known-useful starting points from the SE team; **always try them first**. But they are
  *starting points, not a closed checklist*: labels, UIDs, dashboards, and metrics can change
  over time, and new kinds of questions come up. So if a documented query returns nothing, a tool
  errors, or the situation doesn't match what's written here, **don't stop** — discover
  (`list_loki_label_values`, `list_datasources`, `query_loki_stats`, `list_prometheus_label_values`),
  reason about *why* it failed, and try alternatives. Prefer the noted path; fall back to genuine
  investigation whenever it doesn't fit.
- **Datasource UID, always explicit.** Every query tool needs a `datasourceUid`. The fixed UIDs:
  - Prometheus (metrics): **`grafanacloud-prom`**
  - Loki (logs): **`grafanacloud-logs`**  *(there are other loki/prom datasources — alert-state-history, usage-insights, ml-metrics — use the `grafanacloud-logs`/`grafanacloud-prom` ones for app data)*
  - Tempo (traces): **`grafanacloud-traces`**
  - If a UID ever 404s, reconfirm with `list_datasources`.
- **Time params are structured RFC3339, and the param names differ per tool** (gotcha):
  - Loki (`query_loki_logs`): `startRfc3339` / `endRfc3339` (RFC3339 only — *no* `since`).
  - Prometheus (`query_prometheus`): `startTime` / `endTime` — accepts relative (`now`, `now-1h`); **`endTime` is required even for an instant query**.
  - Tempo (`tempo_traceql-search`): `start` / `end`.
- **Loki limits — aggregate, don't dump.** Loki enforces a **30-day max window** (a wider range
  → HTTP 400) and caps response size (a large raw fetch gets truncated/spilled to a file). For
  counts/tallies (e.g. "which operations ran"), **aggregate inside LogQL** rather than pulling
  raw lines: `sum by (WorkflowType) (count_over_time({…} | json [30d]))` with `queryType="instant"`.
  Pre-check cheaply with `query_loki_stats` / `list_loki_label_values` before an expensive query.

## What the MCP provides (capability map)

- **Logs** — `query_loki_logs`, `list_loki_label_values`/`list_loki_label_names`, `query_loki_stats` (Loki). Service-level reasoning trail.
- **Metrics** — `query_prometheus`, `list_prometheus_label_values`/`list_prometheus_metric_names` (Prometheus). Rates, latency, health.
- **Traces** — `tempo_traceql-search`, `tempo_get-trace`, `tempo_get-attribute-names`/`-values`, `tempo_traceql-metrics-*` (Tempo). Request flow + per-span timing.
- **Dashboards** — `search_dashboards`, `get_dashboard_summary`, `get_dashboard_panel_queries`, `get_dashboard_by_uid`, `run_panel_query`.
- **Alerts / incidents / on-call** — alert-rule, incident, and on-call tools; plus Sift investigations.
- **`ask_assistant`** — sends a natural-language prompt to Grafana Assistant on the same stack (useful as a fallback when you're unsure which tool/query to use, or to interpret a shared link).

## What to use Grafana for during debugging

Pick the approach that matches the question.

### Transaction-level (by execution ID or payment ID)

When the SE gives an execution ID or payment ID and wants to know *what happened*, **Loki logs**
show the service-level reasoning trail — what each service logged, what errors occurred, the
surrounding events, and the `TraceID` tying related events together. The Payrails API and merchant
portal show the *outcome*; Loki shows the code path leading to it. Used alongside:

- **Temporal** (see `temporal.md`) — workflow orchestration state. Use for workflow-level behaviour.
- **Tempo traces** (`tempo_*`) — request flow / per-span timing. Pull a `TraceID` from Loki, then inspect the trace.

**Determining which operations ran** (authorize / capture / cancel / refund …): read the
**`WorkflowType`** field in the JSON log lines (`AuthorizeWorkflow`, `CaptureWorkflow`,
`CancelWorkflow`, `ClientInitWorkflow`, `MainModularWorkflow`, `ReceivePSPRedirectWorkflow`, …) —
**not** a substring match. `|= "capture"` / `|= "checkout"` give **false positives** by matching
JWT permission scopes embedded in lines (`capture:create`, `consumercheckout:read`). To answer
e.g. "did the merchant capture this execution?", filter by the execution id and **tally
`WorkflowType`** with an aggregate query (see the Loki example below). A `CancelWorkflow` with no
`CaptureWorkflow` = authorized then cancelled, never captured.
> **Caveat — modular vs legacy flows:** operations don't always appear as standalone
> `WorkflowType` values. On the **modular** workflow, authorize/capture/notification run as
> *trigger steps inside* `MainModularWorkflow` (no separate `AuthorizeWorkflow`/`CaptureWorkflow`
> type). So "no `CaptureWorkflow` in the tally" is conclusive only when *other* standalone
> op-types (e.g. `CancelWorkflow`) are present (legacy flow); on a modular-flow merchant, also
> check for capture-related **trigger/step** lines within `MainModularWorkflow` before concluding
> "no capture." (Also: a trigger can emit several `Trigger is called, but there were errors
> during handling` lines — read *all* of them, the informative one isn't always the newest.)

**Diagnosing trigger-step failures** (authorize / capture / notification steps run inside
`MainModularWorkflow`): the canonical place to read the *real* cause is the log line `Trigger is
called, but there were errors during handling` — filter by the execution id and read its
`Error` / `ErrorVerbose` / `error_code` fields. Common cases:
- **Scope / credential failures** — `error_code: request.unauthorized` (stack `oauth.ValidateScope`)
  means the caller's token lacked the scope for that operation; blocked *before* any PSP call.
- **Field-mapping failures** (e.g. a field empty/missing in the notification sent to the merchant —
  the rendered notification body itself is **not** logged): the `Error` lists which source fields
  the mapping couldn't read (e.g. `Couldn't get N field(s) from the previous step result:
  authorize.paymentComposition[0].paymentInstrumentData.<field>`). An empty field usually means its
  source was absent in the prior step's result, not that the merchant never sent it — check the
  original request / `JWT claims validated` lines to find where it was lost.

### Performance and health (by metric)

For rates, latency, or trends, use **`query_prometheus`**. For a quick visual scan, the Business
Metrics dashboard panels cover common signals.

### Dashboard exploration (when the right query isn't obvious)

`search_dashboards` + `get_dashboard_panel_queries` / `get_dashboard_summary` let you discover
what's measured and how.

## Logs (Loki) — `query_loki_logs`

Loki logs are structured JSON with rich labels, making merchant-scoped queries fast.

**Useful stream labels:** `merchant_name`, `cluster`, `namespace`, `app`, `component`,
`container`, `environment`, `job`, `service_name`, `stream`.

**Critical: always scope to the right environment and merchant before querying.** If the SE
hasn't specified the environment, ask first — wrong-environment results mislead and waste time.

**Staging:** `namespace="rc-backend"` (the actual staging namespace — a bare `staging` namespace
does **not** exist on this stack):
```
query_loki_logs(datasourceUid="grafanacloud-logs",
  logql='{namespace="rc-backend"} |= "<execution-or-payment-id>"',
  startRfc3339="<start>", endRfc3339="<end>", limit=50)
```

**Production** — try in order (which works depends on how the merchant is deployed):
1. Dedicated namespace: `{namespace="<merchant>", app="backend"} |= "<id>"`
2. Shared backend (`merchant_name` label — `namespace="backend"` for everyone, per-merchant label is `merchant_name`): `{merchant_name="<merchant>", app="backend"} |= "<id>"`
3. **Fallback — discover the labels first** if both return nothing:
   `list_loki_label_values(datasourceUid="grafanacloud-logs", labelName="namespace")` and `labelName="merchant_name"`. Build the filter from what exists.

**Tally operations (e.g. "did they capture?") — aggregate, don't dump raw lines:**
```
query_loki_logs(datasourceUid="grafanacloud-logs",
  logql='sum by (WorkflowType) (count_over_time({merchant_name="<merchant>", app="backend"} |= "<execution-id>" | json [30d]))',
  queryType="instant", startRfc3339="<start>", endRfc3339="<end>")
```

**Exclude noisy log types** when reading raw lines over a window:
`{merchant_name="<m>", app="backend"} |= "<id>" != "Rule evaluation failed" != "Query" != "JWT claims validated"`
(`Rule evaluation failed` lines are emitted in bulk by the routing engine on every authorize — normal.)

**LogQL gotchas:**
- Only **stream labels** (those from `list_loki_label_values`) work inside `{}`. Fields from
  `| json` / `| logfmt` are *extracted* — filter them *after* the parser stage, not in the
  selector. Append `| __error__=""` after `| json` to drop unparsable lines.
- For metric LogQL (`rate`/`count_over_time`), always aggregate (`sum by(...)`) — one series per
  label combo otherwise hits the series limit.
- **30-day max window** — a *hard cliff* at ~30d1h, so keep the range **strictly under** 30 days
  (exactly 30d-to-the-second still 400s) — and a **response-size cap**; prefer aggregates (above)
  over raw fetches for anything high-volume; for raw lines use a tight window + low `limit`.
- **TraceID is in log lines** as `TraceID: <hex>` — pull it to pivot into Tempo (below).
- **DB-query logs were dropped on Cloud** — for DB-level detail use **traces** with span attribute `db.*`.

## Traces (Tempo) — `tempo_*`

Use when you have a `TraceID` (from Loki) or need request flow / per-span timing.
- `tempo_get-trace(trace_id=..., datasourceUid="grafanacloud-traces")` — inspect one trace.
- `tempo_traceql-search(query='{ resource.service.name = "<svc>" && status = error }', datasourceUid="grafanacloud-traces", start=..., end=...)` — search.
- `tempo_get-attribute-names` / `tempo_get-attribute-values` — discover attributes.
**TraceQL scoping:** custom attributes need a scope prefix (`resource.service.name`, `span.http.status_code`); intrinsics are unscoped (`name`, `duration`, `status` = `error`/`ok`/`unset`). Note Tempo tools use `start`/`end` (not `startRfc3339`).

## Metrics (Prometheus) — `query_prometheus`

```
query_prometheus(datasourceUid="grafanacloud-prom", expr='<promql>', queryType="instant", endTime="now")
# range: add startTime + stepSeconds, queryType="range"
```

**`up{job="backend"}` does NOT work — don't use `up` for backend liveness.** The `job` label is
namespaced (`backend-stable-<service>-http`/`-workflow`, `backend-canary-…`, e.g.
`backend-stable-payment-http`); `backend` is not a valid value. *And* the `up` series only covers
**infra** jobs (node_exporter, cilium, kube-state, …) — backend app pods aren't scraped as `up`,
so `up{job="backend-stable-payment-http"}` is also empty. To check backend health, query a real
**app metric** filtered by the namespaced job, not `up`. Confirm any metric/job pairing with
`count by (job) (<metric>)` (or `list_prometheus_label_values labelName="job"`) before trusting it.

**Native histograms (Cloud change):** classic `*_bucket`/`*_count`/`*_sum` metrics were converted
to native histograms — drop the `_bucket` suffix and the `le` aggregation:
`histogram_quantile(0.95, sum by (le) (rate(X_bucket[5m])))` → `histogram_quantile(0.95, sum(rate(X[5m])))`;
`X_sum / X_count` → `histogram_avg(X)`; `X_count` → `histogram_count(X)`; `X_sum` → `histogram_sum(X)`.

## Dashboards

`search_dashboards(query="<keyword>")` **works** for the SE role — search by keyword
(merchant, PSP, "psp", "sla", "business", "payment"), then read panels with
`get_dashboard_panel_queries` / `get_dashboard_summary` (prefer these over `get_dashboard_by_uid`,
which returns a very large payload). `run_panel_query` executes a panel's query directly.

### Business Metrics dashboard

`Payrails / Business Metrics`, UID **`9qv3A94Sz`** — the main merchant-performance surface.

**Template variables that matter:** `merchant`, `provider_name` (PSP: adyen, checkout, klarna, …),
`cluster`, `namespace`, `service`, `payment_method`, `processing_type`, `currency`, `interval`, `percentile`.

**Notable panel sections:** Payments Statuses (auth rates, CIT/MIT split, completed vs created,
failures by result); Authorizations (rate, success/failure, reasons); PSP view – Global; Execution
Statuses (by workspace/workflow version); SLA – critical endpoints (latency).

**Interpretation patterns — last-resort hypotheses, not first-line checks.** Only treat a graph
signal as "the cause" after ruling out merchant-side and Payrails-side issues:
- **Payments Authorized Rate** — a PSP line dropping below its typical band *might* mean that PSP is underperforming; corroborate, a drop alone isn't proof.
- **Payments Completed vs Created** — a PSP's bar missing/flat when usually present *might* mean it stopped working; corroborate.
- **Latency graphs** — an endpoint's latency elevated for a merchant may point to a problem on that code path; compare against that merchant's own historical baseline, not across merchants.

## Investigating PSP-level health (a last-resort hypothesis)

SEs rarely get problems framed as "PSP X is down" — merchants report symptoms. PSP-level
investigation is a *hypothesis* you reach for after ruling out merchant-side and Payrails-side
causes. When it *is* the right hypothesis:
1. **Find PSP/merchant dashboards** — `search_dashboards` with the PSP or merchant name; fall back to Business Metrics.
2. **Query the metric directly, scoped tightly:**
   `query_prometheus(datasourceUid="grafanacloud-prom", expr='payrails_payment_status_gauge{operation="Authorize", provider_name="<psp>"}', queryType="range", startTime="now-6h", endTime="now", stepSeconds=300)`
   — reveals whether the issue is PSP-wide or isolated to one merchant.
3. **Break down by failure reason** — add `result` and `merchant_name` groupings. This often turns a vague "PSP problem" into a specific cause (e.g. one merchant with `InsufficientBalance` dominant → merchant-side routing/config, not PSP infra).

## Resolving a shared Grafana link (`/goto/<uid>`)

The MCP has no generic API passthrough, so it can't expand a `/goto/<uid>` short link directly.
Either ask the SE to open the link and share the underlying query + datasource (then run it via
`query_loki_logs` / `query_prometheus`), or use **`ask_assistant`** to have Grafana Assistant
interpret it on the same stack.

## Alerts, incidents, on-call

Use the MCP's alert-rule / incident / on-call tools when relevant (e.g. list firing alerts, list
incidents, on-call schedules). Discover exact tool names from the available `grafana` tools.

## Explore / ad-hoc

For ad-hoc queries, compose `query_loki_logs` / `query_prometheus` / `tempo_traceql-search`
directly. When you're unsure which tool or query fits, `ask_assistant` (natural language to
Grafana Assistant) is a useful fallback — but prefer the structured tools for anything you'll act on.
