# Payrails Debug Plugin

A Claude Code plugin for the Payrails Solutions Engineering team that packages merchant integration debugging skills, MCPs, and workflows into a single installable bundle.

When you install this plugin, you get:
- **Debugging skills** — Claude Code knows the Payrails-specific debugging workflow (UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE)
- **Grafana MCP** — query Loki logs and dashboards from inside Claude Code
- **Plain MCP** — read merchant support threads
- **Playwright MCP** — browser automation for looking up provider docs (Adyen, Stripe, etc.)
- **Slack/Linear/Notion MCPs** — search prior team discussions, issues, and runbooks
- **Skills for documenting learnings** — capture knowledge from each debugging session into the right reference files

The plugin installs at **user scope**, meaning once installed it works in any folder you open in Claude Code — your backend repo, a debugging scratch folder, anywhere. You don't need to install it per-project.

---

## Supported environments

This plugin can be installed and used in:
- **Antigravity** (the IDE) with Claude Code — primary supported environment
- **Standalone Claude Code CLI** (`claude` command in a terminal) — also supported

**Not supported:**
- Claude Desktop app's Claude Code mode — that mode only loads Anthropic-curated plugins, not arbitrary GitHub-hosted ones.
- VS Code with the Claude Code extension — likely works similarly to Antigravity but not yet tested. If you try this, let Edwin know what you find.

---

## Prerequisites

The list below shows what you'll need depending on which credential setup path you choose (covered below).

**Always required:**
- **Antigravity or standalone Claude Code CLI** — installed and working
- **GitHub access** to `edwin-payrails/payrails-debug-plugin` — currently a private repo. Ask Edwin to add you as a collaborator. After security review, this moves to `payrails-hub` and access becomes automatic for Payrails GitHub org members.
- **`gh` CLI** — authenticated to a GitHub account that has access to `edwin-payrails/payrails-debug-plugin`. This is whichever account you've been added to as a collaborator — it does NOT have to be a specific Payrails-affiliated account; a personal GitHub account also works as long as it has been granted repo access. If you haven't set up `gh` before, follow GitHub's setup at `https://cli.github.com`. Verify with `gh auth status` — you should see the authorized account as Active with `repo` scope. If you have multiple accounts, switch with `gh auth switch -u <username>`.
- **Grafana credentials** for `https://grafana.telemetry.payrails.io` — your Payrails Grafana username and password.

**Required only if using Path B (recommended) for credentials:**
- **1Password CLI (`op`)** — installed and signed in to your Payrails 1Password vault. Verify with `op vault list`. If not installed: `brew install --cask 1password-cli`, then `op signin`. **If you don't have 1Password CLI and can't easily install it, skip this and use Path A instead** — Path A is the manual `.env` shortcut and works without `op`.
- **Your Grafana credentials stored in 1Password** as an item with username and password fields. (Same fallback applies — if your credentials aren't in 1Password, use Path A.)

**Required only if using Playwright MCP** (browser automation for fetching provider docs):
- **Node.js 18+** — verify with `node --version`. Most Payrails developers already have this. **If Node.js is missing and you don't need browser automation, skip this and continue setup** — the Playwright MCP will fail to load but every other plugin feature works fine. Install Node.js later if you want Playwright.

**Convenience:**
- **Homebrew** — the macOS package manager. Not strictly required, but the easiest way to install `gh`, `op`, or `node` if you don't have them. Install from `https://brew.sh`.

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

After install, fully quit Antigravity (Cmd+Q, not the red X — see the Cmd+Q section below) and reopen. The plugin is now ready, but Grafana won't connect until you complete credential setup below.

---

## Credential setup (Grafana)

The Grafana MCP needs your Payrails Grafana credentials. There are two paths — choose based on whether you have 1Password set up.

Both paths end the same way: a `.env` file gets written, then sourced before launching Antigravity.

### Path A — Manual `.env` (faster, less secure)

**Use only if you don't have 1Password set up, or for emergency testing.** Credentials sit on your laptop in plaintext.

**1. Create `.env` in the marketplace folder:**

```bash
cd ~/.claude/plugins/marketplaces/payrails-debug-plugin/
```

**2. STOP — replace the placeholder values below with your real Payrails Grafana username and password before running this command:**

```bash
cat > .env << 'EOF'
GRAFANA_USERNAME="your.username"
GRAFANA_PASSWORD="your-password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
EOF
```

If you skip the substitution, Grafana will fail to authenticate. If you're not sure what your Grafana username is, log in to `https://grafana.telemetry.payrails.io` and check your profile.

**3. Source `.env` and launch Antigravity (covered below in "Launching Antigravity with credentials loaded").**

### Path B — 1Password integrated (recommended, Payrails-security-aligned)

This path keeps credentials in 1Password. They never sit on your disk in plaintext.

**1. Verify 1Password CLI is set up:**

```bash
op --version
op vault list
```

If `op` isn't installed: `brew install --cask 1password-cli`, then `op signin`.

Your Grafana credentials must be stored in 1Password as an item with username and password fields.

**2. Clone the plugin repo locally** (separate from the installed cache copy — needed because `.env.tpl` lives here):

```bash
mkdir -p ~/Documents/Payrails
cd ~/Documents/Payrails
gh repo clone edwin-payrails/payrails-debug-plugin
cd payrails-debug-plugin
```

**If you've cloned this repo before (e.g., you're a maintainer or contributor)**, the `gh repo clone` command will fail with "destination path already exists." That's expected — skip the clone and just `cd` into your existing checkout:

