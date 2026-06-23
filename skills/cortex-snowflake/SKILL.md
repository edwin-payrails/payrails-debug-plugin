---
name: cortex-snowflake
description: >
  Query Payrails payment data in Snowflake via the snowflake MCP server. Use whenever the
  user asks about payments, merchants, authorization/acceptance/success rates, declines and
  decline reasons, fees, settlements, reconciliation, billing, volumes/TPV, attempts, retry
  recovery, providers/PSP performance, BIN or routing analysis, instrument/token states,
  webhook/event history, payment anomalies/incidents, or payments industry benchmarks — and
  for any historical, aggregate, or trend question ("the pattern across X over time") about
  payment data, sliced by merchant, provider, payment method, country, card network, decline
  reason, or merchant metadata. This MCP is the source of truth for that data. Covers which of
  the seven tools to pick, the rule that the Cortex Analyst tools only GENERATE SQL (run it via
  execute-sql to get rows), and when to use the payments knowledge base for benchmarks vs. the
  warehouse for the customer's own numbers.
---

# Payrails Snowflake data

The `snowflake` MCP server (`DWH.REPORTING.PAYRAILS_SCOPE_MCP`) is the source of truth for
Payrails payment, billing, and anomaly data. When a question is about that data, use these
tools rather than answering from general knowledge.

