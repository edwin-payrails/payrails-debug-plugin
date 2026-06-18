# Grafana reference

Grafana is Payrails' observability stack — logs (Loki), metrics (Prometheus), traces
(Tempo), dashboards, and alerts. We query it through the **`gcx` CLI** (Grafana's official
command-line tool), which you run in the shell. **Do not use any Grafana MCP server** — a
dormant `grafana` MCP may be declared in config but is intentionally unauthenticated and
reserved for future use; ignore it and drive every Grafana operation through `gcx`.

## Grafana instance

- **Grafana Cloud:** `https://payrails.grafana.net` — the single stack for logs, metrics,
  traces, and dashboards. *(The old self-hosted `grafana.telemetry.payrails.io` was retired
  in June 2026; ignore any older references to it.)*

## Who manages access

- **Quang Ngo** (`@Quang` in Slack) — platform lead; manages Grafana Cloud roles and
  permissions on `payrails.grafana.net`. Access/permission problems are an admin grant from
  him, not something to fix in config.

## Prerequisite — gcx must be installed and logged in

Grafana work only succeeds if the user has done the one-time setup (see README): installed
`gcx` and run `gcx login --server https://payrails.grafana.net` (OAuth). Sanity-check before
relying on it:

```
gcx config check
```
- Expected: `Auth method: oauth`, `Connectivity: online`, current context `payrails`.
- If it says `server is required` / wrong context: `gcx config use-context payrails`, then re-check.
- If login is denied, or a command returns `403 ... lacks required permissions` on a core
  operation (logs/metrics/datasources), the user's Grafana role is missing the **Assistant**
  permissions — that's an admin grant (ping Quang), not a config fix.

## How to use gcx (read this first)

- **Run gcx in the shell** for every Grafana operation: `gcx <group> <subcommand> ...`.
- **Self-discover — don't guess.** gcx is built to be driven by an agent. If you need a
  command or flag not listed below, run `gcx help-tree --depth 1 -o text` to orient, then
  `gcx <group> --help` / `gcx <group> <subcmd> --help` for exact flags. This reference covers
  the common Payrails paths; gcx can do more, and `--help` is authoritative.
- **JSON / parsing.** Under Claude, gcx auto-emits agent/JSON output. When piping, **always add
  `2>/dev/null`** (gcx writes hints to stderr that break JSON parsers) — never `2>&1`. Use
  `--json list` to discover fields and `--json field1,field2` to select them. `jq` may be
  absent; prefer `python3 -c` for parsing.
- **Datasource UID, never the display name**, for `-d`. The fixed UIDs on this stack:
  - Prometheus (metrics): **`grafanacloud-prom`**
  - Loki (logs): **`grafanacloud-logs`**  *(there is also a datasource literally named `loki`
    with a different UID — do not use it; app logs live in `grafanacloud-logs`)*
  - Tempo (traces): **`grafanacloud-traces`**
  - If a UID ever 404s, reconfirm with `gcx datasources list -o json 2>/dev/null`.
- **Time flags.** Relative (`--since 1h`, or `--from now-1h --to now`); range queries need
  `--step` with a unit (`1m`, `300s` — not `300`). You can't chain subtractions
  (`now-6h-1m` is invalid → use `now-361m`). **`--since` only accepts small units** (`1h`,
  `30m`) and rejects multi-day values like `7d` — for windows beyond a few hours use
  `--from now-720h --to now`. `--limit` is a flag, **never** put `| limit N` inside LogQL.

**Operating principle — try the documented patterns first, then adapt.** The patterns below are
known-useful starting points from the SE team; **always try them first**. But they are *starting
points, not a closed checklist*: labels, UIDs, and namespaces can change over time, and new kinds
of questions come up. So if a documented query returns nothing, an approach fails, or the
situation doesn't match what's written here, **don't stop** — discover (`gcx logs labels`,
`gcx datasources list`, `gcx <cmd> --help`, `gcx help-tree`), reason about *why* it failed, and
try alternatives using gcx's full capability. Prefer the noted path; fall back to genuine
investigation whenever it doesn't fit.

## What gcx can do (capability map)

- **Logs** — `gcx logs query|labels|series` (LogQL over Loki). Service-level reasoning trail.
- **Metrics** — `gcx metrics query|labels|metadata` (PromQL over Prometheus). Rates, latency, health.
- **Traces** — `gcx traces query|get|labels` (TraceQL over Tempo). Request flow across services,
  per-span timing. *(New on Cloud — the old setup could not query traces.)*