```bash
cd ~/Documents/Payrails/payrails-debug-plugin
```

Either way, the next steps work the same.

**3. Find your 1Password reference path:**

In 1Password, find your Grafana item, click the menu (•••) on the username field, choose **"Copy Secret Reference."** This gives you the exact `op://Vault/Item/field` path. Repeat for the password field.

**4. Edit `.env.tpl`** to use your specific 1Password references:

```bash
# Before (placeholders in the committed file)
GRAFANA_USERNAME="op://<your-vault>/<your-grafana-item>/username"
GRAFANA_PASSWORD="op://<your-vault>/<your-grafana-item>/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"

# After (example — your vault and item names will differ)
GRAFANA_USERNAME="op://Employee/Grafana/username"
GRAFANA_PASSWORD="op://Employee/Grafana/password"
PAYRAILS_GRAFANA_BIN="$HOME/tools/mcp-grafana-official"
```

**5. Run `op inject` to write `.env`:**

```bash
op inject -i .env.tpl -o .env
```

You'll be prompted for Touch ID or your Mac password. Approve. This creates `.env` with your actual credentials. The `.env` file is gitignored — it never leaves your machine.

**6. Source `.env` and launch Antigravity** (covered below).

---

## Grafana binary setup (required regardless of Path A or B)

The Grafana MCP runs as a local binary. You need to download it once.

**1. Check if it's already installed:**

```bash
ls ~/tools/mcp-grafana-official 2>/dev/null && echo "EXISTS — skip to verification" || echo "NOT FOUND — proceed with download"
```

If it exists, skip to step 5 (verification).

**2. Detect your Mac's architecture:**

```bash
uname -m
```

If output is `arm64` you have Apple Silicon. If `x86_64` you have Intel. The asset name differs.

**3. Download the latest release:**

Go to `https://github.com/grafana/mcp-grafana/releases`. From the latest release's Assets section, download:
- Apple Silicon: `darwin.arm64.grafana.tar.gz`
- Intel: `darwin.x64.grafana.tar.gz`

Or via terminal (replace `<arch>` with `arm64` or `x64`):

```bash
mkdir -p ~/tools && cd /tmp
RELEASE_TAG=$(gh api repos/grafana/mcp-grafana/releases/latest --jq '.tag_name')
curl -fsSL -o mcp-grafana.tar.gz "https://github.com/grafana/mcp-grafana/releases/download/${RELEASE_TAG}/darwin.<arch>.grafana.tar.gz"
```

**4. Extract, move, and make executable:**

```bash
cd /tmp
tar -xzf mcp-grafana.tar.gz
mv mcp-grafana ~/tools/mcp-grafana-official
chmod +x ~/tools/mcp-grafana-official
```

**5. Verify:**

```bash
~/tools/mcp-grafana-official --help
```

You should see a usage message listing flags. If you instead see "cannot be opened because the developer cannot be verified" (macOS Gatekeeper), run:

```bash
xattr -d com.apple.quarantine ~/tools/mcp-grafana-official
```

Then retry the verification.

---

## Launching Antigravity with credentials loaded

Whichever credential path you used (A or B), Grafana won't connect until env vars are loaded into Antigravity's process.

**Critical**: macOS app processes only inherit env vars from the terminal that launched them. Spotlight launches won't work. Already-running Antigravity instances need to be fully quit first.

**1. Fully quit any running Antigravity instance:**

Cmd+Q (or right-click the dock icon and choose Quit). The red X only hides the window — the process keeps running with its old env vars. Verify by checking that the Antigravity icon is no longer in your dock.

**2. From a terminal, source `.env` and launch Antigravity:**

For Path A:
```bash
source ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env
open -a "Antigravity" /path/to/your/workspace
```