> **Setup & access.** This skill assumes the `snowflake` MCP server is connected and you
> hold Snowflake `ANALYST` access. If it isn't connected, or a tool returns an
> authorization error, see the setup guide in Notion:
> **[Snowflake MCP Access](https://app.notion.com/p/384cc40840c181dd8facc51ca24325ec)** —
> how to connect the MCP (Claude Code and Cowork), and request `ANALYST` access (#help on Slack).

## When to reach for Snowflake

Snowflake is the source of truth for Payrails payment, billing, and anomaly data. **Whenever a
question touches that data, Snowflake can answer it — prefer reaching for it over answering
from memory or assuming it's out of scope.** It's *strongest* for patterns, aggregates, and
trends:

> **"What's the pattern across X over time?" → Snowflake** — over a time range, or sliced by
> merchant, provider, payment method, country, card network, decline reason, BIN, or metadata
> field.

Common cases (illustrative — **not** exhaustive, and **not** a closed list):
- Authorization / acceptance / success-rate trends, by provider, payment method, country, or
  card network
- Decline-reason analysis — what's driving declines, and how a reason drifts over time
- Provider/PSP performance, BIN and routing analysis, fees and reconciliation
- TPV, attempt counts, retry-recovery rate, volume / payment-method distribution
- The impacted set of transactions for a filter (e.g. an incident's blast radius)
- Anything a merchant sends in their request body, including **metadata fields**, and analysis
  over **raw PSP responses**
- Payment anomalies / incidents (see the anomaly section below)

**Single transactions are fair game too.** `dwh-core` holds individual transaction records, so
use Snowflake for a *specific* payment when: it's historical (older than operational-tool
retention — Temporal keeps only ~5 days), you need its **warehoused raw PSP response, metadata,
or decline detail**, or you're pulling the set of transactions matching a filter.

**The only carve-out:** the **live state of an in-flight payment right now** — its current
workflow step or fresh logs/traces. Snowflake **lags real time**, so for "what's happening to
this payment this minute," reach for Grafana (logs/traces), Temporal (workflow state), or the
merchant API first. That's the *one* thing Snowflake isn't the right tool for — everything else
about payment data, it is.

**When unsure, use it.** If a question plausibly touches payment/merchant/anomaly data and you
aren't certain another tool is clearly better, query Snowflake rather than skipping it. The
list above can never be a reason *not* to use Snowflake.

## Three kinds of tools — they behave differently

| Kind | Tools | Returns |
|---|---|---|
| **Cortex Analyst** (NL→SQL) | `reporting-management`, `reporting-merchant`, `dwh-curated`, `dwh-core`, `anomaly-detection` | **SQL text only — no rows** |
| **SQL executor** | `execute-sql` | **actual result rows** from the warehouse |
| **Knowledge base** (Cortex Search) | `payments-knowledge-base` | **text passages** — domain knowledge & industry benchmarks |

### The one rule that trips everyone up

The five Cortex Analyst tools **only generate a SQL statement — they do not return data
rows.** Their response is interpretive text + a `statement`. To get actual numbers you must
take that SQL and run it through **`execute-sql`**, the only tool that returns rows.

**Never present an Analyst tool's generated SQL to the user as "the answer" — run it first.**

Two valid workflows:
1. **Analyst → execute-sql** (preferred for non-trivial questions): ask the matching Analyst
   tool to draft SQL against its semantic model (it's grounded in verified queries), then run
   that SQL via `execute-sql`. You get a semantically-correct query *and* the rows.
2. **execute-sql directly**: for simple/known queries, session functions
   (`SELECT CURRENT_ROLE()`), or exploring a table whose schema you already know.

## Picking the tool

| Question is about… | Tool |
|---|---|
| One specific merchant's payment operations (auth/capture/success, declines, fees, 3DS, retries, settlements, tokens) | `reporting-merchant` (always scope to the merchant/workspace) |
| High-level, cross-merchant business / billing overview (exec or management framing) | `reporting-management` |
| Anomalies, incidents, degrading flows, alert history | `anomaly-detection` |
| Payments **domain knowledge** or **industry / peer benchmarks** ("what's typical for…") | `payments-knowledge-base` |
| A field/grain the reporting tools don't expose | `dwh-curated` (fallback) |
| Individual raw transactions, when even curated isn't enough | `dwh-core` (last resort — heaviest) |
| Running generated SQL, exact rows, or session/metadata queries | `execute-sql` |

Prefer the **reporting** layer first; only drop to `dwh-curated` then `dwh-core` when a
higher layer genuinely lacks the field or grain. Always scope `reporting-merchant` to a
named merchant or workspace.

## Knowledge base vs. the customer's own data

`payments-knowledge-base` answers **"what's typical / how does this work"** — it returns
payments domain knowledge and **industry/peer benchmarks** (e.g. ~85% sector avg success for
subscription, ~90% best-in-class EU e-commerce). It is **not** the connected customer's own
live numbers.

- **Benchmark / domain question** → `payments-knowledge-base`.
- **The customer's own figures** → reporting tools + `execute-sql`.
- **"How do we compare to the industry?"** → get the benchmark from the knowledge base *and*
  the customer's own figure from the data tools, then compare.

Caveat: the knowledge base holds **anonymised client ROI/QBR benchmarks and case studies**,
not a clean normalized per-industry table. Figures vary by transaction type (recurring vs
one-time vs upsell), market, and payment method. Present its passages as *benchmarks*, never
as the customer's actual data.

## When to use execute-sql directly (skip the Analyst tool)

- Session/metadata queries: `SELECT CURRENT_ROLE()`, `SHOW`, `INFORMATION_SCHEMA` lookups.
- A query you already know is correct (e.g. the anomaly query below).
- Cheap exploration of a table whose schema you already know.

Going straight to `execute-sql` avoids an Analyst call (which consumes Cortex credits). Use
the Analyst tools when you need their semantic-model knowledge to write the SQL correctly.

## Anomaly questions ("is anything on fire right now?")

The anomaly model writes to `DWH.MACHINE_LEARNING.ANOMALY_ALERTS_MVP`. Each row is an alert
*event*; the state machine per `merchant_workspace_provider` is
**SUSPECT → INCIDENT → RECOVERING**.

For "what's ongoing now", state alone is misleading — an old `INCIDENT` with no later
`RECOVERING` still *looks* active. Take each combination's **latest** alert, filter to
`INCIDENT`/`SUSPECT`, exclude `shadow_mode = true`, and **check recency**. Run this directly
via `execute-sql`:

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

Then call out which results are *fresh* (alerted recently) vs *stale* (last transition days
ago — may have quietly recovered without a `RECOVERING` row). `baseline_rate` and `cusum` are
often NULL — don't rely on them being populated.

## Trust & verification

- **Always run the SQL and report real rows** — never numbers from memory or un-executed SQL.
- **Show the SQL you ran** alongside the answer so the user can verify the logic.
- **State the time window and any filters you assumed** ("last 7 days", "excluding test
  merchants") — these materially change the number.
- **Flag uncertainty**: if a question likely falls outside the semantic model's verified-query
  coverage, say the answer is best-effort and worth sanity-checking.

## Conventions & guardrails

- **Read-only, always.** Only ever issue read queries (`SELECT`, `SHOW`, `DESCRIBE`,
  `INFORMATION_SCHEMA`). **Never write to Snowflake** — no `INSERT`/`UPDATE`/`DELETE`/`MERGE`,
  no `CREATE`/`ALTER`/`DROP`/`TRUNCATE`, no `COPY`/`PUT`, no grants or DDL — even if a
  `DEVELOPER`-scoped session would technically permit it. If a user asks for a write, decline
  and explain this is a read-only analytics integration. (Sessions are usually scoped to the
  read-only `ANALYST` role and `execute-sql` defaults to read-only, but treat read-only as a
  hard rule regardless of what the session would allow.)
- Fully-qualify objects: `DB.SCHEMA.TABLE` (e.g. `DWH.MACHINE_LEARNING.ANOMALY_ALERTS_MVP`).
- `execute-sql` truncates large results (~250 KB) — aggregate or `LIMIT`, don't dump raw sets.
- *"tables … do not exist or are not authorized"* is a missing grant on the connected role,
  not a query bug — surface it to the user (for the knowledge base, the grants live in a
  different database, `BACKEND.PUBLIC`).
- Retry a failed query once or twice (fix the column/join against the metadata); don't loop.

## Worked examples

**"Are there any anomalies ongoing right now?"**
→ Run the anomaly query above via `execute-sql`. Report combinations whose latest alert is
`INCIDENT`/`SUSPECT`, separating *fresh* (alerted hours ago) from *stale* (days ago).

**"What's merchant Acme's auth rate over the last 7 days?"**
→ `reporting-merchant` scoped to Acme drafts the SQL → run via `execute-sql` → return the
rate, the SQL, and the window. (Merchant-specific operational metric.)

**"This decline reason has been climbing — which merchants/PSPs are driving it?"**
→ `reporting-merchant` or `dwh-curated` drafts the SQL grouping by merchant/provider over the
window → run via `execute-sql`. (Trend across a dimension over time.)

**"Total payment volume across all merchants in May?"**
→ `reporting-management` drafts the SQL → run via `execute-sql`. (Cross-merchant overview.)

**"What's a typical authorization rate for subscription businesses?"**
→ `payments-knowledge-base`. Return the benchmark (~85% sector avg) as a *benchmark*, noting
it's anonymised industry data, not Acme's own number.

**"How does our auth rate compare to the industry?"**
→ Benchmark from `payments-knowledge-base` + the customer's own figure from
`reporting-management`/`reporting-merchant` + `execute-sql`, then compare the two.

**"What role am I connected as?"**
→ `execute-sql` directly: `SELECT CURRENT_ROLE(), CURRENT_SECONDARY_ROLES();` (no Analyst call).
