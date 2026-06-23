# Payrails Debug Plugin

A Claude Code plugin for the Payrails Solutions Engineering team that packages merchant integration debugging skills, MCPs, and workflows into a single installable bundle.

When you install this plugin, you get:
- **Debugging skills** — Claude Code knows the Payrails-specific debugging workflow (UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE)
- **Grafana (via the `gcx` CLI)** — query Loki logs, Prometheus metrics, Tempo traces, and dashboards from inside Claude Code
- **Plain MCP** — read merchant support threads
- **Snowflake MCP** — query Payrails payment data in the warehouse (auth-rate trends, decline-reason analysis, provider performance, anomalies) for historical and aggregate questions; the `cortex-snowflake` skill teaches Claude how to use it
- **Playwright MCP** — browser automation for looking up provider docs (Adyen, Stripe, etc.)
- **Slack/Linear/Notion MCPs** — search prior team discussions, issues, and runbooks
- **Skills for documenting learnings** — capture knowledge from each debugging session into the right reference files

The plugin installs at **user scope**, meaning once installed it works in any folder you open in Claude Code — your backend repo, a debugging scratch folder, anywhere. You don't need to install it per-project.

---

## Supported environments

This plugin can be installed and used in:
- **Antigravity** (the IDE) with Claude Code — primary supported environment; this README covers it
- **Standalone Claude Code CLI** (`claude` command in a terminal) — also supported
- **Claude Desktop (cowork)** — supported via the cowork UI. Follow the separate **[Claude Desktop setup guide](./payrails-debug-plugin-setup.md)** instead of this README's install steps (the cowork UI flow differs). The Grafana (`gcx`) setup is the same in both.

**Not supported:**
- Claude Desktop app's *Claude Code mode* — that mode only loads Anthropic-curated plugins, not arbitrary GitHub-hosted ones. (Cowork, listed above, is a different surface and does work.)
- VS Code with the Claude Code extension — likely works similarly to Antigravity but not yet tested. If you try this, let Edwin know what you find.

---

## Prerequisites

**Always required:**
- **Antigravity or standalone Claude Code CLI** — installed and working
- **GitHub access** to `edwin-payrails/payrails-debug-plugin` — currently a private repo. Ask Edwin to add you as a collaborator. After security review, this moves to `payrails-hub` and access becomes automatic for Payrails GitHub org members.
- **`gh` CLI** — authenticated to a GitHub account that has access to `edwin-payrails/payrails-debug-plugin`. This is whichever account you've been added to as a collaborator — it does NOT have to be a specific Payrails-affiliated account; a personal GitHub account also works as long as it has been granted repo access. If you haven't set up `gh` before, follow GitHub's setup at `https://cli.github.com`. Verify with `gh auth status` — you should see the authorized account as Active with `repo` scope. If you have multiple accounts, switch with `gh auth switch -u <username>`.

