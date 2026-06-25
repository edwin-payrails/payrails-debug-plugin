# Connectors in the Payrails Debug Plugin

This document describes each MCP (Model Context Protocol) server / connector that ships with the plugin, what it does, and any caveats about its setup.

If you're trying to install the plugin, see the [README](./README.md) instead. This doc is for understanding what each connector provides.

---

## Connector overview

The plugin declares **8 MCP servers** in `.mcp.json` (Plain, Slack, Linear, Notion, Snowflake, Playwright, Temporal, Grafana). They use several formats reflecting each connector's reality:

| Connector | Format | Auth | Purpose |
|---|---|---|---|
| Plain | HTTP (Anthropic-hosted) | OAuth | Read merchant support threads |
| Slack | HTTP (Anthropic-hosted) | OAuth | Search prior team discussions |
| Linear | HTTP (Anthropic-hosted) | OAuth | Search/read issues, bugs, feature requests |
| Notion | HTTP (Anthropic-hosted) | OAuth | Search runbooks, post-mortems, documentation |
| Snowflake | npx stdio (`mcp-remote` → Snowflake-hosted) | Browser OAuth (via `mcp-remote`) | Query warehouse payment data — trends, declines, anomalies, merchant metrics |
| Playwright | npx stdio (local Node.js) | None | Browser automation for fetching JS-rendered content |
| Temporal | node stdio (bundled local server) | None (internal cluster routing) | Workflow execution state, history, payload decode |
| Grafana | HTTP (hosted Grafana Cloud MCP) | Browser OAuth (first use) | Query Loki logs, Prometheus metrics, Tempo traces, dashboards |

---

## Plain MCP

**What it is**: Reads from Plain, the merchant support threading platform Payrails uses.

**Configuration**:
```json
"plain": {
  "type": "http",
  "url": "https://mcp.plain.com/mcp"
}
```

**Authentication**: First time you try to use a Plain tool, Claude Code will prompt you to authenticate via a browser link. After that, your auth token persists across sessions.

**What it provides**: Tools to search threads, read thread content, find specific tickets by reference (T-XXXX format), and pull merchant context. Used heavily by the `payrails-thread-debug` skill.

**Caveats**: None significant. Works well out of the box.

---

## Slack MCP

**What it is**: Reads from Slack — channels, messages, search.

**Configuration**:
```json
"slack": {
  "type": "http",
  "url": "https://mcp.slack.com/mcp"
}
```

**Authentication**: OAuth flow via browser, similar to Plain.

**What it provides**: Search public and private channels for prior discussions. Useful for finding past conversations about specific merchants, error codes, or debugging patterns.

**Caveat — claude.ai integrations dedup**: If you have Slack already connected at the Claude.ai account level, the plugin's HTTP declaration is silently deduplicated. Functionally equivalent — both paths use the same Anthropic-hosted Slack MCP backend. You'll see `claude.ai Slack` in `/mcp` instead of `plugin:payrails-debug:slack`. The plugin's declaration is a fallback for users without claude.ai-level Slack integration.

---

## Linear MCP

**What it is**: Reads from Linear — issues, projects, comments.

**Configuration**:
```json
"linear": {
  "type": "http",
  "url": "https://mcp.linear.app/mcp"
}
```

**Authentication**: OAuth flow via browser.

**What it provides**: Search and read Linear issues. Useful for finding existing bug reports about a merchant's issue, checking recent feature requests related to the debugging context, or linking debugging sessions to existing tickets.

**Caveat**: Same deduplication behavior as Slack if you have claude.ai-level Linear connected.

---

## Notion MCP

**What it is**: Reads from Notion — pages, databases, runbooks.

**Configuration**:
```json
"notion": {
  "type": "http",
  "url": "https://mcp.notion.com/mcp"
}
```

**Authentication**: OAuth flow via browser.

**What it provides**: Search runbooks, post-mortems, internal docs. Also writes to the "Merchant Debugging Patterns" Notion database when the `payrails-recurring-issue-doc` skill is invoked (database ID: `47141def-527d-46b8-bbc8-f3ee7688feb3`).

**Caveat**: Same deduplication behavior as Slack/Linear if you have claude.ai-level Notion connected.

