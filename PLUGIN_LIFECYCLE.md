# Plugin Lifecycle

This document describes how the Payrails Debug Plugin actually works under the hood — where it stores state, what happens during install/uninstall/update, how env vars reach the MCPs, and how to diagnose failures.

The audience is contributors, maintainers, and anyone debugging unexpected plugin behavior. If you're trying to *use* the plugin, see `README.md`. If you want to know *why* certain choices were made, see `DESIGN_DECISIONS.md`.

> **⚠️ Grafana migrated to the `gcx` CLI (2026-06-18).** Everything in this doc about Grafana *credentials* — the `op inject` / `.env.tpl` flow, the `mcp-grafana` binary install, the "Maintainer commit cycle / finding #14" `.env.tpl` revert-restore, the Grafana-specific Reset-playbook steps, and the env-var launch ritual — is **superseded and kept only as historical record**. Grafana is now accessed via the `gcx` CLI (`gcx login`, browser OAuth — no `.env`, no 1Password, no binary download, no launch ritual), so none of that machinery exists for Grafana anymore. For the current state see the "Grafana → gcx CLI migration" update at the top of `BUILD_HANDOFF.md`, the "Grafana access: gcx CLI" entry in `DESIGN_DECISIONS.md`, and "Grafana setup" in `README.md`. The **non-Grafana** lifecycle content below (install/uninstall/update mechanics, the five state locations, the Temporal MCP) remains accurate.

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

**`installPath` semantic nuance**: The `installPath` field in `~/.claude/plugins/installed_plugins.json` always references this cache path, regardless of whether the install came from a GitHub marketplace or a local-directory marketplace. However, observation suggests that for local-directory marketplaces, the runtime source-of-truth for skill content is effectively the canonical clone (Location 1) — edits to files in Location 1 are visible to running skills without an explicit refresh. The mechanism (transparent cache-from-source-on-load, symlinks, or runtime-aware loading) is opaque, but the empirical behavior is what matters for the maintainer rule about local-path installs.

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

For active development where this matters, install the plugin via local-path (pointing at Location 1 directly) instead of from GitHub — that way the knowledge-update skill writes are reflected in the canonical clone, and the maintainer just commits and pushes when ready.

### "Marketplace already on disk" message during install

The `claude plugin marketplace add edwin-payrails/payrails-debug-plugin` command, when run a second time after the marketplace is already registered, prints:

> `✓ Marketplace 'payrails-debug-plugin' already on disk — declared in user settings`

The checkmark indicates this is a success message, not an error. The command did what it was asked to do: it confirmed the marketplace registration. There's nothing to fix.

The phrasing is genuinely confusing on first read because "already on disk — declared in user settings" sounds like a stale-state warning. It isn't. It's the CLI's way of saying "this is already done." If you (or Claude Code, in autonomous-install scenarios) are re-running marketplace-add for any reason — retrying after a partial install, scripting an idempotent setup, etc. — this message is the expected output and you can proceed.

If you actually want a fresh marketplace state (because something is genuinely broken), follow the Complete uninstall sequence below — `claude plugin marketplace remove payrails-debug-plugin` is the command that clears the registration, after which a fresh `marketplace add` will print the first-install confirmation message instead.

### `op inject` fails with "invalid secret reference 'op://': too few '/'"

This error comes from `op inject` finding either malformed `op://` references or unfilled placeholders in `.env.tpl`.

Possible causes:
1. **Comment lines containing `op://` substrings**: fixed in v0.1.6, where comment lines like `# Path format: vault-name/item-name/field-name` no longer contain literal `op://`. If you see this error on a current `.env.tpl`, ensure your local copy hasn't been modified.
2. **Unfilled angle-bracket placeholders**: the committed `.env.tpl` has lines like `op://<your-vault>/<your-grafana-item>/username`. Until each user replaces those with their real 1Password references (e.g., `op://Private/Edwin Grafana/username`), `op inject` will fail because there's no actual vault literally named `<your-vault>`. This is the expected first-run state for a fresh teammate; the README documents the fill-in step.
3. **Maintainer's `.env.tpl` was reverted to committed state**: the maintainer typically edits `.env.tpl` once with their real `op://` references for daily use. If a Reset C playbook included `git checkout .env.tpl`, it reverts to placeholders and breaks the maintainer's daily flow. See "Testing the plugin → Reset playbooks → Reset C" below for the corrected approach.
4. **Maintainer prepared a commit and reverted `.env.tpl` to committed state**: same mechanism as cause 3, different trigger. Whenever the maintainer pushes a PR, they need `.env.tpl` in committed (placeholder) state so the maintainer's personal `op://` references don't get committed to the public repo. After the merge, daily use needs the real refs back. See the "Maintainer commit cycle" subsection below for the documented before/after sequence.

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

