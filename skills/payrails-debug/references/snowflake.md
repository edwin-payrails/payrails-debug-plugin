# Snowflake reference

Payrails payment, billing, and anomaly data lives in Snowflake, queried through the
**`snowflake` MCP server** (`DWH.REPORTING.PAYRAILS_SCOPE_MCP`, bundled in this plugin). It's
the source of truth for **historical and aggregate** payment data — use it rather than
answering from general knowledge when a question is about that data.

> **Access.** Requires Snowflake `ANALYST` access and the MCP connected. If a tool returns an
> authorization error or the server isn't connected, see the **[Snowflake MCP Access](https://app.notion.com/p/384cc40840c181dd8facc51ca24325ec)**
> Notion guide (connect the MCP, request `ANALYST` via #help). For the full standalone usage
> guide, the `cortex-snowflake` skill in this plugin covers the same tools in more depth.

## When to reach for Snowflake vs the operational tools

Snowflake is the source of truth for payment, billing, and anomaly data. During debugging,
**use it freely whenever the question touches that data — prefer reaching for it over assuming
it's out of scope.** It's *strongest* for the pattern across many payments:

> **"What's the pattern across X over time?" → Snowflake** — sliced by merchant, provider,
> payment method, country, card network, decline reason, BIN, or metadata field.

Common cases (illustrative — **not** exhaustive, and **not** a closed list):
- Authorization / acceptance / success-rate **trends**, by provider, method, country, card network
- Decline-reason analysis — what's driving declines for a merchant, and how a reason **drifts over time**
- Provider/PSP performance, BIN and routing analysis, fees and reconciliation
- TPV, attempt counts, retry-recovery rate, volume / payment-method distribution
- The **impacted set of transactions** for a filter (an incident's blast radius — "how many txns matched this?")
- Anything a merchant sends in their request body, including **metadata fields**, and analysis over **raw PSP responses**
- 3DS / SCA authentication outcomes, and fraud / risk-check data
- Payment **anomalies / incidents** (see below)

**Single transactions too.** `dwh-core` holds individual transaction records — use Snowflake
for a *specific* payment when it's historical (older than Grafana/Temporal retention — Temporal
keeps ~5 days), when you need its **warehoused raw PSP response, metadata, or decline detail**,
or to pull the set of transactions matching a filter.

**The only carve-out:** the **live state of one in-flight payment right now** (current workflow
step, fresh logs/traces). Snowflake **lags real time**, so there Grafana/Temporal/the API are
the faster, authoritative first stop. Outside that, Snowflake is fair game — including looking
up a single historical transaction, and checking whether a single-payment symptom is part of a
wider trend.

**When unsure, use it.** Don't skip Snowflake on a payment-data question just because it
doesn't match an example here — the list can never be a reason *not* to query it.

## Three kinds of tools — they behave differently

| Kind | Tools | Returns |
|---|---|---|
| **Cortex Analyst** (NL→SQL) | `reporting-management`, `reporting-merchant`, `dwh-curated`, `dwh-core`, `anomaly-detection` | **SQL text only — no rows** |
| **SQL executor** | `execute-sql` | **actual result rows** from the warehouse |
| **Knowledge base** (Cortex Search) | `payments-knowledge-base` | **text passages** — domain knowledge & industry benchmarks |

### The one rule that trips everyone up

The five Cortex Analyst tools **only generate a SQL statement — they do not return data
rows.** To get actual numbers you must take that SQL and run it through **`execute-sql`**, the
only tool that returns rows. **Never present an Analyst tool's generated SQL as "the answer" —
run it first.**

Two valid workflows:
1. **Analyst → execute-sql** (preferred for non-trivial questions): the matching Analyst tool
   drafts SQL against its semantic model (grounded in verified queries), then you run it via
   `execute-sql`. Semantically-correct query *and* the rows.
2. **execute-sql directly**: simple/known queries, session functions (`SELECT CURRENT_ROLE()`),
   or exploring a table whose schema you already know.

## Picking the tool

| Question is about… | Tool |
|---|---|
| One specific merchant's payment operations (auth/capture/success, declines, fees, 3DS, retries, settlements, tokens) | `reporting-merchant` (always scope to the merchant/workspace) |
| High-level, cross-merchant business / billing overview | `reporting-management` |
| Anomalies, incidents, degrading flows, alert history | `anomaly-detection` |
| Payments **domain knowledge** or **industry / peer benchmarks** ("what's typical for…") | `payments-knowledge-base` |
| A field/grain the reporting tools don't expose | `dwh-curated` (fallback) |
| Individual raw transactions, when even curated isn't enough | `dwh-core` (last resort — heaviest) |
| Running generated SQL, exact rows, or session/metadata queries | `execute-sql` |

Prefer the **reporting** layer first; only drop to `dwh-curated` then `dwh-core` when a higher
layer genuinely lacks the field or grain. Always scope `reporting-merchant` to a named
merchant or workspace.

## Knowledge base vs. the merchant's own data

`payments-knowledge-base` answers **"what's typical / how does this work"** — payments domain
knowledge and **industry/peer benchmarks** (e.g. ~85% sector avg success for subscription). It
is **not** the merchant's own live numbers. Useful in debugging to judge whether a figure is
*abnormal*:

- **Benchmark / domain question** → `payments-knowledge-base`.
- **The merchant's own figures** → reporting tools + `execute-sql`.
- **"Is this merchant's auth rate abnormally low?"** → benchmark from the knowledge base *and*
  the merchant's own figure from the data tools, then compare.

Present knowledge-base passages as *benchmarks* (anonymised industry data), never as the
merchant's actual numbers.

## Anomaly questions ("is anything on fire for this merchant?")

The anomaly model writes to `DWH.MACHINE_LEARNING.ANOMALY_ALERTS_MVP`. Each row is an alert
*event*; the state machine per `merchant_workspace_provider` is
**SUSPECT → INCIDENT → RECOVERING**.

For "what's ongoing now", state alone is misleading — an old `INCIDENT` with no later
`RECOVERING` still *looks* active. Take each combination's **latest** alert, filter to
`INCIDENT`/`SUSPECT`, exclude `shadow_mode = true`, and **check recency**. Run directly via
`execute-sql`:

```sql
WITH latest AS (
  SELECT merchant_workspace_provider, alert_type, alert_ts, observed_rate,
         forecast_rate, event_count, shadow_mode,
         ROW_NUMBER() OVER (PARTITION BY merchant_workspace_provider
                            ORDER BY alert_ts DESC NULLS LAST) AS rn
  FROM DWH.MACHINE_LEARNING.ANOMALY_ALERTS_MVP
)
SELECT merchant_workspace_provider, alert_type, alert_ts,
       observed_rate, forecast_rate, event_count,
       TIMESTAMPDIFF(MINUTE, alert_ts, CURRENT_TIMESTAMP()) AS minutes_ago
FROM latest
WHERE rn = 1
  AND alert_type IN ('INCIDENT','SUSPECT')
  AND shadow_mode IS DISTINCT FROM TRUE
ORDER BY alert_ts DESC;
```

Call out *fresh* alerts (recent) vs *stale* (last transition days ago — may have quietly
recovered without a `RECOVERING` row). `baseline_rate` and `cusum` are often NULL — don't rely
on them. To scope to one merchant, filter `merchant_workspace_provider ILIKE '%<merchant>%'`.

## Trust & guardrails

- **Always run the SQL and report real rows** — never numbers from memory or un-executed SQL.
- **Show the SQL you ran**, and **state the time window and filters you assumed** ("last 7
  days", "excluding test merchants") — they materially change the number.
- **Read-only, always.** Only `SELECT`/`SHOW`/`DESCRIBE`/`INFORMATION_SCHEMA`. Never
  `INSERT`/`UPDATE`/`DELETE`/`MERGE`/`CREATE`/`ALTER`/`DROP`/`TRUNCATE`/`COPY`/`PUT`, no grants
  or DDL — even if the session would technically permit it. This is a read-only analytics
  integration. (Aligns with Rule 3 of this skill.)
- Fully-qualify objects: `DB.SCHEMA.TABLE`.
- `execute-sql` truncates large results (~250 KB) — aggregate or `LIMIT`, don't dump raw sets.
- *"tables … do not exist or are not authorized"* is a missing grant on the connected role,
  not a query bug — surface it (the knowledge base's grants live in `BACKEND.PUBLIC`).
- Retry a failed query once or twice (fix the column/join against the metadata); don't loop.

## Where this fits in the debugging workflow

- **SEARCH / DIAGNOSE:** once you've looked at the single failing payment (Grafana/Temporal/
  API), use Snowflake to ask "is this isolated or a trend?" — auth-rate or decline-reason
  movement over the window, and how many transactions are affected.
- **Spotting systemic patterns** (Rule 9): Snowflake is how you confirm a single report is
  actually hitting many transactions/merchants — query the impacted set.
- It complements, not replaces, the single-execution view: Grafana/Temporal tell you *what
  happened to this payment*; Snowflake tells you *whether it's part of a pattern*.
