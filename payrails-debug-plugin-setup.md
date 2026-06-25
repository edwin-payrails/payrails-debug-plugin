# Payrails Debug Plugin — Setup Guide

This guide walks through installing and fully configuring the **Payrails Debug Plugin** in Claude Desktop. It covers both manual setup and steps that can be followed with the help of Claude Code.

---

## Prerequisites

Before starting, confirm you have access to all of the following. If any are missing, request access in the **#help** Slack channel and wait until they are provisioned before proceeding with the setup.

- **Claude Desktop** installed on macOS
- **Plain** — the support platform used for merchant threads
- **Grafana Cloud** — observability access at `payrails.grafana.net` (your normal Payrails Grafana login; you'll authenticate via your browser, so there's no password to copy anywhere)
- **GitHub** — to install the plugin from the repository

---

## Step 1 — Install the Plugin via Claude Cowork

> **This step requires action in the Claude Desktop UI.**

**Part A — Add the plugin marketplace**

1. Open **Claude Desktop** and click the **Cowork** tab in the left sidebar.
2. Click **Customize** in the left sidebar.
3. Under **Personal plugins**, click the **+** icon.
4. Select **Create plugin** → **Add marketplace**.
5. In the popup that appears, paste the following URL and click **Sync**:

   ```
   https://github.com/edwin-payrails/payrails-debug-plugin/
   ```

The marketplace is now linked. Close or dismiss any popups and return to the Customize sidebar before continuing.

**Part B — Install the plugin from the marketplace**

6. Go back to the **Customize** sidebar from the beginning — under **Personal plugins**, click the **+** icon. This is a completely fresh visit to the same button from Part A, but you will take a different path from here.
7. Select **Browse plugins** (not Create plugin).
8. In the Directory that opens, click the **Personal** tab.
9. The **Payrails debug** plugin will appear — click on it.
10. Click the **Install** button.
11. Once installed, **Payrails debug** will now be visible under **Personal plugins** in the Customize sidebar.

---

## Step 2 — Enable Required Connectors

> **This step requires action in the Claude Desktop UI.**

1. In Claude Desktop, go to **Customize** and locate **Payrails debug** under **Personal plugins** in the left sidebar.
2. Click on **Payrails debug** to expand it, then click **Connectors** underneath it — note this is the Connectors section specific to the plugin, not the top-level Connectors item in the sidebar.
3. Ensure the following connectors are enabled:
   - **Slack**
   - **Linear**
   - **Notion**

---

## Step 3 — Install Homebrew and Node.js

Homebrew and Node.js are required for the plugin's MCP servers to run.

### Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install Node.js

```bash
brew install node
```

### Verify the installation

```bash
node --version
npm --version
npx --version
```

All three commands should return version numbers without errors.

---

## Step 4 — Authorize Grafana (one-time, in Claude)

Grafana is provided by the plugin's **Grafana MCP** — there's **nothing to install** (no binary, no credentials file, no Claude Desktop config edits). The first time Claude uses Grafana, you authorize it through your browser with one click.

**1.** After the plugin is installed (Step 1) and Claude Desktop is restarted, ask Claude something like *"use Grafana to list the datasources."*

**2.** Claude will surface an **authorize URL** (the Grafana MCP needs OAuth on first use). Open it in your browser and click **Allow access**. You'll see **Read access** — allow it. *("Write access — you do not have permission to grant it" is expected; we only read.)*

**3.** Once authorized, the Grafana tools work automatically. Confirm with **`/mcp`** in Claude — `grafana` should show **Connected**.

> **If the authorize page says Access Denied / you don't have permission:** your Grafana account needs the **"Assistant"** role. Ask in **#help** (or the platform team) to enable it, then re-trigger the authorize flow. This is an admin-only grant — there's nothing to fix on your side.

That's the whole Grafana setup — no install, no terminal commands, no config edits.

---

## What the Plugin Can Access

Once set up, the plugin can pull data from the following sources to assist with debugging:

- **Plain** — support threads and customer conversations
- **Linear** — issues, projects, and team activity
- **Slack** — messages and channels
- **Notion** — internal documentation and pages
- **Grafana** — metrics, logs, and observability dashboards
- **Temporal** — workflow execution data
- **Payrails Portal** — merchant and platform data

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `node: command not found` | Re-run `brew install node` and open a new terminal |
| Grafana authorize page says "Access Denied" / no permission | Your Grafana account needs the **"Assistant"** role — ask in #help / the platform team to grant it, then re-trigger the authorize flow |
| Plugin not appearing after install | Restart Claude Desktop and check Customize → Personal plugins |
| Grafana not connecting / queries failing | In Claude run `/mcp`; if `grafana` isn't **Connected**, ask Claude to use Grafana again to re-surface the authorize link, open it, and **Allow access** |