### Snowflake MCP — auth model and gotchas

Snowflake is an `npx` stdio MCP wrapped in **`mcp-remote`** (a local proxy to the Snowflake-hosted server). The *why* of this design is in `DESIGN_DECISIONS.md` ("Snowflake access: `mcp-remote`…"); the operational mechanics:

- **Auth is per-user, one-time-ish.** First use opens a browser to log into Snowflake and approve the `ANALYST` role. `mcp-remote` caches the token (access + refresh) in **`~/.mcp-auth`** and refreshes it silently, so it's not re-prompted each session. Re-auth happens only when the refresh token expires (the integration's `OAUTH_REFRESH_TOKEN_VALIDITY`) or the cache is cleared.
- **"Needs authentication" in `/mcp` is the pre-login state**, not a failure — it connects after the one-time browser login. **"tables … do not exist or are not authorized"** at *query* time means the user lacks the Snowflake `ANALYST` grant (request in #help), not a config problem.
- **Port `3334` must be free at auth time.** `mcp-remote` listens on `3334` for the OAuth redirect (matching the registered redirect URI). If `3334` is occupied — e.g. a *second* Claude client running its own auth flow — `mcp-remote` silently picks a random port and the redirect no longer matches → "OAuth callback port … in use" / redirect-mismatch. Fix: don't run two clients through Snowflake auth at once; free `3334` (`lsof -ti:3334`).
- **Cross-client token sharing.** All clients on the machine share `~/.mcp-auth`, so a token minted by one (e.g. terminal `claude`) is reused by others (Antigravity, Cowork) — which is why a client may connect *without* its own browser popup. The flip side: a client's *failed* auth attempt can clobber the shared token; re-auth from a working client restores it.
- **Cowork needs its own config.** Cowork doesn't read the plugin's `.mcp.json` for this — the same `snowflake` block must be added to `claude_desktop_config.json`. See the Snowflake MCP Access Notion guide (cowork section).

---

## Update flow

Updates have two distinct caches that both need to refresh:

### Marketplace cache

Records what versions of the plugin are available in the marketplace. Refreshing this cache asks GitHub: "what's the latest version?" Without a refresh, even a fresh `claude plugin update` doesn't know that a new version exists.

Refresh via UI: Manage Plugins → Marketplaces tab → click the refresh icon next to the marketplace entry.

### Plugin cache

The actual installed plugin code at Location 3. Updating this cache copies the latest version from the marketplace cache into a new versioned subfolder.

Update via UI: Manage Plugins → Plugins tab → toggle off and on (this triggers re-installation from the marketplace). **Note**: this UI toggle path has been observed to be unreliable in some Antigravity versions — the toggle completes but doesn't actually pull the new version. The CLI command below is more reliable.

Update via CLI: `claude plugin update payrails-debug@payrails-debug-plugin`. **This is the recommended primary mechanism.**

### Why it's a two-step

If only the plugin cache is refreshed but the marketplace cache is stale, the system thinks "I'm already at the latest." If only the marketplace cache is refreshed but the plugin cache isn't updated, the user keeps running the old version even though a new one is known to exist.

When a maintainer pushes a new version, teammates need both: refresh marketplace first (to learn about the new version), then update plugin (to actually pick it up). The UI refresh icon does both in one click for the marketplace cache; the plugin cache then needs the CLI update command to actually install the new version.

---

## Path A (manual `.env`): heredoc-write hazard

When following Path A's manual credential setup, Claude Code in autonomous-install scenarios typically writes the `.env` file using a heredoc:

```bash
cat > ~/.claude/plugins/marketplaces/payrails-debug-plugin/.env << 'EOF'
GRAFANA_USERNAME="actual.username"
GRAFANA_PASSWORD="actual-password-value-shown-in-cleartext"
EOF
```

The heredoc body — including the actual credential values being written — is visible in Claude Code's chat output by default. The values appear in the conversation transcript and in any screenshots taken of the install flow.

This is a real leak risk:
- Anyone who later reads the conversation sees the credentials.
- Screenshots of the install flow may end up shared in tickets, demo recordings, or pasted into other conversations.
- The credentials persist in the conversation history even after they've been "used."

**For maintainers running Path A tests**: assume the heredoc will be visible. Treat any credentials used during a Path A test as potentially-leaked, rotate them after the test, and avoid sharing screenshots of the install flow without redaction.

**For end users following Path A on their own machine**: the heredoc is visible in your local Claude Code session, which is less of a concern since you're the only viewer. But if you share that session (export, screenshot, or pair-driving), the credentials go with it.

**Why Path A specifically**: Path B (op-inject) avoids this hazard entirely. The `op inject` step writes from 1Password references that themselves aren't secrets — only the resolved values, written to disk via `op inject`'s own redaction-aware mechanics, contain secrets. The agent never has the values in its own output.

**Mitigation pending in v0.1.7+**: Path A's documented install flow could be reworked to write the `.env` via a method that doesn't echo to chat — e.g., prompting the user to type credentials into a `read -s` prompt outside Claude Code's view, or providing a `.env.example` and instructing the user to manually populate it.

---

## Maintainer commit cycle: `.env.tpl` revert before push, restore after merge

> The **full release flow** (branch → bump → commit → PR → merge → distribute) and the **rollback playbook** live in `GIT_WORKFLOW.md`. This section is the `.env.tpl` *mechanics* used within that flow (finding #14).

The maintainer keeps a working `.env.tpl` with their own real `op://` references (e.g., `op://Private/Edwin Grafana/username`) so the daily-use shell function `payrails-claude` produces a working `.env` from `op inject`. The committed `.env.tpl` in the repo, on the other hand, must keep generic placeholder text (`op://<your-vault>/<your-grafana-item>/username`) so teammates see what to fill in for their own setup.

This creates a tension that the maintainer must manage manually around any commit:

1. **Daily state**: `.env.tpl` has the maintainer's real `op://` refs. `payrails-claude` works.
2. **Before a commit/PR**: revert `.env.tpl` to the committed (placeholder) state. Otherwise `git status` shows it as modified, the modification would be staged, and the maintainer's personal vault references would land in a public-to-collaborators commit.
3. **During the commit/PR**: only commit the intended changes. `.env.tpl` should not appear in `git diff --stat`.
4. **After the merge**: re-apply the maintainer's real refs so daily use works again.

### Before a commit — revert to committed state

```bash
cd ~/Documents/Payrails/payrails-debug-plugin
git checkout .env.tpl
git status
```

`.env.tpl` should no longer appear under "Changes not staged for commit." If you forgot to do this and `.env.tpl` is in your staged changes, unstage it (`git restore --staged .env.tpl`) and then revert.

If you discover after pushing that `.env.tpl` was accidentally committed with maintainer-real refs, you'll need to push a follow-up commit reverting it (`git checkout` from the previous-good main, commit, push) and consider whether the personal references need rotation. Real `op://` paths aren't credentials by themselves (they're pointers to 1Password, not secrets), but they do leak personal vault structure that the maintainer may prefer to keep private.

### After the merge — restore real refs

```bash
cd ~/Documents/Payrails/payrails-debug-plugin
sed -i.bak 's|op://<your-vault>/<your-grafana-item>/username|op://<MAINTAINER_VAULT>/<MAINTAINER_ITEM>/username|' .env.tpl
sed -i.bak 's|op://<your-vault>/<your-grafana-item>/password|op://<MAINTAINER_VAULT>/<MAINTAINER_ITEM>/password|' .env.tpl
rm -f .env.tpl.bak
```

Replace `<MAINTAINER_VAULT>` and `<MAINTAINER_ITEM>` with the maintainer's actual values (e.g., `Private/Edwin Grafana`). Verify with `cat .env.tpl` — lines 9 and 10 should now have the real refs back.

After the restore, `git status` will show `.env.tpl` as modified again. That's the maintainer's personal working state and should NOT be committed — the next commit cycle starts again with another `git checkout .env.tpl` before pushing.

### Long-term simpler approach (deferred)

The fundamental fix to this back-and-forth is a `.env.tpl.local` pattern: a gitignored sibling file that holds the maintainer's real refs, with `payrails-claude` checking for it first and falling back to `.env.tpl` if absent. That eliminates the tension entirely — `.env.tpl` stays at committed (placeholder) state always, and the maintainer's real refs live separately in a never-committed file.

This is a real architectural change (changes to the shell function template, gitignore, and the documented setup flow) and is captured in BUILD_HANDOFF as a v0.1.7+ candidate.

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

### Behavior: Antigravity restores the last-open folder on launch

When Antigravity is launched fresh (after Cmd+Q), it doesn't open with a blank welcome screen — it restores whichever folder was last open. For maintainer use this is convenient. For fresh-teammate tests it's a contamination: the launched Antigravity has a folder context that a fresh teammate wouldn't have.

This behavior interacts badly with a broken `~/.zshrc`: when `~/.zshrc` has a parse error, Antigravity may not honor the `open -a folder` argument and will fall back to its last-known folder. This is one reason the pre-test sanity check (see below) verifies `~/.zshrc` loads cleanly before any Reset A or test launch.

**Fix during tests**: after Antigravity launches, use Cmd+Shift+N to open a new no-folder window before starting the Claude Code session. Confirm by checking the window title or breadcrumb — it should not show any project name.

### Behavior: maintainer's `payrails-claude` shell function suppresses Claude Code's question-asking

The recommended teammate setup includes a `payrails-claude` shell function in `~/.zshrc` that automates the daily-use launch sequence. For maintainer daily use, this function is essential.

For fresh-teammate-simulation tests, the function's *presence* changes Claude Code's behavior in a subtle and important way: when Claude Code inspects `~/.zshrc` during the install flow (to check if the function exists per the README's setup), it sees a function that points at the maintainer's clone path. Claude Code then:

1. Discovers the maintainer's canonical clone exists at the path the function references.
2. May try to consolidate its install into that existing clone instead of using its own newly-created clone.
3. *Doesn't ask the README's natural setup questions* (vault item name, default workspace, etc.) because it sees an existing setup pattern and infers continuity.

In testing, removing the function (commenting out / move-aside, see Reset playbooks) noticeably changed Claude Code's behavior in the next run — it began asking the questions the README's setup flow expects, and stopped trying to consolidate into the maintainer clone.

This means: any fresh-teammate test where the `payrails-claude` function is active is not a true fresh-teammate simulation. The function must be neutralized during Reset A and restored in Reset C.

### Behavior: gh multi-account state confuses Claude Code

If the maintainer has multiple `gh` accounts authenticated (e.g., `EdwinSamuel7` for teammate-simulation and `edwin-payrails` as the actual repo owner), `gh auth status` shows both accounts. Claude Code reads this and reasons about which account to use — sometimes attempting to switch accounts even when the active account already has the necessary access.

A real teammate would only have one `gh` account; the multi-account state is a maintainer-machine artifact.

**Fix during tests**: include explicit guidance in the bootstrap prompt:

> Don't switch gh accounts. Use whichever account is currently active — it already has the access we need.

### Pre-test sanity check (run before Reset A)

Before running Reset A — and certainly before launching Antigravity at any test folder — confirm the maintainer's shell environment loads cleanly:

```bash
zsh -i -c 'echo zshrc-loaded-without-errors'
```

Expected: prints `zshrc-loaded-without-errors` with no parse errors above it.

If the output shows a parse error (e.g., `parse error near '}'`), `~/.zshrc` is broken in some way unrelated to the plugin and needs fixing before any test can run. Reasons this matters:
- Reset A's `~/.zshrc` move-aside step writes a filtered version of `~/.zshrc`. If the source file is already broken, the filtered version inherits the brokenness.
- Antigravity's `open -a folder` argument may not be honored when `~/.zshrc` has parse errors — Antigravity falls back to last-known folder, contaminating the test.
- The maintainer's daily-use tools (including `payrails-claude`) may have been silently broken before the test started, and the test is the first time it surfaces.

If the sanity check fails, fix `~/.zshrc` first (or restore from a known-good backup) before proceeding.

### Reset playbooks

> **Reset A/B/C are for *testing* a clean install — they are NOT part of a push/release.** A normal release never runs them; the only per-push "reset" is the `.env.tpl` revert/restore in the Maintainer commit cycle above. For the release/push flow, see `GIT_WORKFLOW.md`.

There are three reset scenarios. Run the one that matches your situation. They're explicit because mixing them up is how locations get out of sync.

#### Reset A — Pre-test (bring machine to fresh-teammate state)

**When to run**: Before starting any fresh-teammate-simulation test phase.

**Prerequisite**: Run the pre-test sanity check above. Don't proceed if `~/.zshrc` has parse errors.

**Cleans**: plugin install state (Locations 2, 3, 5), maintainer `.env` and `.env.tpl` (move-aside backups + revert live `.env.tpl` to placeholder state), Grafana binary, `/tmp` Grafana artifacts, `~/.zshrc` shell function (move-aside backup using awk block-skip, NOT line-based grep filter or in-place comment markers).

```bash
# === Chunk A1: plugin uninstall + filesystem + registration ===
claude plugin uninstall payrails-debug@payrails-debug-plugin
rm -rf ~/.claude/plugins/cache/payrails-debug-plugin/
rm -rf ~/.claude/plugins/marketplaces/payrails-debug-plugin/
claude plugin marketplace remove payrails-debug-plugin

echo "--- verify chunk A1 ---"
cat ~/.claude/plugins/installed_plugins.json | grep -i payrails-debug || echo "INSTALLED_PLUGINS_CLEAN"
cat ~/.claude/settings.json | python3 -c "import json,sys; d=json.load(sys.stdin); ekm=d.get('extraKnownMarketplaces', {}); print('PAYRAILS_REGISTRATION_PRESENT' if 'payrails-debug-plugin' in ekm else 'EXTRA_KNOWN_MARKETPLACES_CLEAN')"
ls -la ~/.claude/plugins/cache/ 2>/dev/null | grep -i payrails || echo "CACHE_FOLDER_CLEAN"
ls -la ~/.claude/plugins/marketplaces/ 2>/dev/null | grep -i payrails || echo "MARKETPLACE_FOLDER_CLEAN"
```

```bash
# === Chunk A2: maintainer state move-aside (.env, .env.tpl, Grafana binary) ===
mv ~/Documents/Payrails/payrails-debug-plugin/.env ~/Documents/Payrails/payrails-debug-plugin/.env.maintainer-backup 2>/dev/null
cp ~/Documents/Payrails/payrails-debug-plugin/.env.tpl ~/Documents/Payrails/payrails-debug-plugin/.env.tpl.maintainer-backup
cd ~/Documents/Payrails/payrails-debug-plugin && git checkout .env.tpl && cd -
mv ~/tools/mcp-grafana-official ~/tools/mcp-grafana-official.bak 2>/dev/null

echo "--- verify chunk A2 ---"
ls -la ~/Documents/Payrails/payrails-debug-plugin/.env* 2>/dev/null
ls -la ~/tools/ | grep -i grafana
echo "--- .env.tpl head (should show placeholders, not real refs) ---"
head -15 ~/Documents/Payrails/payrails-debug-plugin/.env.tpl
```

The `.env.tpl` is *copied* (not moved) to a backup because the maintainer's working `.env.tpl` typically has real `op://` references that they need restored after the test. The `git checkout .env.tpl` immediately afterwards reverts the live file to committed (placeholder) state — without that revert, the maintainer's real refs would still be in the live file when Claude Code inspects it during the test, breaking fresh-teammate fidelity. The backup-restore mechanic preserves both the test's needs (test runs against committed-state `.env.tpl`) and the maintainer's daily-use state (restored in Reset C).

```bash
# === Chunk A3: /tmp cleanup ===
rm -f /tmp/mcp-grafana.tar.gz
rm -rf /tmp/mcp-grafana
rm -f /tmp/darwin.arm64.grafana.tar.gz
rm -f /tmp/darwin.x64.grafana.tar.gz

echo "--- verify chunk A3 ---"
ls -la /tmp/ 2>/dev/null | grep -E "grafana|darwin" || echo "TMP_FULLY_CLEAN"
```

`/tmp` accumulates Grafana install artifacts across sessions under multiple naming patterns (`mcp-grafana.tar.gz`, `darwin.arm64.grafana.tar.gz`, sometimes a `mcp-grafana` directory from extraction). Stale artifacts cause confusion — `tar` overwrites existing extractions silently, making it ambiguous which binary ended up at the destination. Each `rm` is a separate command rather than combined: zsh's default behavior fails the entire command line on a missing-glob match, so chained globs can halt before processing literal paths.

```bash
# === Chunk A4: ~/.zshrc handling — move-aside via awk block-skip ===
cp ~/.zshrc ~/.zshrc.maintainer-backup
awk '
/^function payrails-claude/,/^}/ { next }
/^payrails-claude\(\)/,/^}/ { next }
{ print }
' ~/.zshrc.maintainer-backup > ~/.zshrc.tmp
mv ~/.zshrc.tmp ~/.zshrc

echo "--- verify chunk A4 ---"
zsh -i -c 'type payrails-claude' 2>&1 | head -3
zsh -i -c 'echo zshrc-loaded-without-errors' 2>&1 | tail -3
ls -la ~/.zshrc ~/.zshrc.maintainer-backup
wc -l ~/.zshrc ~/.zshrc.maintainer-backup
```

Expected verification output:
- `payrails-claude not found` (function gone — good).
- `zshrc-loaded-without-errors` printed cleanly with no parse errors above it (good).
- `~/.zshrc` line count smaller than `.maintainer-backup` (function block removed).

The verification uses `zsh -i -c` (interactive) not `zsh -c`. Non-interactive shells don't source `~/.zshrc`, so `zsh -c 'type payrails-claude'` returns "not found" regardless of whether the function is defined. Use the `-i` flag for an actual test of whether the function is loaded in a real shell.

**Why awk block-skip and not `grep -v`**: an earlier version of this chunk used `grep -v "payrails-claude" | grep -v "payrails-debug"` to filter the function out of `~/.zshrc`. That approach filters by line — the opening line of `payrails-claude` (which contains the function name) gets removed, but body lines that don't reference plugin-specific strings (e.g., `cd "${1:-...}"`, `op inject -i .env.tpl -o .env`, the closing `}` brace) survive into the filtered output. The result is a malformed `~/.zshrc` with an orphan closing brace and no matching opener, which produces a `parse error near '}'` when sourced. Empirically observed during a real maintainer test (v0.1.8 fix). The awk block-skip drops everything from the function header to the matching `}` regardless of body content, handling both `function payrails-claude { ... }` and `payrails-claude() { ... }` definition styles.

**Why move-aside instead of in-place comment markers**: an even earlier approach commented out the function block in place using marker prefixes (e.g., `# PHASE4_RERUN_COMMENTED_OUT: ...`). When Claude Code subsequently inspected `~/.zshrc`, it found the marker-commented function and interpreted it as a "partial setup that needs fixing" — attempting to overwrite the entire commented block with a new active function. Move-aside (writing a clean file without the function entirely, keeping the original at `.maintainer-backup`) is unambiguous: there's nothing for Claude Code to "fix."

```bash
# === Chunk A5: GitHub access + Antigravity quit (browser/dock, not terminal) ===
# 5a: From maintainer's edwin-payrails browser session:
#     https://github.com/edwin-payrails/payrails-debug-plugin/settings/access
#     Remove the teammate-identity collaborator if present, then re-add as Read-only collaborator.
# 5b: From teammate-identity browser session: accept the invite.
# 5c: Cmd+Q Antigravity (right-click dock icon → Quit, verify icon disappears).
```

**Expected end state after Reset A**:
- Plugin uninstalled, all five locations clean
- Maintainer `.env` and `.env.tpl` backed up; live `.env.tpl` reverted to committed (placeholder) state via `git checkout`
- `~/tools/`: `mcp-grafana-bin` (Syed's fork compiled, untouched), `mcp-grafana/` (Syed's fork source, untouched), `mcp-grafana-official.bak`, no plain `mcp-grafana-official`
- `/tmp/`: no `mcp-grafana*` or `darwin*` files
- `~/.zshrc`: no `payrails-claude` function active; `zsh -i -c 'echo ok'` loads cleanly; backup at `~/.zshrc.maintainer-backup`
- Teammate-identity `gh` account has fresh accepted repo invite
- Antigravity not running

#### Reset B — Post-test (clean test artifacts)

**When to run**: After each test phase wraps, regardless of success or failure.

```bash
# === Chunk B1: plugin uninstall + filesystem + registration (same as A1) ===
claude plugin uninstall payrails-debug@payrails-debug-plugin
rm -rf ~/.claude/plugins/cache/payrails-debug-plugin/
rm -rf ~/.claude/plugins/marketplaces/payrails-debug-plugin/
claude plugin marketplace remove payrails-debug-plugin
```

```bash
# === Chunk B2: clean test clone folders, /tmp, Grafana binary ===
rm -rf ~/code/payrails-debug-plugin                   # Path B's typical autonomous-install clone folder
rm -rf ~/Documents/phase4_plugin_test/                # if a specific test folder was created
rm -rf /tmp/mcp-grafana
rm -f /tmp/mcp-grafana.tar.gz
rm -f /tmp/darwin.arm64.grafana.tar.gz
rm -f /tmp/darwin.x64.grafana.tar.gz
mv ~/tools/mcp-grafana-official ~/tools/mcp-grafana-official.bak.tmp 2>/dev/null
```

```bash
# === Chunk B3: project-scoped memory file cleanup ===
find ~/.claude/projects -name "user_role.md" -o -name "project_payrails*.md" -o -name "MEMORY.md" 2>/dev/null
# Review output. Memory files with timestamps from the test run are candidates for removal.
# Memory files with older timestamps are pre-existing real usage — leave alone.
# Likely path for a $HOME-launched test: ~/.claude/projects/-Users-<username>/memory/
# DON'T blanket-delete ~/.claude/projects/ — it contains real-usage memory for unrelated work.
```

```bash
# === Chunk B4: Antigravity Cmd+Q ===
# Right-click dock icon → Quit, verify dock icon disappears.
```

After Reset B, run Reset C to restore maintainer state.

#### Reset C — Maintainer state restore (after any test phase, before resuming daily use)

**When to run**: After a test phase ends, before resuming daily debugging work.

```bash
# === Chunk C1: restore maintainer .env, .env.tpl, Grafana binary ===
mv ~/Documents/Payrails/payrails-debug-plugin/.env.maintainer-backup ~/Documents/Payrails/payrails-debug-plugin/.env 2>/dev/null
cp ~/Documents/Payrails/payrails-debug-plugin/.env.tpl.maintainer-backup ~/Documents/Payrails/payrails-debug-plugin/.env.tpl
rm -f ~/Documents/Payrails/payrails-debug-plugin/.env.tpl.maintainer-backup
mv ~/tools/mcp-grafana-official.bak ~/tools/mcp-grafana-official 2>/dev/null
rm -f ~/tools/mcp-grafana-official.bak.tmp* 2>/dev/null

echo "--- verify chunk C1 ---"
ls -la ~/Documents/Payrails/payrails-debug-plugin/.env* 2>/dev/null
ls -la ~/tools/ | grep -i grafana
~/tools/mcp-grafana-official --version 2>&1 | head -3
```

The `.env.tpl` is restored from backup (not via `git checkout`) so the maintainer's daily-use real `op://` references come back. `git checkout` would revert to committed (placeholder) state and break the next `payrails-claude` invocation.

```bash
# === Chunk C2: restore ~/.zshrc from backup ===
cp ~/.zshrc.maintainer-backup ~/.zshrc
rm -f ~/.zshrc.maintainer-backup

echo "--- verify chunk C2 ---"
zsh -i -c 'type payrails-claude' 2>&1 | head -3
zsh -i -c 'echo zshrc-loaded-without-errors' 2>&1 | tail -3
wc -l ~/.zshrc
```

Restoring from backup is cleaner than reversing in-place edits — the saved file is byte-identical to the original, no chance of leftover markers or partial reverses. The second verification line catches the case where `~/.zshrc` got broken during the test (e.g., a write to the file that didn't go cleanly) — if it shows a parse error, restore from `~/.zshrc.maintainer-backup` again, or fix manually.

```bash
# === Chunk C3: handle stale .env after credential rotation ===
# If any credential was rotated during the test (per Path A's heredoc-write hazard or any other reason),
# the restored .env is now stale. Best to delete it and let payrails-claude regenerate via op inject.
# rm -f ~/Documents/Payrails/payrails-debug-plugin/.env
# Then on next payrails-claude invocation, op inject will write a fresh .env from current 1Password values.
```

```bash
# === Chunk C4: re-install plugin for daily use (optional) ===
# If maintainer wants the plugin live for daily debugging:
# Local-path install (recommended per maintainer rule — see "Plugin install paths" in main doc):
#   claude plugin marketplace add ~/Documents/Payrails/payrails-debug-plugin
#   claude plugin install payrails-debug@payrails-debug-plugin
# OR via Antigravity UI: /manage-plugins → Marketplaces → Add → enter directory path → Add → toggle on.
```

**Expected end state after Reset C**:
- Maintainer's working `.env`, `.env.tpl` (with real `op://` refs), Grafana binary, and `~/.zshrc` (with `payrails-claude` function active) all restored.
- `zsh -i -c 'echo ok'` loads cleanly (no parse errors).
- Plugin re-installable for daily use; the local-path install is the recommended approach.

### Critical reset rules

- **Always run Reset C after Reset B.** Reset B leaves the maintainer in a partially-cleaned state; only Reset C makes the maintainer's setup whole.
- **Run all uninstall commands regardless of which locations appear clean.** Idempotent commands are safer than conditional ones.
- **Don't combine literal paths and globs in `rm` (zsh).** Default zsh behavior fails the entire command on a missing-glob match. Use separate `rm` invocations.
- **Don't `rm -rf ~/.claude/projects/`.** That contains real-usage memory files for unrelated work. Always identify the specific test-folder slug to delete.
- **Use awk block-skip for `~/.zshrc` move-aside in Reset A (Chunk A4).** A line-based `grep -v` filter or in-place comment markers both produce malformed shell config — see the "Why awk block-skip" note in Chunk A4.
- **Use `zsh -i -c 'type ...'`, not `zsh -c 'type ...'`** for shell-function verification. Non-interactive shells don't source `~/.zshrc`.
- **Run the pre-test sanity check before Reset A.** A `~/.zshrc` that already has parse errors will produce an even worse result after move-aside.

### Bootstrap-prompt redaction list (test-only)

When prompting Claude Code to drive an install autonomously, include an explicit list of files whose contents must not be printed back to the test driver. The minimum list:

- `.env` (any file matching `.env.*` other than `.env.tpl`)
- `~/.claude/settings.json`
- 1Password CLI output
- `~/.zshrc`

The first three are obvious; the fourth is the one that's easy to miss. During an install, Claude Code naturally runs `tail ~/.zshrc` or `cat ~/.zshrc` to verify whether the optional shell function is already present. If the user has plaintext credentials exported in `.zshrc` (e.g., `export ANTHROPIC_API_KEY=...`), those values appear in stdout and risk being captured in screenshots or transcripts. Add `~/.zshrc` to the redaction list to prevent this — instruct Claude Code to use existence-only checks (e.g., `grep -n "payrails-claude" ~/.zshrc` rather than `tail ~/.zshrc`).

In addition to the redaction list, include this guidance:

> Don't switch gh accounts during the install. Use whichever account is currently active — it already has the access needed.

This prevents Claude Code from acting on the multi-account state that some maintainer machines have and that real teammates wouldn't have.

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