- **Dashboards** — `gcx dashboards list|get`. Find and read dashboards and their panel queries.
- **Alerts & incidents** — `gcx alert ...` (rules, instances, contact points), `gcx irm ...`
  (incidents, on-call).
- **Raw Grafana API** — `gcx api <path>` (authenticated passthrough) for anything without a
  dedicated command — notably resolving a shared `/goto/<uid>` link (below).

## Resolving a shared Grafana link (`/goto/<uid>`)

SEs often paste a Grafana short link like `https://payrails.grafana.net/goto/sbtqcz`. Resolve it
to the underlying query, then run that query yourself:

```
gcx api /api/short-urls/<uid> -o json 2>/dev/null
```
`<uid>` is the last path segment of the `/goto/...` link. The response's `path` field is a
**URL-encoded** Grafana Explore state — percent-decode it to read the `datasource` (UID) and the
`expr` (the LogQL/PromQL). Then run that query via the matching `gcx logs query` /
`gcx metrics query` (`-d <uid>`) to reproduce what the link shows and investigate.

## What to use Grafana for during debugging

Pick the approach that matches the question.

### Transaction-level (by execution ID or payment ID)

When the SE gives an execution ID or payment ID and wants to know *what happened*, **Loki logs**
show the service-level reasoning trail — what each service logged, what errors occurred, the
surrounding events, and the `TraceID` tying related events together. The Payrails API and
merchant portal show the *outcome* (payment failed with reason X); Loki shows the code path
leading to it. Used alongside:

- **Temporal** (see `temporal.md`) — workflow orchestration state. Use for workflow-level behaviour.
- **Tempo traces** (`gcx traces`) — request flow across services, per-span timing. Use when the
  question is *where time was spent* or *which service handled a span*. Pull a `TraceID` from
  Loki, then inspect the trace (see "Traces" below).

Typical Loki path: query filtered by the execution/payment ID, plus merchant and environment.

**Diagnosing trigger-step failures** (authorize / capture / notification steps run inside
`MainModularWorkflow`): the canonical place to read the *real* cause is the log line `Trigger is
called, but there were errors during handling` — filter by the execution id and read its
`Error` / `ErrorVerbose` / `error_code` fields. Common cases this surfaces:
- **Scope / credential failures** — `error_code: request.unauthorized` (stack `oauth.ValidateScope`)
  means the caller's token lacked the scope for that operation; the step is blocked *before* any
  PSP call (not a decline or infra fault).
