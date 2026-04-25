# Payrails Debug Plugin

A Claude Code plugin for the Payrails Solutions Engineering team that packages merchant integration debugging skills, MCPs, and workflows into a single installable bundle.

When you install this plugin, you get:
- **Debugging skills** — Claude Code knows the Payrails-specific debugging workflow (UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE)
- **Grafana MCP** — query Loki logs, Prometheus metrics, and dashboards from inside Claude Code
- **Plain MCP** — read merchant support threads
- **Playwright MCP** — browser automation for looking up provider docs (Adyen, Stripe, etc.)
- **Slack/Linear/Notion MCPs** — search prior team discussions, issues, and runbooks
- **Skills for documenting learnings** — capture knowledge from each debugging session into the right reference files

The plugin is designed to make every SE's debugging experience consistent, regardless of how new they are to Payrails.

The plugin installs at **user scope**, meaning once installed it works in any folder you open in Claude Code — your backend repo, a debugging scratch folder, anywhere. You don't need to install it per-project.

---

## Prerequisites

Before installing the plugin, make sure you have:

- **Antigravity** (or standalone Claude Code CLI) — the IDE/CLI you'll use to run Claude Code
- **GitHub access** to `edwin-payrails/payrails-debug-plugin` (private repo for now; will move to `payrails-hub` after security review)
- **`gh` CLI** authenticated to your Payrails-affiliated GitHub account (`edwin-payrails` namespace, not your personal one)
- **1Password CLI** (`op`) installed and signed in — needed to load Grafana credentials securely
- **Grafana credentials** stored in your 1Password (your Payrails Grafana username and password, accessed via `https://grafana.telemetry.payrails.io`)
- **Node.js 18+** (for the Playwright MCP) — usually already installed if you do any frontend work
- **Homebrew** — for installing missing tools

If you don't have one of these, talk to Edwin or check with `#ai` in Slack before continuing.

---

## Installation

### Step 1 — Add the plugin marketplace in Antigravity

1. In Antigravity, open Claude Code's `/manage-plugins` slash command
2. Click the **Marketplaces** tab
3. In the "GitHub repo, URL, or path…" field, enter:
   ```
   edwin-payrails/payrails-debug-plugin
   ```
4. Click **Add**

If GitHub authentication prompts you, authenticate as your `edwin-payrails` (Payrails-affiliated) account.

### Step 2 — Enable the plugin

1. Switch to the **Plugins** tab
2. Find `payrails-debug@payrails-debug-plugin` in the list
3. Toggle it on
4. When prompted, restart Claude Code

### Step 3 — Verify the install

In a Claude Code session, run `/mcp`. Under "dynamic" you should see:
- `plugin:payrails-debug:plain`
- `plugin:payrails-debug:playwright`
- `plugin:payrails-debug:grafana`

(Slack/Linear/Notion are deduplicated against your claude.ai account-level integrations and won't appear under "dynamic" — that's expected. They still work.)

If Grafana shows "Failed" or doesn't appear, you haven't set up credentials yet. See the next section.

---

## Credential setup (Grafana)

The Grafana MCP needs your Payrails Grafana username and password. There are two paths to provide them — choose based on your security preferences and your team's policy.

### Path A — Quick setup (less secure, faster)

Edit a `.env` file in the plugin folder with raw credentials:

```bash
# Find where the plugin is installed (cache location)
ls ~/.claude/plugins/marketplaces/payrails-debug-plugin/

# Create a .env file with your credentials (NEVER commit this!)
cd ~/.claude/plugins/marketplaces/payrails-debug-plugin/
cat > .env << 'EOF'
GRAFANA_USERNAME="your.username"
GRAFANA_PASSWORD="your-password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
EOF
```

Then `source` the file and launch Antigravity from the same terminal:

```bash
source ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env
open -a "Antigravity" /path/to/your/workspace
```

**Trade-off**: faster setup, but credentials sit on your laptop in plaintext. Not aligned with Payrails security policy. Use only if you're testing or in an emergency.

### Path B — 1Password integrated (recommended, Payrails-security-aligned)

This path keeps credentials in 1Password. They never sit on your disk in plaintext.

**1. Make sure prerequisites are installed**

```bash
op --version          # verify op CLI is installed
op vault list         # verify you're authenticated, see your vaults
```

If `op` isn't installed: `brew install --cask 1password-cli`. Then `op signin`.

Make sure your Grafana credentials are stored in 1Password as an item with username and password fields.

**2. Clone the plugin repository locally**

```bash
mkdir -p ~/Documents/Payrails
cd ~/Documents/Payrails
gh repo clone edwin-payrails/payrails-debug-plugin
cd payrails-debug-plugin
```

