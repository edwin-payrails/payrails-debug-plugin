# Plugin Lifecycle

This document describes how the Payrails Debug Plugin actually works under the hood — where it stores state, what happens during install/uninstall/update, how env vars reach the MCPs, and how to diagnose failures.

The audience is contributors, maintainers, and anyone debugging unexpected plugin behavior. If you're trying to *use* the plugin, see `README.md`. If you want to know *why* certain choices were made, see `DESIGN_DECISIONS.md`.

---

## Five locations of state

When the plugin is installed and in use, its state spreads across five locations on the user's machine. Understanding which location holds what — and which operation touches which — is essential for clean installs, clean uninstalls, and debugging "the plugin isn't behaving like I expect" issues.

### Location 1 — The git checkout (canonical source)

**Path**: `~/Documents/Payrails/payrails-debug-plugin/` (or wherever the maintainer cloned it)

**What it is**: A local clone of the GitHub repo. This is the canonical source of truth on the maintainer's machine — every file change ultimately needs to flow through here to reach GitHub.

**Who touches it**: Maintainer editing files directly. Tools (like the `payrails-knowledge-update` skill) when the plugin is installed via local-path.

**How edits flow out**: Only via `git commit` and `git push`. Changes here don't automatically appear anywhere else until pushed.

**Note**: Most teammates won't have this location at all — they install the plugin from GitHub without cloning the source repo. Only contributors and maintainers have a checkout.

### Location 2 — Marketplace metadata clone

**Path**: `~/.claude/plugins/marketplaces/payrails-debug-plugin/`

**What it is**: A full clone of the GitHub repo that Antigravity creates automatically when the marketplace is added. Contains all source files (skills, `.mcp.json`, README, etc.) — but Antigravity does NOT load the plugin from here.

**Who touches it**: 
- Created by `claude plugin marketplace add edwin-payrails/payrails-debug-plugin` (via CLI) or the equivalent UI action.
- Refreshed by clicking the refresh icon on the marketplace entry, or running `claude plugin update`.

**Auth boundary**: This is where the GitHub auth check happens. If `gh` is authenticated to an account without repo access, this clone fails silently — the marketplace entry shows up registered but the files never appear here.

### Location 3 — Plugin install cache

**Path**: `~/.claude/plugins/cache/payrails-debug-plugin/payrails-debug/<version>/`

**What it is**: The version-pinned snapshot Claude Code actually loads at runtime. When the plugin is enabled and Claude Code starts, it reads from this path. This is what skills and MCPs are loaded from — not Location 2.

**Who touches it**:
- Created by `claude plugin install payrails-debug@payrails-debug-plugin` (which copies from Location 2 into here).
- When the plugin is GitHub-installed and a tool like `payrails-knowledge-update` writes a learning, the write goes here. **Edits made here are local and volatile** — they get overwritten on the next version-bump cache refresh.

### Location 4 — Process memory

**What it is**: The Antigravity process itself, and the env vars it inherits at startup. Once the plugin is loaded into the Antigravity process, it stays there in memory until the process quits.

**Who touches it**:
- Created when Antigravity launches.
- Cleared only by fully quitting (Cmd+Q from the dock or App menu — not the red X, which only hides the window).
- Env vars (Grafana credentials etc.) are inherited only at process startup. Setting env vars in a terminal AFTER Antigravity has started will not propagate to the running process.

### Location 5 — User settings (marketplace registration)

**Path**: `~/.claude/settings.json` under the `extraKnownMarketplaces` key

**What it is**: A registry entry that records "this marketplace is declared for this user." Separate from the filesystem clone in Location 2.

**Why it matters**: 
- `claude plugin uninstall` and `rm -rf` on Locations 1, 2, or 3 do NOT touch this entry.
- The entry persists across uninstalls. Antigravity sees "marketplace already declared" even after the filesystem clone is gone.
- A fresh re-install attempt is blocked by "Marketplace already on disk — declared in user settings" until this entry is removed.