**Required for Grafana** (logs/metrics/traces/dashboards):
- **Grafana Cloud access** to `https://payrails.grafana.net` — your normal Payrails Grafana account (check your inbox for the invite if you don't have it yet).
- **The `gcx` CLI** — a one-time install + login, covered in "Grafana setup" below. (No 1Password, no credentials file, no binary download — gcx handles auth via a browser login.)

**Required for Snowflake** (payment-data queries):
- **Snowflake `ANALYST` access** — request in the **#help** Slack channel. Without it, the MCP connects but every query is denied.
- **Authentication is a one-time browser login** (OAuth) on first use, then it's remembered. In Claude Code (terminal / Antigravity) it works once you have access. For **Cowork**, follow the cowork steps in the **[Snowflake MCP Access](https://app.notion.com/p/384cc40840c181dd8facc51ca24325ec)** Notion guide.

**Required only if using Playwright MCP** (browser automation for fetching provider docs):
- **Node.js 18+** — verify with `node --version`. Most Payrails developers already have this. **If Node.js is missing and you don't need browser automation, skip this and continue setup** — the Playwright MCP will fail to load but every other plugin feature works fine. Install Node.js later if you want Playwright.

**Convenience:**
- **Homebrew** — the macOS package manager. Not strictly required, but the easiest way to install `gh`, `gcx`, or `node` if you don't have them. Install from `https://brew.sh`.

If any required prerequisite is missing, install it before continuing. The plugin install will succeed without these, but features depending on them will silently fail or be limited.

---

## Installation

There are two installation paths. The CLI path is recommended — it's faster and works the same in any environment.

### Path 1 — CLI install (recommended)

From any terminal, run these two commands:

```bash
claude plugin marketplace add edwin-payrails/payrails-debug-plugin
claude plugin install payrails-debug@payrails-debug-plugin
```

Expected output of the second command: `✔ Successfully installed plugin: payrails-debug@payrails-debug-plugin (scope: user)`.

If you see `gh: Not Found (HTTP 404)` from either command, see the Troubleshooting section.

These commands work from any folder — the plugin is user-scoped, so the directory doesn't matter.

### Path 2 — Antigravity UI install (alternative)

If you prefer clicking through the UI:

1. In Antigravity, run the `/manage-plugins` slash command
2. Click the **Marketplaces** tab
3. In the "GitHub repo, URL, or path…" field, enter: `edwin-payrails/payrails-debug-plugin`
4. Click **Add**
5. Switch to the **Plugins** tab — `payrails-debug@payrails-debug-plugin` should appear in the INSTALLED section
6. Toggle it on
7. When prompted, restart Claude Code

**Known issue with Path 2:** in some Antigravity versions, after step 4 the plugin may not appear in the Plugins tab. If that happens, fall back to running `claude plugin install payrails-debug@payrails-debug-plugin` from a terminal — that finishes the install, and the plugin will then appear toggled on after a restart.

### Restart Claude Code

After install, fully quit Antigravity (Cmd+Q, not the red X — see the Cmd+Q note in Troubleshooting) and reopen. The plugin is now ready; complete the Grafana setup below so Claude can query Grafana.

---

## Grafana setup (`gcx` CLI)

Grafana is queried through the **`gcx` CLI** (Grafana's official command-line tool), which Claude runs in the shell. This is a one-time, per-person setup — **no credentials file, no 1Password, no binary download, no special launch ritual.**

**1. Install gcx** (one-time):

```bash
brew install grafana/grafana/gcx
```

(For non-Homebrew options, see `https://github.com/grafana/gcx#installation`.)

**2. Log in** (one-time — browser OAuth with your normal Grafana account):

```bash
gcx login --server https://payrails.grafana.net
```

Choose the **OAuth (browser)** option and approve in the browser. When it asks for an optional "Grafana Cloud API token," just press Enter to skip — it's not needed for debugging.

**3. Verify:**

```bash
gcx config check
```

Expected: `Auth method: oauth`, `Connectivity: online`, current context `payrails`, and a Grafana version. *(If you also see a separate `default` context reported as invalid, that's a harmless leftover — run `gcx config delete-context default`. Your active context is `payrails`.)*

That's it. gcx stores your login under `~/.config/gcx/config.yaml`, so it works in **any** Claude Code session regardless of how you launched Antigravity — no env vars, no terminal ritual, nothing to re-source.

**Permission note:** `gcx login` requires the Grafana **"Assistant CLI User"** role. The platform team grants this to the SE team. If `gcx login` returns **"Access Denied … you need the Assistant CLI User role / `grafana-assistant-app.tokens:access`,"** that's an admin grant — ping Quang Ngo (`@Quang`) to enable it for your account. It is not something you can fix locally.

---

## Verifying the install

In a Claude Code session, run `/mcp`.

Expected under "dynamic":
- `plugin:payrails-debug:plain` — Connected
- `plugin:payrails-debug:playwright` — Connected
- `plugin:payrails-debug:snowflake` — *Needs authentication* until you complete the one-time browser login (see the Snowflake prerequisite); Connected afterwards. Requires `ANALYST` access or queries will be denied.

**About Grafana:** Grafana is *not* an MCP in this plugin — it's the `gcx` CLI, so it won't appear as a Connected MCP in `/mcp` (there is no `grafana` MCP server in the plugin). To verify Grafana works, run `gcx config check` in a terminal (see Grafana setup) — `oauth` + `online` means you're good.

**About Slack/Linear/Notion**: these are deduplicated against your claude.ai account-level integrations, so they appear in the **claude.ai** section of `/mcp` rather than the **dynamic** section. In `claude mcp list` they may show as "Failed" — that's expected and not a real failure. The functionality is provided through the claude.ai-level connection, not the plugin's. If a Slack/Linear/Notion query in Claude Code works, you're fine.

(See `CONNECTORS.md` for what each connector is supposed to provide. That file describes design state, not runtime status — for actual runtime, use `/mcp`, `claude mcp list`, or `gcx config check`.)

---

## Daily workflow

Once set up, a debugging session looks like:

1. Open Antigravity (any way you like — no terminal ritual needed) in your workspace
2. In Claude Code, describe the merchant issue you're debugging — the `payrails-debug` skill auto-triggers
3. Claude works through investigation, hypothesis, diagnosis using Grafana (`gcx`), Plain, Slack, Linear, Notion as needed
4. When done, optionally invoke `/payrails-response-draft` for merchant communication, `/payrails-knowledge-update` to capture learnings, or `/payrails-recurring-issue-doc` to document the pattern in Notion

Your `gcx login` persists across sessions, so there's nothing to refresh day to day. (If a Grafana query ever fails with an auth error, re-run `gcx login --server https://payrails.grafana.net`.)

---

## Updates

When the maintainer pushes a new version:

**Recommended:** in Antigravity → `/manage-plugins` → Marketplaces tab → click the refresh icon next to `payrails-debug-plugin`. Then Cmd+Q Antigravity and relaunch.

**Fallback:** if the UI refresh doesn't seem to work:

```bash
claude plugin update payrails-debug@payrails-debug-plugin
```

You can run this from any folder.

**Note about caches:** Antigravity has two separate caches. The marketplace cache (records what versions are available) and the plugin cache (the installed plugin code). Sometimes the marketplace cache needs to refresh first before the plugin cache can update. The UI refresh icon updates both. The CLI command may need the marketplace refresh to happen first if you're trying to pick up a brand-new version.

---

## Troubleshooting

### `gh: Not Found (HTTP 404)` when installing

Either you don't have access to the repo, or `gh` is authenticated to the wrong account.
- Check access: visit `https://github.com/edwin-payrails/payrails-debug-plugin` in a browser logged in as your Payrails GitHub account. If you see 404, ask Edwin to add you as a collaborator.
- Check `gh` auth: run `gh auth status`. The Active account should be your Payrails account. Switch with `gh auth switch -u <username>` if needed.

### Plugin appears in Marketplaces tab but not Plugins tab

The marketplace cloned successfully but the install step didn't fire. Run from any terminal:
```bash
claude plugin install payrails-debug@payrails-debug-plugin
```
Then Cmd+Q Antigravity and reopen. The plugin should now appear in the Plugins tab.

### Grafana queries fail or `gcx login` is denied

- **`gcx config check` shows an error / not online:** re-run `gcx login --server https://payrails.grafana.net` (choose OAuth). If a stale `default` context is the only thing erroring, run `gcx config delete-context default`.
- **`gcx login` returns "Access Denied … Assistant CLI User role required":** your Grafana role lacks the Assistant permission. This is an admin grant — ping Quang Ngo to enable it for your account. Nothing to fix locally.
- **`gcx: command not found`:** gcx isn't installed or isn't on your PATH — `brew install grafana/grafana/gcx` (see Grafana setup).
- **A query 403s on a specific resource** (e.g. dashboard *search*): some sub-permissions may not be granted; the skill routes around these (e.g. `dashboards list` instead of `search`). If a core operation (logs/metrics) is blocked, mention it to Quang.

### Cmd+Q vs the red X

The red X only hides the window — the Antigravity process keeps running. When a step says to fully quit Antigravity, use **Cmd+Q** (or right-click the dock icon → Quit) and verify the dock icon disappears.

### Skills don't auto-trigger on debugging requests

- Verify the plugin is enabled in `/manage-plugins` → Plugins tab
- Restart Claude Code session
- If still not working, fully quit Antigravity (Cmd+Q) and reopen

### Plugin shows wrong version after update

- Check installed version: `cat ~/.claude/plugins/installed_plugins.json | grep -A 5 payrails-debug`
- The `installPath` should reference the latest version folder. If it shows an old version, run `claude plugin update payrails-debug@payrails-debug-plugin` from terminal, then Cmd+Q Antigravity and reopen.
- If still showing wrong version, the marketplace cache may be stale — open `/manage-plugins` → Marketplaces tab → click the refresh icon, then update again.

### Playwright MCP opens a Chromium browser window

Expected behavior, not a bug. The browser stays alive between tool calls for efficiency.

### "Per-project Disable" in `/mcp` removed an MCP for one workspace

The Disable button in `/mcp` only disables for the current project, not globally. Click it again to re-enable, or use a different workspace.

---

## Complete uninstall

If you need to remove every trace of the plugin:

```bash
claude plugin uninstall payrails-debug@payrails-debug-plugin
rm -rf ~/.claude/plugins/cache/payrails-debug-plugin/
rm -rf ~/.claude/plugins/marketplaces/payrails-debug-plugin/
claude plugin marketplace remove payrails-debug-plugin
```

Then Cmd+Q Antigravity to clear in-memory plugin state. Optionally also remove gcx if you don't use it elsewhere (`brew uninstall gcx`) and your gcx login (`rm -rf ~/.config/gcx`).

The `claude plugin marketplace remove` step is important: it cleans up the marketplace registration in your `~/.claude/settings.json` (under `extraKnownMarketplaces`). Without this step, even after deleting the filesystem clones, Antigravity will see "Marketplace already on disk — declared in user settings" when you try to re-install, blocking a fresh install.

---

## What this plugin does NOT include

- The Payrails MCP (`go run ./cmd/payrails_mcp`) — that lives in the backend repo, requires Go and podman, and is for local Payrails service development. It's separate from this plugin.
- The hosted Grafana Cloud MCP — Grafana is accessed via the `gcx` CLI, not the hosted MCP (it incurs Grafana Cloud usage cost, unbudgeted). Its config is documented in `CONNECTORS.md` ("Future — re-enabling the hosted MCP") for when that changes; it is deliberately not in `.mcp.json`.
- Both staging and production Grafana data live on the same Cloud stack (`https://payrails.grafana.net`); scope queries to the correct environment/namespace (see `skills/payrails-debug/references/grafana.md`). Talk to the platform team if you need access beyond your default role.

---

## Reporting issues / suggesting improvements

For now (v1):
- **Bugs or questions**: ping Edwin directly in Slack or open a GitHub issue on this repo
- **Suggestions for new debugging patterns**: Slack `#ai` or `#payments-acceptance`
- **Knowledge or runbook learnings**: tell Edwin and they'll be added to the plugin's reference files

After the plugin moves to `payrails-hub` (post-security-review), the contribution flow will move to GitHub PRs.

---

## Maintainers

- **Edwin Samuel** (`@edwin-payrails`) — current maintainer, primary contributor
- Original `payrails-debug` skill: Eduardo Janicas

---

## Related Slack channels

- `#ai` — general AI/agent discussion
- `#payments-acceptance` — API/platform debugging routing
- `#checkout` — SDK debugging routing
- `#integrations` — Provider debugging routing
- `#platform` — Infrastructure issues (Grafana, MCPs)
- `#security` — security and tooling policy