- **Field-mapping failures** (e.g. a field empty/missing in the notification sent to the merchant —
  the rendered notification body itself is **not** logged): the `Error` lists which source fields
  the mapping couldn't read (e.g. `Couldn't get N field(s) from the previous step result:
  authorize.paymentComposition[0].paymentInstrumentData.<field>`). An empty field usually means its
  **source was absent in the prior step's result**, not that the merchant never sent it — check the
  original request / `JWT claims validated` lines to find where it was lost.

### Performance and health (by metric)

For rates, latency, or trends — "is authorization rate down for merchant X", "has checkout
latency spiked", "are refunds processing" — use **`gcx metrics query`** (PromQL). For a quick
visual scan, the Business Metrics dashboard panels cover common signals.

### Dashboard exploration (when the right query isn't obvious)

When you don't yet know what to query, `gcx dashboards list` + reading a dashboard's panels lets
you discover what's measured and how.

## Logs (Loki) — `gcx logs`

Loki logs are structured JSON with rich labels, making merchant-scoped queries fast.

**Useful stream labels:** `merchant_name`, `cluster`, `namespace`, `app`, `component`,
`container`, `environment`, `job`, `service_name`, `stream`.

**Critical: always scope to the right environment and merchant before querying.** If the SE
hasn't specified the environment, ask first — results from the wrong environment mislead and
waste time.

**Staging** — try in order:

1. `namespace="rc-backend"` (confirmed working; this is the actual staging namespace — a bare
   `staging` namespace does **not** exist on this stack):
   ```
   gcx logs query -d grafanacloud-logs '{namespace="rc-backend"} |= "<execution-or-payment-id>"' --since 1h --limit 100
   ```
   The `rc-` prefix matches the staging API base URL (`rc-api.staging.payrails.io`).

**Production** — try in order (which works depends on how the merchant is deployed):

1. Dedicated namespace (merchants on their own Kubernetes namespace):
   ```
   gcx logs query -d grafanacloud-logs '{namespace="<merchant>", app="backend"} |= "<id>"' --since 1h --limit 100
   ```
2. Shared backend (`merchant_name` label — merchants on the shared `backend` namespace, where
   `namespace="backend"` for everyone and the per-merchant label is `merchant_name`):
   ```
   gcx logs query -d grafanacloud-logs '{merchant_name="<merchant>", app="backend"} |= "<id>"' --since 1h --limit 100
   ```
3. **Fallback — discover the right labels first** if both return nothing:
   ```
   gcx logs labels -d grafanacloud-logs -l namespace
   gcx logs labels -d grafanacloud-logs -l merchant_name
   ```
   Check which values exist for this merchant, then build the filter from what you find.

**Exclude noisy log types for large windows** to surface signal and stay under the limit:
```
gcx logs query -d grafanacloud-logs '{merchant_name="<merchant>", app="backend"} |= "<execution-id>" != "Rule evaluation failed" != "Query" != "JWT claims validated"' --since 6h --limit 200
```
`Rule evaluation failed` lines are emitted in bulk by the routing engine on every authorize
attempt (normal — it evaluates all rules and skips non-matching ones).

**LogQL gotchas:**
- `--limit` is a flag (default 50). **Don't trust `--limit 0` as "uncapped"** — it can return
  *fewer* lines than an explicit cap (a server default applies). Use a high explicit `--limit`
  (e.g. `200`) and paginate (see "Cover a long window") for full coverage. `{...} | limit 5`
  inside LogQL is invalid.
- **To tell which operations ran (authorize, capture, cancel, …), read the `WorkflowType`
  field** in the JSON log line (`AuthorizeWorkflow`, `CaptureWorkflow`, `CancelWorkflow`,
  `ClientInitWorkflow`, `MainModularWorkflow`, `ReceivePSPRedirectWorkflow`, …) — **not** a
  substring match. `|= "capture"` / `|= "checkout"` give **false positives** by matching JWT
  permission scopes embedded in lines (`capture:create`, `consumercheckout:read`). To answer
  e.g. "did the merchant capture this execution?", filter by the execution id, then tally the
  `WorkflowType` values (e.g. a `CancelWorkflow` with no `CaptureWorkflow` = authorized then
  cancelled, never captured).
- **Large results spill to a file:** gcx writes oversized output to a temp `gcx-results-*.json`
  and returns a JSON envelope with a `spilled_to` path instead of the rows — read that file
  rather than parsing stdout.
- Only **stream labels** (those returned by `gcx logs labels`) work inside `{}`. Fields from
  `| json` / `| logfmt` are *extracted* — filter on them *after* the parser stage, not in the
  selector (a stream selector on an extracted field silently matches nothing). Append
  `| __error__=""` after `| json` to drop unparsable lines.
- For metric LogQL (`rate`/`count_over_time`), always aggregate (`sum by(...)`) — one series per
  label combo otherwise hits the 20k-series limit.
- **TraceID is present in log lines** as `TraceID: <hex>`. Pull it from a relevant log entry to
  pivot into Tempo (next section).
- **DB-query logs were dropped on Cloud** (volume reduction). For DB-level detail use **traces**
  with the span attribute `db.*` instead of Loki.

**Cover a long window:** if `--limit` fills before the full range, re-query with `--from` set to
just after the last timestamp you received, and repeat.

## Traces (Tempo) — `gcx traces`  *(new capability on Cloud)*

Use when you have a `TraceID` (from Loki) or need request flow / per-span timing.

```
# Inspect one trace by ID (positional arg) in agent-friendly form
gcx traces get -d grafanacloud-traces <trace-id> --llm -o json

# Search traces (e.g. errored or slow spans for a service)
gcx traces query -d grafanacloud-traces '{ resource.service.name = "<svc>" && status = error }' --since 1h
gcx traces query -d grafanacloud-traces '{ resource.service.name = "<svc>" && duration > 1s }' --since 1h

# Discover attribute names / values
gcx traces labels -d grafanacloud-traces
gcx traces tags -d grafanacloud-traces -l resource.service.name --llm -o json
```
**TraceQL gotchas:** custom attributes need a scope prefix — `resource.service.name`,
`span.http.status_code` (bare `service.name` is a parse error). Intrinsics are unscoped:
`name`, `duration`, `status` (`error`/`ok`/`unset`), `kind`. Use `--llm -o json` for analysis.
Workflow: `traces labels`/`tags` (discover) → `traces query` (find IDs) → `traces get --llm`.

## Metrics (Prometheus) — `gcx metrics`

```
# Instant query
gcx metrics query -d grafanacloud-prom 'up{job="backend"}'