---

## Snowflake MCP

**What it is**: Queries Payrails payment, billing, and anomaly data in Snowflake — the Snowflake-managed MCP server `DWH.REPORTING.PAYRAILS_SCOPE_MCP`. It's the source of truth for **historical and aggregate** payment data.

**Configuration** (wrapped in `mcp-remote`, a local stdio proxy):
```json
"snowflake": {
  "command": "npx",
  "args": [
    "-y", "mcp-remote",
    "https://eb02656.eu-central-1.snowflakecomputing.com/api/v2/databases/DWH/schemas/REPORTING/mcp-servers/PAYRAILS_SCOPE_MCP",
    "3334",
    "--static-oauth-client-info", "{\"client_id\":\"vxQ4LhvjrO8gU+1zBVeubuPTwqY=\"}",
    "--static-oauth-client-metadata", "{\"scope\":\"session:role:ANALYST\"}"
  ]
}
```

**Why `mcp-remote` and not a plain `type: http` + `oauth` block**: the native Claude Code OAuth connector mis-encodes the `+` in the Snowflake client id on older clients (it sends a raw `+`, which a URL reads as a space → Snowflake returns "client id not found"), and the Claude desktop app's *native* Snowflake connector is admin-gated. `mcp-remote` (a local stdio proxy) runs its own OAuth — it percent-encodes the client id correctly and works across Claude Code (terminal / Antigravity), the desktop Code tab, **and Cowork**. The Data team set up a dedicated OAuth integration for this, registered for `mcp-remote`'s default callback port `3334` and its `/oauth/callback` path.

**Authentication**: first use opens a browser to log into Snowflake and approve the `ANALYST` role; the token is cached (`~/.mcp-auth`) and refreshed automatically. Requires Snowflake **`ANALYST` access** (request in #help) — without it the MCP connects but queries are denied. The client id above is a *public* OAuth client identifier (no secret), so it's safe to commit.

**What it provides**: seven tools — five Cortex Analyst NL→SQL tools (`reporting-management`, `reporting-merchant`, `dwh-curated`, `dwh-core`, `anomaly-detection`), `execute-sql` (the only one that returns rows), and `payments-knowledge-base` (industry benchmarks). Tool selection and usage live in the `cortex-snowflake` skill and `skills/payrails-debug/references/snowflake.md`.

**Caveats**: the Cortex Analyst tools only *generate* SQL — run it via `execute-sql` to get rows. Snowflake data lags real time (use it for patterns/trends, not "this payment right now"). For **Cowork**, the same block must also be added to `claude_desktop_config.json` — see the [Snowflake MCP Access](https://app.notion.com/p/384cc40840c181dd8facc51ca24325ec) Notion guide.

---

## Playwright MCP

**What it is**: Browser automation. Allows Claude Code to navigate websites, capture rendered content, fill forms, etc.

**Configuration**:
```json
"playwright": {
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest"]
}
```

**Authentication**: None. The MCP runs locally on your machine.

**What it provides**: Tools to navigate URLs, capture page content, screenshot, etc. Used primarily for fetching JS-rendered content from PSP documentation sites (Adyen, Stripe, Checkout.com etc.) where simple `web_fetch` doesn't work.

**Behavior**: First use opens a Chromium browser window. The browser stays alive between tool calls for efficiency. This is normal behavior, not a bug.

**Prerequisite**: Node.js 18+ on your machine. `npx` must be in your PATH. If `npx` works in a terminal, this MCP will work.

**Source**: This uses Microsoft's official `@playwright/mcp` package, NOT `@anthropic-ai/mcp-playwright` (which doesn't exist on npm despite some Payrails configs referencing it).

---

## Grafana MCP

**What it is**: Grafana Cloud (`https://payrails.grafana.net`) — Loki logs, Prometheus metrics, Tempo traces, dashboards, alerts — via the **hosted Grafana Cloud MCP** (`https://mcp.grafana.com/mcp`), declared as `grafana` in `.mcp.json`. Its tools (`query_loki_logs`, `query_prometheus`, `search_dashboards`, the `tempo_*` trace tools, etc.) are exposed to the agent directly.

**Configuration** (in `.mcp.json`):
```json
"grafana": {
  "type": "http",
  "url": "https://mcp.grafana.com/mcp",
  "headers": { "X-Grafana-URL": "https://payrails.grafana.net" }
}
```

**Authentication**: browser **OAuth** on first use — the agent surfaces an authorize URL; the user clicks **Allow** (Read access). No binary, no credentials file, no env vars. Requires the Grafana **"Assistant"** role (admin-granted by the platform team); if authorization is denied, that's a role grant, not a config issue. *(History: this stack briefly used the `gcx` CLI while the hosted MCP was cost-deferred; the platform team has since approved the MCP. The gcx approach + a gcx-vs-MCP comparison are preserved in `BUILD_HANDOFF.md` and the git history of `grafana.md` in case it's ever revisited.)*

