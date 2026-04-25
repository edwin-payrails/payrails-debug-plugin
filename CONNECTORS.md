# Connectors in the Payrails Debug Plugin

This document describes each MCP (Model Context Protocol) server / connector that ships with the plugin, what it does, and any caveats about its setup.

If you're trying to install the plugin, see the [README](./README.md) instead. This doc is for understanding what each connector provides.

---

## Connector overview

The plugin declares **6 MCP servers** in `.mcp.json`. They use three different formats reflecting each connector's reality:

| Connector | Format | Auth | Purpose |
|---|---|---|---|
| Plain | HTTP (Anthropic-hosted) | OAuth | Read merchant support threads |
| Slack | HTTP (Anthropic-hosted) | OAuth | Search prior team discussions |
| Linear | HTTP (Anthropic-hosted) | OAuth | Search/read issues, bugs, feature requests |
| Notion | HTTP (Anthropic-hosted) | OAuth | Search runbooks, post-mortems, documentation |
| Playwright | npx stdio (local Node.js) | None | Browser automation for fetching JS-rendered content |
| Grafana | Local binary (stdio) | Username + password env vars | Query Loki logs, Prometheus metrics, dashboards |

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

**What it is**: Queries the Payrails Grafana instance — Loki logs, Prometheus (Cortex) metrics, dashboards, alerts.

**Configuration**:
```json
"grafana": {
  "command": "${PAYRAILS_GRAFANA_BIN}",
  "env": {
    "GRAFANA_URL": "https://grafana.telemetry.payrails.io",
    "GRAFANA_USERNAME": "${GRAFANA_USERNAME}",
    "GRAFANA_PASSWORD": "${GRAFANA_PASSWORD}"
  }
}
```

**Authentication**: HTTP basic auth via env vars (`GRAFANA_USERNAME`, `GRAFANA_PASSWORD`). Set up via the op-inject pattern documented in [README](./README.md).

**Binary**: This MCP is the official Grafana Labs `mcp-grafana` binary. You need to download it once and put it at `$HOME/tools/mcp-grafana-official` (or update `PAYRAILS_GRAFANA_BIN` in your `.env` to point elsewhere).

To download:
```bash
mkdir -p ~/tools
# Download from official Grafana releases
# (URL and version handling — talk to Edwin or check Grafana Labs docs)
```

**What it provides**:
- `list_datasources` — inventory of Grafana datasources (Cortex, Loki, Tempo, CloudWatch, etc.)
- `search_dashboards` — find dashboards by keyword
- `get_dashboard_summary` — get panels and template variables for a dashboard
- `get_dashboard_panel_queries` — extract exact PromQL/LogQL queries from panels
- `query_prometheus` — run PromQL queries directly
- `query_loki_logs` — run LogQL queries
- `list_loki_label_values` — discover what label values exist for a Loki label
- `get_panel_image` — render a dashboard panel as image (currently broken — see caveats)

**Caveats**:

1. **Spotlight launches don't work**: Antigravity must be launched from a terminal that has env vars set. See README for the daily workflow.

2. **Image rendering currently broken**: The `get_panel_image` tool currently returns "No image renderer available/installed" because the Grafana Image Renderer plugin isn't installed on the Grafana instance. Platform team is aware (queued to flag). Workaround: extract the underlying query with `get_dashboard_panel_queries` and run it via `query_prometheus` instead.

3. **Tempo trace tools not exposed**: The Grafana MCP could expose Tempo trace lookup tools, but they require Tempo's mcp_server.enabled:true on the Tempo side (infrastructure change). Workaround: extract TraceID from Loki logs and provide a Grafana UI URL.

4. **Namespace gotcha for Loki queries**: Different merchants have different Loki label structures. The skill's reference file `grafana.md` documents a 3-tier fallback approach — try `namespace=<merchant>` first, fall back to `merchant_name=<merchant>`, fall back to `list_loki_label_values` discovery if both return zero results.

5. **LogQL `limit` is a tool parameter, not a query operator**: Don't write `{...} | limit 5` in your LogQL — that's invalid syntax. Pass `limit=5` as a separate argument to `query_loki_logs`.

6. **Large execution searches**: For traces spanning hours, exclude noisy entries to stay within the 100-entry limit. Pattern: `{merchant_name="<merchant>", app="backend"} |= "<execution-id>" != "Rule evaluation failed" != "Query" != "JWT claims validated"`

---

## Connectors NOT in this plugin

Things you might expect but aren't included:

- **Payrails MCP** (`go run ./cmd/payrails_mcp`): Lives in the backend repo, requires Go + podman, used for local backend development. Not part of debugging flow.

- **Production Grafana**: Plugin uses staging Grafana for safety. If you need production access, talk to Quang Ngo and platform team.

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
| Playwright | None (npx fetches package) |
| Grafana | **Significant**: download binary + 1Password setup + per-session terminal ritual. See README. |

If something isn't working: check `/mcp` in Claude Code — it will show which MCPs are Connected vs Failed vs Needs Auth.