(You're cloning the source repo separately so you can edit `.env.tpl` for credential setup. The plugin you installed via Antigravity is a separate cached copy.)

**3. Edit `.env.tpl` to point at your 1Password item**

The committed `.env.tpl` has placeholders. Edit it with your specific 1Password references.

To find your op:// reference path: open 1Password, find your Grafana item, click the menu (•••) on any field, choose **"Copy Secret Reference."** This gives you the exact `op://Vault/Item/field` path.

Open `.env.tpl` in your editor and replace the placeholders:

```bash
# Before
GRAFANA_USERNAME="op://<your-vault>/<your-grafana-item>/username"
GRAFANA_PASSWORD="op://<your-vault>/<your-grafana-item>/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"

# After (example — your vault and item names will differ)
GRAFANA_USERNAME="op://Employee/Grafana/username"
GRAFANA_PASSWORD="op://Employee/Grafana/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
```

**4. Run `op inject` to resolve and write `.env`**

```bash
op inject -i .env.tpl -o .env
```

You'll be prompted for Touch ID or your Mac password. Approve.

This creates a `.env` file in the plugin folder with your real credentials. The `.env` is gitignored — it never leaves your machine.

**5. Source `.env` and launch Antigravity from the same terminal**

```bash
source .env
echo "Pass length: ${#GRAFANA_PASSWORD}"  # safe to check; should print 64
open -a "Antigravity" /path/to/your/workspace
```

The same terminal that has the env vars set must launch Antigravity. **Spotlight launches won't work** — they don't inherit shell env vars.

**6. Verify Grafana works**

In Claude Code, run `/mcp`. The `plugin:payrails-debug:grafana` entry should show "Connected."

**7. (Optional but recommended) Add a shell function for easier daily use**

Add this to your `~/.zshrc`:

```bash
function payrails-claude() {
    cd ~/Documents/Payrails/payrails-debug-plugin
    op inject -i .env.tpl -o .env || return 1
    source .env
    cd "${1:-$HOME/Documents/Payrails/backend}"
    open -a "Antigravity" .
}
```

Reload your shell (`source ~/.zshrc`) and you can now start any debugging session with one command:

```bash
payrails-claude
```

This handles the per-session credential refresh and terminal-launched Antigravity automatically.

---

## Why op-inject and not just `.env` (Path A)?

**Honest answer**: op-inject is what Payrails security policy requires (no plaintext credentials on disk, no agents calling 1Password directly). Path A is a fallback for emergency situations. Use Path B for normal work — it's not much harder once set up, and once you have the `payrails-claude` shell function it's actually easier.

---

## Daily workflow

Once set up:

1. Open a terminal, run `payrails-claude` (or manually do the source-and-launch ritual)
2. Antigravity opens with credentials loaded
3. Open a Claude Code session
4. Describe the merchant issue you're debugging — Edu's `payrails-debug` skill auto-triggers
5. Claude works through investigation, hypothesis, diagnosis using Grafana, Plain, Slack, Linear, Notion as needed
6. When done, optionally invoke `/payrails-response-draft` for merchant communication, `/payrails-knowledge-update` to capture learnings, or `/payrails-recurring-issue-doc` to document the pattern in Notion

---

## Updates

When the plugin maintainer pushes a new version:

### Path A — Antigravity UI (recommended)
1. Open Antigravity → Manage Plugins → Marketplaces tab
2. Click the refresh icon next to `payrails-debug-plugin`
3. Restart Claude Code session (or close/reopen Antigravity if using Grafana — env vars need to stay loaded)

### Path B — Terminal (fallback)
If the UI refresh doesn't seem to work:

```bash
claude plugin update payrails-debug@payrails-debug-plugin
```

You can run this from any folder — the plugin is user-scoped, so the command isn't tied to a specific directory.

Then restart Claude Code.

### Note about `/plugin` slash commands
`/plugin install` and `/plugin marketplace add` slash commands are NOT available in Antigravity-embedded Claude Code. They only work in standalone Claude Code CLI. Use the Manage Plugins UI panel or the terminal command above.

---

## Troubleshooting

### Grafana MCP shows "Failed" in `/mcp`
- You haven't sourced `.env` yet, or credentials haven't loaded
- Verify with: `echo "Pass length: ${#GRAFANA_PASSWORD}"` — should print 64
- If it prints 0: re-run `source .env` and relaunch Antigravity from the same terminal

### Grafana MCP "Failed" but env vars are set
- You launched Antigravity from Spotlight — env vars don't inherit
- Quit Antigravity completely, then `open -a "Antigravity" .` from your terminal

### Skills don't auto-trigger on debugging requests
- Check that the plugin is enabled in Manage Plugins → Plugins tab
- Restart Claude Code session
- If still not working, restart Antigravity

### Plugin appears installed but new MCPs/features from a recent update aren't showing
- Plugin cache is stale; refresh the marketplace (refresh icon in Marketplaces tab)
- If UI refresh doesn't work: `claude plugin update payrails-debug@payrails-debug-plugin` from terminal
- Then restart Claude Code

### "Per-project Disable" in `/mcp` removed Grafana for one workspace
- The Disable button in `/mcp` only disables for the current project, not globally
- Click it again to re-enable, or use a different workspace

### Playwright MCP opens a Chromium browser window
- Expected behavior, not a bug
- Browser stays alive between tool calls for efficiency

### Plugin shows wrong version even after refresh
- Verify with: `cat ~/.claude/plugins/installed_plugins.json | grep -A 3 payrails-debug`
- Look at the `installPath` — it should reference the latest version folder
- If the path still shows an old version, fully restart Antigravity (close completely, relaunch)

---

## What this plugin does NOT include

- The Payrails MCP (`go run ./cmd/payrails_mcp`) — that lives in the backend repo, requires Go and podman, and is for local Payrails service development. It's separate from this plugin.
- Production-only debugging tools (e.g., production Grafana access) — this plugin uses the staging Grafana for safety. Talk to platform team if you need production access.

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
