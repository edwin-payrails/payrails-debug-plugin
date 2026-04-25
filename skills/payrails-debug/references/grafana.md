# Grafana reference

## Grafana instances

- **Staging logs (Loki):** `https://grafana.telemetry.payrails.io` — this is the one we use for debugging merchant issues
- **Grafana Cloud (traces):** `https://payrails.grafana.net` — used by Quang Ngo's team for distributed traces

## Who manages Grafana access

- **Quang Ngo** (`@Quang` in Slack) — manages service accounts on `payrails.grafana.net`
- **Michael Shebeko** (`@Shebeko`) — platform engineer, done the Grafana MCP setup himself
- **Bishoy Atif** — also working on Grafana MCP integration (Apr 2026, #platform thread)

## How to use this reference

The patterns below are known-useful starting points from the SE team's experience. They are hints, not rules. Use Grafana's full capabilities — navigating dashboards, running custom queries, exploring logs — to investigate whatever the current problem actually needs. Use the patterns when relevant, ignore them when not. Always try the primary approach first; fall back only when it fails.

## Available capabilities via Grafana MCP

The Grafana MCP server connects to `grafana.telemetry.payrails.io` and exposes the following. Always try the primary approach first — if it fails, use the fallback.

**Datasources configured (12 total, most relevant listed):**
- `cortex` (Prometheus) — main metrics store, default datasource
- `loki` — log aggregation
- `tempo` — distributed tracing
- `alertmanager` — alerting
- Multiple CloudWatch, Snowflake, etc. for specific needs

**Core capabilities that work:**
- **Datasource discovery** (`list_datasources`) — call first in an unfamiliar environment
- **Loki log queries** (`query_loki_logs`) — rich structured JSON logs with extensive labels (merchant_name, cluster, namespace, service_name, etc.). TraceID is present in logs for correlation.
- **Live PromQL** (`query_prometheus`) — run metric queries directly with custom filters and time ranges
- **Dashboard search** (`search_dashboards`) — by keyword. Try specific keywords first (e.g. "psp", "sla", the merchant or PSP name). If they return nothing useful, fall back to broader terms like "business", "payment", or "merchant". The business metrics dashboard often surfaces from these broader terms.
- **Dashboard structure** (`get_dashboard_summary`) — low-cost panel inventory, use before querying
- **Panel query extraction** (`get_dashboard_panel_queries`) — extracts the exact PromQL or LogQL a panel runs, with template variables still embedded. This is the most valuable feature for understanding what a panel measures.

**Panel image rendering (`get_panel_image`):**
Try this whenever a quick visual signal would help. If it succeeds, use the rendered image directly. If it returns a "No image renderer available/installed" error, fall back to `get_dashboard_panel_queries` + `query_prometheus` to fetch the underlying data and interpret it numerically.

**Tempo trace querying (`tempo_get-trace` and related):**
Try this whenever you have a TraceID and need trace details. If it succeeds, use the result directly. If the tools aren't available or return errors, fall back to: extract TraceID from Loki logs and hand off to the SE by providing the Grafana UI URL for them to view the trace in browser.

## What to use Grafana for during debugging

Grafana covers multiple kinds of investigation. Pick the approach that matches the question.

### Transaction-level investigation (by execution ID or payment ID)

When the SE has provided an execution ID or payment ID and wants to understand *what happened*, Loki logs are one of several views available. Specifically, Loki shows the service-level reasoning trail — what each service logged, what errors occurred, what the surrounding events were. The Payrails API and merchant portal show the outcome (e.g. a payment failed with reason X); Loki shows the code path leading to that outcome, surrounding context, and the TraceID tying related events together.

Other tools give different views of the same transaction and are often used alongside Loki:

- **Temporal** (see `temporal.md`) — workflow orchestration state: which workflow ran, what activities it executed, the inputs and outputs between steps, and final workflow state. Use when the question is about workflow-level behaviour rather than service-level logs.
- **Tempo** (Grafana's distributed tracing datasource, when accessible) — request flow across services, per-span timing. Use when the question is about where time was spent or which service handled a specific span.

For deep transaction-level debugging, choose the tool that matches the question you're asking, and combine when one view isn't enough.

Typical Loki pattern: query Loki filtered by the execution or payment ID, plus merchant and cluster. See "Log queries (Loki)" below for label and query details.

### Performance and health investigation (by metric)

For questions about rates, latency, or trends — "is authorization rate down for merchant X", "has latency spiked on the checkout endpoint", "are refunds processing normally" — Prometheus metrics via `query_prometheus` is the right path. For a quick visual scan, the business metrics dashboard panels cover common signals.

### Dashboard exploration (when the right query isn't obvious)

When you don't yet know what metric to query, `search_dashboards` and panel inspection via `get_dashboard_panel_queries` let you discover what's measured and how. Useful when entering an unfamiliar area of the platform or when the SE's question is broad.

## Log queries (Loki)

Loki logs are structured JSON with rich labels, making merchant-scoped queries fast.

**Useful labels:** `merchant_name`, `cluster`, `namespace`, `app`, `component`, `container`, `environment`, `job`, `service_name`, `stream`.

**Critical: always scope to the right environment and merchant before querying.**

If the SE hasn't specified the environment, ask before querying. Results from the wrong environment are misleading and waste time.

**Staging:** All merchants share a single `staging` Kubernetes namespace. Filter by `namespace`:
```
{namespace="staging", app="backend"} |= "<execution-or-payment-id>"
```

**Production:** Two approaches — try them in order. Which works depends on how that merchant is deployed.

1. **`namespace` approach** (original guidance — works for merchants on dedicated Kubernetes namespaces):
   ```
   {namespace="<merchant>", app="backend"} |= "<execution-or-payment-id>"
   ```

2. **`merchant_name` approach** (confirmed working for Careem Apr 2026 — merchants on the shared `backend` Kubernetes namespace):
   ```
   {merchant_name="<merchant>", app="backend"} |= "<execution-or-payment-id>"
   ```
   On the shared backend cluster, `namespace` is `"backend"` for all merchants — the per-merchant label is `merchant_name`, which Payrails adds at log time.

3. **Fallback — discover the right labels first** if both return zero results. Call these before querying:
   ```
   list_loki_label_values(datasourceUid="loki", labelName="namespace")
   list_loki_label_values(datasourceUid="loki", labelName="merchant_name")
   ```
   Check which values exist for this merchant, then build the filter from what you find.

**Common pattern — filter by execution or payment ID:**
```
{merchant_name="<merchant>", app="backend"} |= "<execution-or-payment-id>"
```

**For large time windows, exclude noisy log types** to stay within the 100-entry limit and surface the signal faster:
```
{merchant_name="<merchant>", app="backend"} |= "<execution-id>" != "Rule evaluation failed" != "Query" != "JWT claims validated"
```
`Rule evaluation failed` entries are generated in bulk by the routing engine on every authorize attempt (normal — the engine evaluates all rules and skips ones that don't match). Excluding them avoids burning your limit on noise.

**`query_loki_logs` required parameters** — these caused a hard error when missing or mis-named:
- `datasourceUid` — **required**, even though it looks optional. For this Grafana instance, Loki's UID is `"loki"`. If unsure, call `list_datasources` first to confirm.
- `logql` — the LogQL query string. Parameter is named `logql`, not `query`.
- `startRfc3339` / `endRfc3339` — time bounds in RFC3339 format. Not `since`/`until`.
- `limit` — row cap passed as a tool parameter, NOT inside the LogQL string. `{...} | limit 5` is invalid LogQL and returns a parse error.
- `direction="forward"` — add this when investigating a flow chronologically (oldest events first).

**Handling large result sets:** If 100 entries fill the limit before covering your full time window, run follow-up queries with `startRfc3339` set to just after the last timestamp you received. Repeat until you've covered the range you need.

**Logs contain TraceID** — present in log lines as `TraceID: <hex>`. To investigate a trace, extract the TraceID from relevant log entries. If Tempo trace tools are available, query directly with the TraceID. If not, provide the SE with the Grafana UI URL for the trace.

## Dashboard usage for debugging

### Business metrics dashboard

Dashboard name: `Payrails / Business Metrics` (UID: `9qv3A94Sz`). This is a well-known debugging surface for merchant performance questions.

**Template variables that matter most for merchant debugging:**
- `merchant` — the specific merchant experiencing issues
- `provider_name` — PSP name (adyen, checkout, klarna, etc.)
- `cluster`, `namespace` — environment isolation
- `service`, `payment_method`, `processing_type`, `currency`, `interval`, `percentile` — further filters

**Notable panel sections and what they cover:**
- **Payments Statuses** — authorization rates, CIT/MIT split, completed vs created, failures by result
- **Authorizations (excl./incl. Notifications)** — authorization rate, success/failure rates, failure reasons
- **PSP view - Global** — operations across PSPs
- **Execution Statuses** — by workspace and workflow version
- **SLA - critical endpoints** — latency panels (client init, authorize, vault proxy)

### Interpretation patterns from the SE team

**These are last-resort hypotheses, not first-line checks.** Only treat a signal on these graphs as "the cause" after ruling out merchant-side and Payrails-side issues in the usual debugging flow.

- **Payments Authorized Rate** — if a PSP's line drops unusually compared to its typical band, that PSP *might* be underperforming. A drop alone isn't proof; combine with other evidence.
- **Payments Completed vs Created** — if a PSP's bar is missing or flat at the current time when it's usually present, that PSP *might* have stopped working entirely. Same caveat — corroborate before concluding.
- **Latency graphs** — if a specific endpoint's latency is noticeably elevated for a merchant, that may indicate a problem on that code path. Compare against the same merchant's historical baseline; don't compare across merchants or services.

### Other dashboards

Other payment-related dashboards exist in the Grafana instance. If business metrics doesn't cover the current question, search for them via `search_dashboards` and use your judgment on whether they're relevant to the problem. Specific patterns for these dashboards to be documented as they emerge.

## Investigating PSP-level health (as a last-resort hypothesis)

SEs rarely receive problems framed as "PSP X is having trouble" — merchants report symptoms (payments failing, checkout broken, declines). PSP-level investigation is a *hypothesis* you reach for after ruling out merchant-side and Payrails-side causes. It is not a first-line check; it's a hypothesis to test once other, more common, causes have been excluded.

When PSP health *is* the right hypothesis to test, the following sequence has proven effective in 3–5 tool calls:

1. **Search dashboards for PSP-specific views** — `search_dashboards` with the PSP name or the merchant name. If no specific dashboard surfaces, fall back to business metrics.
2. **Query the metric directly, scoped tightly** — use `query_prometheus` with `provider_name="<psp>"` across all affected merchants over the relevant time range. This reveals whether the issue is PSP-wide or isolated.
3. **Break down by failure reason** — query `payrails_payment_status_gauge{operation="Authorize", provider_name="<psp>"}` broken down by `result` and `merchant_name`. This often turns a vague "PSP problem" hypothesis into a specific cause (for example: one merchant with `InsufficientBalance` as dominant failure reason — pointing to merchant-side routing or config, not PSP infrastructure).

This pattern produces a concrete hypothesis with supporting data. Prefer it over manual dashboard clicking when PSP health is under investigation.

## Explore (ad-hoc queries)

*Grafana's Explore interface is used by some team members for ad-hoc log and metric queries that don't have a pre-built dashboard. Specific patterns to be documented — ask the team.*