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

## Step 4 — Set up Grafana access (`gcx` CLI)

Grafana is queried through the **`gcx` CLI** (Grafana's official command-line tool). There's **no binary to download manually and no credentials to put in any config file** — gcx logs you in through your browser and remembers it.

> Claude Code can run the install/verify commands for you; the browser login (Part 2) needs you to click through.

**1. Install gcx** (one-time):

```bash
brew install grafana/grafana/gcx
```

**2. Log in to Grafana Cloud** (one-time — this opens your browser):

```bash
gcx login --server https://payrails.grafana.net
```

- When prompted, choose the **OAuth (browser)** option.
- Sign in / approve in the browser that opens (check the verification code matches the terminal).
- When it asks for an optional **"Grafana Cloud API token,"** just press **Enter** to skip it — it's not needed.

**3. Verify the connection:**

```bash
gcx config check
```

You should see `Auth method: oauth`, `Connectivity: online`, current context `payrails`, and a Grafana version. *(If a separate `default` context is reported as invalid, that's a harmless leftover — run `gcx config delete-context default`.)*

> **If `gcx login` says "Access Denied — you need the Assistant CLI User role":** your Grafana account hasn't been granted the permission yet. Ask in **#help** (or the platform team) to enable the **Assistant CLI User** role for your Grafana Cloud account, then re-run `gcx login`. This is an admin-only access grant — there's nothing to fix on your side.

That's the whole Grafana setup — no binary, no credentials file, and **no Claude Desktop config edits**. gcx stores your login under `~/.config/gcx/config.yaml` and the plugin uses it automatically.

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
| `gcx: command not found` | Re-run `brew install grafana/grafana/gcx` and open a new terminal |
| `gcx login` says "Access Denied / Assistant CLI User role required" | Your Grafana account needs the **Assistant CLI User** role — ask in #help / the platform team to grant it, then re-run `gcx login --server https://payrails.grafana.net` |
| Plugin not appearing after install | Restart Claude Desktop and check Customize → Personal plugins |
| Grafana queries failing | Run `gcx config check`; if it's not `online`, re-run `gcx login --server https://payrails.grafana.net` and choose the OAuth option |