**What it provides** (a rich, auto-advertised tool surface):
- `list_datasources` — datasources + UIDs (Prometheus `grafanacloud-prom`, Loki `grafanacloud-logs`, Tempo `grafanacloud-traces`)
- `query_loki_logs` / `list_loki_label_values` / `query_loki_stats` — LogQL + label discovery (Loki)
- `query_prometheus` / `list_prometheus_label_values` — PromQL (Prometheus)
- `tempo_traceql-search` / `tempo_get-trace` / `tempo_get-attribute-*` — traces (Tempo)
- `search_dashboards` / `get_dashboard_panel_queries` / `get_dashboard_summary` / `run_panel_query` — dashboards
- alert / incident / on-call / Sift tools; `ask_assistant` (natural-language to Grafana Assistant)

The query patterns, real datasource UIDs, the merchant/namespace ladder, and gotchas live in `skills/payrails-debug/references/grafana.md`.

**Caveats / gotchas**:

1. **Auth is admin-gated**: needs the Grafana "Assistant" role. Ping the platform team if the authorize page denies you.

2. **Time-param names differ per tool**: Loki uses `startRfc3339`/`endRfc3339`; Prometheus uses `startTime`/`endTime` (relative `now-1h` ok; `endTime` required); Tempo uses `start`/`end`. There is no `since`.

3. **Loki 30-day window + response-size cap**: aggregate inside LogQL (`sum by(...) (count_over_time(... | json [30d]))` with `queryType="instant"`) instead of dumping raw lines; pre-check cheaply with `query_loki_stats` / `list_loki_label_values`.

4. **`up` doesn't cover backend app jobs** (only infra); the `job` label is namespaced (`backend-stable-<service>-http`), so `up{job="backend"}` is empty — query a real app metric for backend health. See grafana.md.

5. **Dashboard `search` works** for the SE role via the MCP (it was 403 via the earlier gcx path — a real behavioral difference between the two access methods).

---

## Connectors NOT in this plugin

Things you might expect but aren't included:

- **Payrails MCP** (`go run ./cmd/payrails_mcp`): Lives in the backend repo, requires Go + podman, used for local backend development. Not part of debugging flow.

- **Separate "production Grafana"**: staging and production data now live on the same Grafana Cloud stack (`payrails.grafana.net`); scope queries by environment/namespace. Talk to the platform team for access beyond your role.

- **Production Temporal**: Same — staging only by default.

---

## Setup reminders

The plugin install only sets up MCP **declarations**. Some MCPs need additional one-time setup on your machine:

| Connector | Additional setup needed? |
|---|---|
| Plain | First-use OAuth (one click) |
| Slack | First-use OAuth (one click) |
| Linear | First-use OAuth (one click) |
| Notion | First-use OAuth (one click) |
| Snowflake | First-use browser OAuth (one login, then cached). Requires the `ANALYST` Snowflake role (request in #help). For Cowork, also add the block to `claude_desktop_config.json`. |
| Playwright | None (npx fetches package) |
| Temporal | None (configured via `.mcp.json`). |
| Grafana | One-time: authorize the `grafana` MCP via the OAuth link on first use (click Allow). Requires the Grafana "Assistant" role (admin-granted). See README. |

If something isn't working: check `/mcp` in Claude Code — it will show which MCPs are Connected vs Failed vs Needs Auth.