# Range query (rate needs a window; step needs a unit)
gcx metrics query -d grafanacloud-prom 'rate(http_requests_total[5m])' --from now-1h --to now --step 1m

# Does a metric exist / what type?
gcx metrics metadata -d grafanacloud-prom -m payrails_payment_status_gauge
gcx metrics labels -d grafanacloud-prom -l provider_name
```

**Native histograms (Cloud change):** classic histogram metrics (`*_bucket`, `*_count`,
`*_sum`) were converted to **native histograms**. Update old queries — drop the `_bucket`
suffix and the `le` aggregation:
- `histogram_quantile(0.95, sum by (le) (rate(X_bucket[5m])))` → `histogram_quantile(0.95, sum(rate(X[5m])))`
- `X_sum / X_count` → `histogram_avg(X)`;  `X_count` → `histogram_count(X)`;  `X_sum` → `histogram_sum(X)`

Don't use `--time` (instant) with over-time aggregations (`increase()`, `*_over_time()`); use
`--from`/`--to` so the window defines the answer.

## Dashboards — `gcx dashboards`

```
# List all dashboards (name == legacy UID, plus title/folder), then filter client-side
gcx dashboards list -o json 2>/dev/null
# Read one dashboard's full definition (panels + their queries)
gcx dashboards get <uid> -o json 2>/dev/null
```
**Use `list` + client-side filter, not `search`** — `gcx dashboards search` returns 403 for the
SE role (a separate, ungranted search-API permission); `list` works and covers our needs.

### Business Metrics dashboard

`Payrails / Business Metrics`, UID **`9qv3A94Sz`** (unchanged on Cloud) — the main merchant-
performance surface. Read it with `gcx dashboards get 9qv3A94Sz -o json`.

**Template variables that matter:** `merchant`, `provider_name` (PSP: adyen, checkout, klarna,
…), `cluster`, `namespace`, `service`, `payment_method`, `processing_type`, `currency`,
`interval`, `percentile`.

**Notable panel sections:** Payments Statuses (auth rates, CIT/MIT split, completed vs created,
failures by result); Authorizations (rate, success/failure, reasons); PSP view – Global;
Execution Statuses (by workspace/workflow version); SLA – critical endpoints (latency: client
init, authorize, vault proxy).

**Interpretation patterns — last-resort hypotheses, not first-line checks.** Only treat a graph
signal as "the cause" after ruling out merchant-side and Payrails-side issues:
- **Payments Authorized Rate** — a PSP line dropping below its typical band *might* mean that PSP
  is underperforming. A drop alone isn't proof; corroborate.
- **Payments Completed vs Created** — a PSP's bar missing/flat when usually present *might* mean
  it stopped working. Corroborate before concluding.
- **Latency graphs** — an endpoint's latency elevated for a merchant may point to a problem on
  that code path. Compare against the same merchant's historical baseline; don't compare across
  merchants or services.

Other payment-related dashboards exist — find them via `gcx dashboards list` filtered by keyword
(merchant, PSP, "psp", "sla", "business", "payment") and use judgment on relevance.

## Investigating PSP-level health (a last-resort hypothesis)

SEs rarely get problems framed as "PSP X is down" — merchants report symptoms (failures,
declines, broken checkout). PSP-level investigation is a *hypothesis* you reach for after ruling
out merchant-side and Payrails-side causes. When it *is* the right hypothesis, this sequence has
proven effective in a few calls:

1. **Find PSP/merchant dashboards** — `gcx dashboards list` filtered by the PSP or merchant name;
   fall back to Business Metrics.
2. **Query the metric directly, scoped tightly:**
   ```
   gcx metrics query -d grafanacloud-prom 'payrails_payment_status_gauge{operation="Authorize", provider_name="<psp>"}' --from now-6h --to now --step 5m
   ```
   This reveals whether the issue is PSP-wide or isolated to one merchant.
3. **Break down by failure reason** — add `result` and `merchant_name` groupings. This often
   turns a vague "PSP problem" into a specific cause (e.g. one merchant with `InsufficientBalance`
   dominant → merchant-side routing/config, not PSP infrastructure).

## Alerts, incidents, on-call (when relevant)

```
gcx alert rules list -o json 2>/dev/null
gcx alert instances list --state firing -o json 2>/dev/null
gcx irm incidents list -o json 2>/dev/null
gcx irm oncall schedules list -o json 2>/dev/null
```

## Explore / ad-hoc

For ad-hoc queries without a pre-built dashboard, compose `gcx logs query` / `gcx metrics query`
/ `gcx traces query` directly. Use `gcx <group> --help` to discover options as needed.