For Path B:
```bash
cd ~/Documents/Payrails/payrails-debug-plugin
source .env
open -a "Antigravity" /path/to/your/workspace
```

Replace `/path/to/your/workspace` with your actual project folder (e.g. `~/Documents/Payrails/backend`).

**3. Verify env vars are loaded** (optional but reassuring):

Before the `open -a` line, run:
```bash
echo "Pass length: ${#GRAFANA_PASSWORD}"
```
Should print a number > 0 (typically 64). If it prints 0, the source didn't work.

---

## Verifying the install

In a Claude Code session in the relaunched Antigravity, run `/mcp`.

Expected under "dynamic":
- `plugin:payrails-debug:plain` — Connected
- `plugin:payrails-debug:playwright` — Connected
- `plugin:payrails-debug:grafana` — Connected

You can also run `claude mcp list` from Claude Code's bash tool or any terminal to see the same information.

**About Slack/Linear/Notion**: these are deduplicated against your claude.ai account-level integrations, so they appear in the **claude.ai** section of `/mcp` rather than the **dynamic** section. In `claude mcp list` they may show as "Failed" — that's expected and not a real failure. The functionality is provided through the claude.ai-level connection, not the plugin's. If a Slack/Linear/Notion query in Claude Code works, you're fine.

(See `CONNECTORS.md` for what each MCP is supposed to provide. That file describes design state, not runtime status — for actual runtime, use `/mcp` or `claude mcp list`.)

---

## Daily workflow

Once set up, a debugging session looks like:

1. Open a terminal, source `.env`, launch Antigravity from there (or use the shell function below)
2. In Claude Code, describe the merchant issue you're debugging — Edu's `payrails-debug` skill auto-triggers
3. Claude works through investigation, hypothesis, diagnosis using Grafana, Plain, Slack, Linear, Notion as needed
4. When done, optionally invoke `/payrails-response-draft` for merchant communication, `/payrails-knowledge-update` to capture learnings, or `/payrails-recurring-issue-doc` to document the pattern in Notion

### Optional shell function (recommended for Path B)

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

Reload your shell (`source ~/.zshrc`). Then start any debugging session with one command:
```bash
payrails-claude
```

This handles the credential refresh and terminal-launched Antigravity automatically.

---

## Updates

When the maintainer pushes a new version:

**Recommended:** in Antigravity → `/manage-plugins` → Marketplaces tab → click the refresh icon next to `payrails-debug-plugin`. Then Cmd+Q Antigravity and relaunch from your sourced terminal (env vars need to stay loaded).

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

### Grafana MCP shows "Failed"

Most likely cause is one of these. Check in order:
- **Binary missing**: `ls -la ~/tools/mcp-grafana-official` — should exist and be executable. If not, redo the Grafana binary setup.
- **Env vars not loaded**: in a terminal, run `echo "Pass length: ${#GRAFANA_PASSWORD}"`. If it prints 0, you haven't sourced `.env` in this shell. Run `source .env` from the right path.
- **Antigravity launched without env vars**: even if env vars are in your shell, if you launched Antigravity from Spotlight or it was already running with a stale env, Grafana won't see the credentials. Cmd+Q Antigravity completely, then `source .env && open -a Antigravity` from your terminal.

### `open -a "Antigravity"` brought existing instance to foreground instead of launching fresh

That's how `open -a` works on macOS — it doesn't start a new process if one is already running. Cmd+Q Antigravity completely first (verify the dock icon disappears), then re-run the source-and-open commands.

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
rm -f ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env
claude plugin marketplace remove payrails-debug-plugin
```

Then Cmd+Q Antigravity to clear in-memory plugin state. Optionally also delete the local clone if you used Path B (`rm -rf ~/Documents/Payrails/payrails-debug-plugin/`) and the Grafana binary (`rm ~/tools/mcp-grafana-official`).

The `claude plugin marketplace remove` step is important: it cleans up the marketplace registration in your `~/.claude/settings.json` (under `extraKnownMarketplaces`). Without this step, even after deleting the filesystem clones, Antigravity will see "Marketplace already on disk — declared in user settings" when you try to re-install, blocking a fresh install.

---

## What this plugin does NOT include

- The Payrails MCP (`go run ./cmd/payrails_mcp`) — that lives in the backend repo, requires Go and podman, and is for local Payrails service development. It's separate from this plugin.
- Direct production-Grafana access — debugging primarily uses staging Grafana (`grafana.telemetry.payrails.io`). Some merchant-specific access patterns may differ; talk to platform team if you need access beyond the default staging path.

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