**How to clean**: Run `claude plugin marketplace remove payrails-debug-plugin`.

---

## Install flow — what actually happens

When a teammate runs the two install commands from the README:

```bash
claude plugin marketplace add edwin-payrails/payrails-debug-plugin
claude plugin install payrails-debug@payrails-debug-plugin
```

Step 1 — `claude plugin marketplace add`:
1. Reads the GitHub repo URL.
2. Uses `gh` CLI auth to clone the repo into Location 2.
3. Writes a marketplace registration to Location 5 (settings.json).
4. Succeeds with: `Adding marketplace... ✓ Marketplace 'payrails-debug-plugin' added`.

Step 2 — `claude plugin install`:
1. Reads the marketplace clone in Location 2 to find the plugin manifest (`.claude-plugin/plugin.json`).
2. Copies the plugin's relevant files (skills, `.mcp.json`, etc.) from Location 2 into Location 3 (versioned cache).
3. Writes an entry to `~/.claude/plugins/installed_plugins.json` registering the plugin as installed.
4. Succeeds with: `✔ Successfully installed plugin: payrails-debug@payrails-debug-plugin (scope: user)`.

After both commands, Cmd+Q Antigravity to clear Location 4, then relaunch from a terminal that has `.env` sourced — the new Antigravity process loads the plugin from Location 3, MCPs spawn, and env vars from the launching terminal propagate into Location 4.

---

## What can go wrong (and where)

### Marketplace add succeeds but plugin doesn't appear in Plugins tab

Usually means Step 2 of the install didn't run. The marketplace clone is in Location 2, but Location 3 was never populated and `installed_plugins.json` has no entry for this plugin.

In some Antigravity versions, the UI's marketplace-add silently skips the plugin install step. The fix is to run `claude plugin install payrails-debug@payrails-debug-plugin` from any terminal, then restart Antigravity.

### Marketplace add succeeds but no files in Location 2

Means the GitHub clone failed silently (auth issue). The settings.json entry exists in Location 5, but `~/.claude/plugins/marketplaces/payrails-debug-plugin/` doesn't.

Verify with `gh auth status` that the active account has access to the repo. If the active account is wrong, switch with `gh auth switch -u <username>` and retry the marketplace add.

### Plugin behaves like an old version after update

Most common cause: Antigravity is still running with the old plugin loaded in Location 4 (process memory). Cmd+Q completely (red X is not enough — see Location 4 for why), then relaunch.

