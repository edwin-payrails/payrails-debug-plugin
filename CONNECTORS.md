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
| Grafana | **`gcx` CLI** (shell tool, not an MCP) | Browser OAuth (`gcx login`) | Query Loki logs, Prometheus metrics, Tempo traces, dashboards |

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

## Grafana (`gcx` CLI — not an MCP)

**What it is**: Grafana Cloud (`https://payrails.grafana.net`) — Loki logs, Prometheus metrics, Tempo traces, dashboards, alerts — queried through Grafana's official **`gcx` CLI**, which the debugging skill runs in the shell. It is **not** an MCP server.

**Why gcx, not an MCP**: Payrails moved off self-hosted Grafana (retired June 2026) to Grafana Cloud. The hosted Grafana Cloud MCP is deferred (it incurs Grafana Cloud AI-usage cost that isn't budgeted yet), so the platform team's recommended path is the `gcx` CLI. The hosted-MCP block was **removed** from `.mcp.json` — a present-but-unauthenticated MCP confused the agent (it reached for the MCP, hit OAuth, and concluded Grafana was broken) and risked a teammate authorizing it and incurring cost. Its config is recorded under "Future — re-enabling the hosted MCP" below, for if/when it's budgeted.

**Setup**: one-time per person — `brew install grafana/grafana/gcx`, then `gcx login --server https://payrails.grafana.net` (browser OAuth). See [README](./README.md) → "Grafana setup". No binary download, no credentials file, no 1Password, no env vars.

**Authentication**: browser OAuth via `gcx login` (token stored in `~/.config/gcx/config.yaml`). Requires the Grafana **"Assistant CLI User"** role — admin-granted by the platform team. If `gcx login` is denied, that's a role grant, not a config issue.

**What it provides** (run `gcx <group> --help` to discover more):
- `gcx datasources list` — inventory of datasources + their UIDs
- `gcx logs query` / `gcx logs labels` — LogQL queries + label discovery (Loki)
- `gcx metrics query` / `gcx metrics labels` — PromQL queries (Prometheus)
- `gcx traces query` / `gcx traces get` — TraceQL / trace lookup (Tempo) — newly available on Cloud
- `gcx dashboards list` / `gcx dashboards get` — find + read dashboards and their panel queries
- `gcx alert ...` / `gcx irm ...` — alert rules, incidents, on-call
- `gcx api <path>` — authenticated raw Grafana API (e.g. resolving a shared `/goto/<uid>` link)

The full command patterns, the real datasource UIDs, the merchant/namespace ladder, and gotchas live in the skill's reference file `skills/payrails-debug/references/grafana.md`.

**Caveats**:

1. **Auth is admin-gated**: `gcx login` needs the "Assistant CLI User" role (auto-granted only to Editor+; SE-team Viewers need it granted explicitly). Ping the platform team if denied.

2. **`gcx config check` may show a stale `default` context** as invalid — harmless; the active context is `payrails`. Clean it with `gcx config delete-context default`.

3. **Dashboard `search` is 403** for the SE role (a separate search-API permission) — use `gcx dashboards list` + client-side filter instead.

4. **Operational gotchas**: pass datasource **UID, not name**, to `-d`; add `2>/dev/null` when piping (gcx writes hints to stderr); large results spill to a temp `gcx-results-*.json` file; `--since` rejects multi-day values (use `--from now-720h`). See grafana.md.

5. **cowork (Claude Desktop) is unverified**: whether cowork can run the `gcx` shell command and reach `*.grafana.net` may need an allowlist. Claude Code (Antigravity / Claude Desktop Code) is confirmed working.

**Future — re-enabling the hosted MCP** (only when the platform team budgets the cost): the hosted Grafana Cloud MCP authenticates via OAuth, and the SE "Assistant CLI User" grant already covers the read access its OAuth needs. To bring it back, add this block to `.mcp.json` and have each user authorize once via `/mcp`:
```json
"grafana": {
  "type": "http",
  "url": "https://mcp.grafana.com/mcp",
  "headers": { "X-Grafana-URL": "https://payrails.grafana.net" }
}
```
Before adopting it *over* gcx, see the gcx-vs-hosted-MCP decision framework recorded in `BUILD_HANDOFF.md`.

---

## Connectors NOT in this plugin

Things you might expect but aren't included:

- **Payrails MCP** (`go run ./cmd/payrails_mcp`): Lives in the backend repo, requires Go + podman, used for local backend development. Not part of debugging flow.

- **The hosted Grafana Cloud MCP**: not used — Grafana is accessed via the `gcx` CLI (the hosted MCP incurs unbudgeted Grafana Cloud usage cost). Its config is recorded under "Future — re-enabling the hosted MCP" above; it is deliberately **not** in `.mcp.json`.

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
| Playwright | None (npx fetches package) |
| Grafana | One-time: `brew install grafana/grafana/gcx` + `gcx login` (browser OAuth). Requires the "Assistant CLI User" Grafana role (admin-granted). See README. |

If something isn't working: check `/mcp` in Claude Code — it will show which MCPs are Connected vs Failed vs Needs Auth.