Second possible cause: cache staleness. The marketplace cache (Antigravity's record of what versions exist) might be stale and not yet aware of the new version. Refresh the marketplace from the UI (Manage Plugins → Marketplaces tab → click the refresh icon next to the marketplace entry), then update the plugin again.

### Knowledge captured by `payrails-knowledge-update` doesn't appear for teammates

This is by design, not a bug — but it surprises people. When the plugin is installed from GitHub, the knowledge-update skill writes to Location 3 (the cache), not Location 1 (the canonical source). The cache edit improves the local user's session but doesn't propagate to GitHub or to other teammates.

To make a learning flow back to all teammates, someone with repo access has to promote the change: copy from Location 3 to a maintainer's Location 1, commit, push. From there, normal update flow distributes it.

For active development where this matters, install the plugin via local-path (pointing at Location 1 directly) instead of from GitHub — that way the knowledge-update skill writes to the canonical clone, and the maintainer just commits and pushes when ready.

### "Marketplace already on disk" message during install

The `claude plugin marketplace add edwin-payrails/payrails-debug-plugin` command, when run a second time after the marketplace is already registered, prints:

> `✓ Marketplace 'payrails-debug-plugin' already on disk — declared in user settings`

The checkmark indicates this is a success message, not an error. The command did what it was asked to do: it confirmed the marketplace registration. There's nothing to fix.

The phrasing is genuinely confusing on first read because "already on disk — declared in user settings" sounds like a stale-state warning. It isn't. It's the CLI's way of saying "this is already done." If you (or Claude Code, in autonomous-install scenarios) are re-running marketplace-add for any reason — retrying after a partial install, scripting an idempotent setup, etc. — this message is the expected output and you can proceed.

If you actually want a fresh marketplace state (because something is genuinely broken), follow the Complete uninstall sequence below — `claude plugin marketplace remove payrails-debug-plugin` is the command that clears the registration, after which a fresh `marketplace add` will print the first-install confirmation message instead.

---

## Complete uninstall

To remove every trace of the plugin from a machine, all five locations must be addressed:

```bash
claude plugin uninstall payrails-debug@payrails-debug-plugin    # cleans Location 3 + the registry entry
rm -rf ~/.claude/plugins/cache/payrails-debug-plugin/           # cleans any remaining cache leftovers
rm -rf ~/.claude/plugins/marketplaces/payrails-debug-plugin/    # cleans Location 2
rm -f ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env # if a credentials file was placed here (Path A)
claude plugin marketplace remove payrails-debug-plugin          # cleans Location 5 (settings.json registration)
# Then Cmd+Q Antigravity to clear Location 4 (process memory)
```

If a maintainer also wants to remove their own canonical clone (Location 1):

```bash
rm -rf ~/Documents/Payrails/payrails-debug-plugin/
```

After all of these, the machine is back to fresh-teammate state for this plugin. Other plugins in the user's Claude Code setup remain untouched.

---

## Env var propagation to MCPs

Some MCPs (currently just Grafana) require credentials provided through env vars. The propagation chain has four steps, and a break at any of them causes the MCP to fail.

### Step 1 — Credentials end up in `.env`

Either by `op inject -i .env.tpl -o .env` (Path B) or by manually writing values into `.env` (Path A). Either way, the file ends up with literal credential values that can be sourced.

### Step 2 — A terminal sources `.env` into its environment

`source ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env` (Path A) or `source ~/Documents/Payrails/payrails-debug-plugin/.env` (Path B).

The current terminal now has `GRAFANA_USERNAME` and `GRAFANA_PASSWORD` as environment variables.

### Step 3 — Antigravity launches with that terminal as parent

`open -a "Antigravity" /path/to/workspace` from the same sourced terminal. The Antigravity process inherits the parent terminal's env vars at startup.

This step has two common failure modes:
- **Spotlight launch**: Spotlight-launched apps don't inherit shell env vars, only launchd-level vars. A teammate who launches Antigravity from Spotlight after sourcing `.env` will not have credentials in Antigravity's process.
- **Already-running Antigravity**: `open -a` brings an existing process to foreground rather than starting a new one. The existing process kept its old env vars (or none) from when it originally launched. Cmd+Q first to fully quit, then relaunch.

### Step 4 — MCP subprocess inherits Antigravity's env vars

When Antigravity loads the plugin, it reads `.mcp.json` and spawns each MCP as a subprocess. The Grafana MCP entry uses `${VAR}` substitution that resolves from Antigravity's environment. The subprocess inherits these resolved values.

If Step 3 succeeded, Step 4 happens automatically. If Step 3 failed, the substitution resolves to empty strings and the MCP starts with no credentials, returning a connection failure when it tries to authenticate to Grafana.

---

## MCP failure diagnostics

When `/mcp` shows an MCP as Failed, work through these checks based on which MCP is affected.

### Grafana MCP — "Failed"

Check in this order:

**1. Binary present and executable**:
```bash
ls -la ~/tools/mcp-grafana-official
~/tools/mcp-grafana-official --help
```
The first command should show the file with execute permissions. The second should print a usage message. If either fails, the binary is missing or broken — redo the Grafana binary setup from the README.

**2. Env vars loaded**:
```bash
echo "Pass length: ${#GRAFANA_PASSWORD}"
```
Run this in the same terminal that launched Antigravity. Should print a number greater than 0 (typically 64). If it prints 0, the source didn't work — re-source `.env`, then re-launch Antigravity.

**3. Antigravity launched correctly**:
- Was it started from a terminal that had `.env` sourced? (Spotlight launches don't work.)
- Was Antigravity fully quit before re-launching? (`open -a` on a running process doesn't refresh env vars.)

If all three checks pass and Grafana still fails, the credentials themselves may be invalid — try logging into `https://grafana.telemetry.payrails.io` directly to verify they work.

### Plain MCP — "Failed"

Plain is a hosted MCP (HTTP-based). Failure is usually an OAuth issue. Check:
- The MCP needs the Plain integration authorized via Anthropic's OAuth flow. From `/mcp`, click the failed entry — there should be a "Connect" or "Needs Auth" prompt.

### Playwright MCP — "Failed"

Playwright is an `npx` stdio MCP. Common causes:
- **Node.js missing**: `node --version` should print v18+. If the command fails, install Node.js.
- **First-run download stuck**: on first invocation, `npx @playwright/mcp@latest` fetches the package. If your network is slow or restricted, this can hang. Wait, or try running the npx command manually in a terminal to see what happens.
- **Chromium download**: Playwright downloads a Chromium browser on first browser action (separate from the npm install). This is one-time; subsequent runs reuse it.

### Slack / Linear / Notion MCP — "Failed" but functionality works

This is expected behavior, not a real failure. These three MCPs are declared in the plugin's `.mcp.json` as HTTP-based, but most users have Slack/Linear/Notion already connected via Anthropic's claude.ai-level integrations. The plugin's declarations get deduplicated by URL match against the claude.ai connections.

Result: the plugin's version shows as Failed in `claude mcp list` (because the dedup prevented it from connecting), but the functionality is provided through the claude.ai-level connection. In `/mcp`, the working MCPs show under the **claude.ai** section, not the **dynamic** section.

To verify it's actually working: try a Slack/Linear/Notion query in Claude Code. If it works, you have functional access. If it doesn't, the claude.ai integration itself isn't authenticated — fix that, not the plugin.

---

## Update flow

Updates have two distinct caches that both need to refresh:

### Marketplace cache

Records what versions of the plugin are available in the marketplace. Refreshing this cache asks GitHub: "what's the latest version?" Without a refresh, even a fresh `claude plugin update` doesn't know that a new version exists.

Refresh via UI: Manage Plugins → Marketplaces tab → click the refresh icon next to the marketplace entry.

### Plugin cache

The actual installed plugin code at Location 3. Updating this cache copies the latest version from the marketplace cache into a new versioned subfolder.

Update via UI: Manage Plugins → Plugins tab → toggle off and on (this triggers re-installation from the marketplace).

Update via CLI: `claude plugin update payrails-debug@payrails-debug-plugin`.

### Why it's a two-step

If only the plugin cache is refreshed but the marketplace cache is stale, the system thinks "I'm already at the latest." If only the marketplace cache is refreshed but the plugin cache isn't updated, the user keeps running the old version even though a new one is known to exist.

When a maintainer pushes a new version, teammates need both: refresh marketplace first (to learn about the new version), then update plugin (to actually pick it up). The UI refresh icon does both in one click; the CLI requires running both commands explicitly.

---

## Testing the plugin: Claude-Code-driven autonomous installs

When testing this plugin's install flow as a fresh-teammate simulation — i.e. having Claude Code in Antigravity drive the entire install autonomously by reading the README — Claude Code exhibits a few behaviors that don't show up during normal teammate use, and which need to be accounted for in the test setup and cleanup.

This section is for maintainers running these tests, not for end-users.

### Behavior: autonomous memory-file creation

When Claude Code completes an install task, it autonomously writes memory files capturing what it learned about the user and the project. These files live under `~/.claude/projects/<launch-folder>/memory/`, where `<launch-folder>` is a slug of whatever folder Antigravity was opened in.

Files created on a typical install run:
- `user_role.md` — Claude Code's inferred description of who the user is (name, role, email)
- `project_<plugin-name>.md` — install state and any friction notes Claude Code captured during the run
- `MEMORY.md` — index linking to the above

These memory files are *project-scoped*: they apply only when Claude Code is launched in that specific folder. They persist across sessions until explicitly deleted.

For real-teammate use this behavior is fine — useful, even, since it carries learnings forward. But for fresh-teammate-simulation tests, it's a problem because:

1. The test is supposed to simulate a user encountering the plugin for the first time. Existing memory files violate that.
2. Claude Code infers the *real* user identity from `git config --global user.email`, system metadata, etc., even when the test is being run under a different GitHub identity (e.g. a personal account standing in for a teammate). This contaminates future Claude Code sessions on the maintainer's machine with a "you are Edwin Samuel, maintainer" framing that a real teammate's Claude Code wouldn't have.

### Behavior: launch folder becomes a "project"

If the test launches Antigravity from `$HOME` (which is the cleanest way to simulate a teammate not having any project context yet), Claude Code creates an entry under `~/.claude/projects/-Users-<username>/memory/` — treating `$HOME` as a project. This is harmless but unusual; the directory will accumulate memory files until explicitly cleaned.

### Cleaning up after a test run

After completing an autonomous-install test, remove the memory files Claude Code created. The exact paths depend on which folder Antigravity was launched from:

```bash
find ~/.claude/projects -name "user_role.md" -o -name "project_payrails*.md" -o -name "MEMORY.md" 2>/dev/null
```

Review the output. Memory files with timestamps from the test run are candidates for removal. Memory files with older timestamps are pre-existing real usage and should be left alone — distinguish before deleting.

To remove the test-run files, the typical pattern is to delete the entire `memory/` subfolder under whichever launch-folder slug was created during the test:

```bash
rm -rf ~/.claude/projects/-Users-<username>/memory/
```

Use the path from the `find` output above. Don't blanket-delete `~/.claude/projects/` — that has unrelated session transcripts and other plugins' state.

### Bootstrap-prompt redaction list (test-only)

When prompting Claude Code to drive an install autonomously, include an explicit list of files whose contents must not be printed back to the test driver. The minimum list:

- `.env`
- `~/.claude/settings.json`
- 1Password CLI output
- `~/.zshrc`

The first three are obvious; the fourth is the one that's easy to miss. During an install, Claude Code naturally runs `tail ~/.zshrc` or `cat ~/.zshrc` to verify whether the optional shell function is already present. If the user has plaintext credentials exported in `.zshrc` (e.g., `export ANTHROPIC_API_KEY=...`), those values appear in stdout and risk being captured in screenshots or transcripts. Add `~/.zshrc` to the redaction list to prevent this — instruct Claude Code to use existence-only checks (e.g., `grep -n "payrails-claude" ~/.zshrc` rather than `tail ~/.zshrc`).

### Optional: instruct Claude Code not to write memory files

If you'd rather not deal with cleanup at the end of the test, add an explicit instruction to the bootstrap prompt:

> Do not write to memory files (`user_role.md`, `MEMORY.md`, project memory). Do not infer the user's real identity into persistent state.

This skips the memory-file creation behavior entirely. Cleanup then doesn't apply. The trade-off is that you lose Claude Code's own captured friction notes from the run, which can sometimes be useful as cross-check evidence.

---

## Updating this doc

If you discover a new mechanism, state location, or failure mode that isn't documented here, add it. Keep the structure: describe what it is, where it lives, who touches it, and how to diagnose problems related to it.

If a mechanism changes (e.g., Antigravity introduces a new install path, or env var propagation changes due to a launchd update), document the new behavior alongside the old — don't delete the old entry. Teammates running older Antigravity versions still need the old guidance.

For decisions about *why* the plugin works this way (rather than what it does), see `DESIGN_DECISIONS.md`.

For workflow questions (how to contribute, branch naming, PR conventions), see `CONTRIBUTING.md`.
