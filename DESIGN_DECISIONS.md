# Design Decisions

This document captures the *why* behind major architectural and process choices for the Payrails Debug Plugin. The audience is contributors, maintainers, and any future Claude session helping with the plugin.

If you're trying to *use* the plugin, see `README.md`. If you want to understand *how the plugin works under the hood*, see `PLUGIN_LIFECYCLE.md`. This file answers "why was it built this way?"

Each decision below documents:
- The choice we made
- The alternatives considered
- Why we chose what we chose
- What would trigger revisiting

---

## Plugin scope: user-scope, not project-scope

**Decision**: The plugin installs at user scope, meaning it loads in any Claude Code session regardless of folder.

**Alternatives considered**:
- Project scope tied to a specific folder, requiring per-project install

**Why user scope**:
- A Solutions Engineer may use this plugin from multiple folders during their work, not tied to any one location.
- Project scope would require a separate install per folder. With user scope, one install applies everywhere.
- Updates also flow through one path: bumping the plugin once propagates to every place it's used. Project-scoped installs would require updating each folder separately.

**When to revisit**:
- If a future skill genuinely depends on being in a specific folder context (e.g., needs to read codebase structure of a particular repo), we'd reconsider whether parts of the plugin should be project-scoped.
- For now, no skill has that dependency.

**Note on observed nuance**: Project-scope installs have been observed on the maintainer's machine when the plugin is installed via local-directory marketplace, even though GitHub-marketplace installs typically register as user-scope. Whether this is a pattern from one Antigravity version or a stable behavior is unclear. Both scopes work for daily use; the distinction matters for tests where the simulation should match teammate experience.

---

## Credential handling: `op inject` outside the agent (not plaintext, not direct `op` calls)

> **⚠️ Superseded for Grafana (2026-06-18)** — Grafana moved to the `gcx` CLI (browser OAuth), which retires op-inject / `.env.tpl` / 1Password for Grafana. See "Grafana access: gcx CLI" below. Grafana was the only consumer, so this apparatus is **currently inactive** — but the decision and mechanics below are deliberately **kept as the reference design for any *future* MCP that needs injected credentials**. If such an MCP is ever added, reinstate a `.env.tpl` with `op://` placeholders and follow this decision plus the op-inject mechanics still documented in `PLUGIN_LIFECYCLE.md`.

**Decision**: Credentials live in 1Password. The user runs `op inject` outside the agent context (in their own shell) to produce a `.env` file with resolved values, then `source` it before launching Antigravity. Path A (manual `.env`) exists as a simpler alternative.

**Alternatives considered**:
- Plaintext `.env` committed alongside placeholders (fast to set up, terrible security)
- Agent calls `op` directly during plugin runtime (would let the LLM access secrets dynamically)
- A custom credential broker service that the plugin queries
- Environment variables exported in `~/.zshrc`

**Why op-inject outside the agent**:
- Plaintext on disk discouraged by Daniel König's security rulings.
- Direct `op` calls from the agent are explicitly forbidden under PS-368 (Syed Hasan's remediation).
- `op inject` invoked by the user (outside the agent) was sanctioned by Bishoy Atif in the April 6 Q&A and confirmed in Claude Enterprise findings.
- Once `.env` is sourced and Antigravity inherits the env vars, the agent never sees the credentials directly — the MCP subprocess does.
- Plaintext `~/.zshrc` exports work but spread credentials across shell config files; `.env` keeps them in one place that's gitignored.

**When to revisit**:
- If Payrails security policy changes to allow agent-mediated credential access.
- If Grafana migrates to Grafana Cloud and gets a hosted MCP that handles its own auth — that would eliminate the credential-injection step entirely for the Grafana MCP.
- If a different secrets manager replaces 1Password company-wide.

**Notes for contributors**:
- Path A (manual `.env`) is documented as a simpler alternative for testing or quick setup. It's not the default; it's the lighter-weight option.
- The `.env.tpl` file in the repo uses placeholder `op://` references that each teammate edits to point at their own 1Password vault item. Don't commit `.env` (it's gitignored).
- Path A has its own security concern in autonomous-install scenarios — see `PLUGIN_LIFECYCLE.md`'s "Path A: heredoc-write hazard" section. Path B avoids this entirely.

---

## Grafana access: `gcx` CLI (supersedes op-inject + local-binary, 2026-06-18)

> **⚠️ Superseded 2026-06-25** — Quang approved the hosted Grafana Cloud MCP, so Grafana now uses the **Grafana MCP** (`https://mcp.grafana.com/mcp`, browser OAuth), not the gcx CLI. This entry is kept as the rationale *and* the documented **fallback** (gcx needs no MCP-usage budget and avoids the agent-discovery confusion if ever reconsidered). The gcx↔MCP comparison is in `BUILD_HANDOFF.md`; the gcx `grafana.md` is preserved (`grafana.md.gcx-backup`, gitignored, + git history).

**Decision**: Grafana is accessed via Grafana's official **`gcx` CLI**, run from the shell by the debugging skill and authenticated with `gcx login` (browser OAuth). This **supersedes** both the "Credential handling: op inject" and "No podman containerization" decisions above, for Grafana.

**Context**: Payrails retired self-hosted Grafana (`grafana.telemetry.payrails.io`) and moved to Grafana Cloud (`payrails.grafana.net`), which disables password/basic auth — so the old `mcp-grafana` binary + op-inject'd username/password no longer works. (This is the exact "When to revisit" trigger the op-inject decision anticipated.)

**Alternatives considered**:
- **Hosted Grafana Cloud MCP** (`mcp.grafana.com`, OAuth) — the cleanest "no binary" option, but (a) gated behind an admin-granted Assistant *MCP* role, and (b) per platform lead Quang Ngo it bills against Grafana Cloud AI usage that isn't budgeted. Deferred; its config is recorded in `CONNECTORS.md` for when it's budgeted (removed from `.mcp.json` because a present-but-unauthenticated MCP confused the agent into reaching for it).
- **mcp-grafana binary against Cloud + service-account token** — still a binary, still needs an admin-minted token; rejected in favor of the platform team's recommended path (gcx).
- **The gcx *plugin*** (a separate Claude plugin) — rejected: a whole second plugin install, blocked by the same role gate; we only need the gcx *CLI*, driven by our own skill.

**Why gcx CLI**:
- No credentials on disk, no 1Password, no `.env`/op-inject, no env-var launch ritual — `gcx login` stores an OAuth session in `~/.config/gcx/config.yaml`. This **retires the entire credential-injection apparatus** (op-inject, `.env.tpl`, and finding #14's revert/restore commit cycle).
- It's the platform team's recommended path for AI/Grafana usage.
- Same tool surface as the old MCP (logs/metrics/dashboards) plus more (traces, alerts, incidents) — validated against five real debugging cases + a zero-hint fresh-session test.

**Trade-off accepted**: gcx is still a downloaded binary (Homebrew) and is CLI-driven rather than an MCP, so the skill (`references/grafana.md`) must teach the gcx command patterns instead of relying on an MCP's auto-exposed tools. Mitigated by an explicit "try documented patterns first, discover via `gcx --help`, adapt when they don't fit" operating principle in that file.

**Auth dependency**: `gcx login` requires the Grafana "Assistant CLI User" role (admin-granted; not self-service).

**When to revisit**:
- If/when the hosted Grafana Cloud MCP is budgeted *and* the Assistant MCP role is granted team-wide, we could switch to the no-binary hosted MCP (the dormant `.mcp.json` block is ready). That would change only the skill's *mechanics* back to MCP tool calls — the Payrails domain knowledge in `grafana.md` stays.

---

## No podman containerization for v1

> **⚠️ Superseded (2026-06-18)** — the `mcp-grafana` local binary is no longer used; Grafana is accessed via the `gcx` CLI. See "Grafana access: gcx CLI" above. Kept as historical record.

**Decision**: The Grafana MCP runs as a local binary on the user's machine (`~/tools/mcp-grafana-official`), not inside a container.

**Alternatives considered**:
- Containerizing the Grafana MCP via Podman (matches some other internal Payrails tools)
- Pre-built Docker image distributed via internal registry

**Why local binary for v1**:
- Daniel König's security ruling targets agent-1Password access patterns specifically, not all MCP communication paths.
- Containerization adds significant friction to setup (install Podman, manage container lifecycle, configure volume mounts for credentials).
- For a v1 plugin used by a small team where the security concern (credential exposure) is already addressed by op-inject, the container layer doesn't add proportional value.
- The pre-merge security heads-up to Daniel and Syed will catch any objection if our reading is wrong.

**When to revisit**:
- If security review post-v1 explicitly requires it.
- If the binary becomes a maintenance burden across architectures (currently we ship Apple Silicon and Intel; if Linux teammates show up, container becomes more attractive).

---

## Microsoft's `@playwright/mcp` for the Playwright MCP

**Decision**: Use Microsoft's `@playwright/mcp@latest` package for browser automation.

**Alternatives considered**:
- Other Playwright MCP packages on npm with similar names but different maintainers and release cadences.

**Why Microsoft's package**:
- It's the canonical, vendor-maintained Playwright MCP. Microsoft owns Playwright; their package is the source of truth.
- More actively maintained than alternative packages.
- Better track record on bug fixes and Playwright API alignment.
- Documented in Microsoft's official Playwright MCP docs.

**When to revisit**:
- If Microsoft stops maintaining their package (unlikely).
- If a Payrails-specific browser-automation pattern emerges that Microsoft's MCP doesn't support.

**Notes for contributors**:
- The package is invoked via `npx @playwright/mcp@latest` in `.mcp.json`. The `@latest` tag means each launch fetches the current version. If you want to pin a version for stability, use `@x.y.z` instead. Currently we use `@latest` and accept the small risk of breaking changes for the freshness benefit.

---

## Snowflake access: `mcp-remote` wrapper, not the native OAuth connector

**Decision**: The Snowflake MCP (`DWH.REPORTING.PAYRAILS_SCOPE_MCP`) is wrapped in **`mcp-remote`** (a local stdio proxy) in `.mcp.json`, not declared as a native `type: http` server with an `oauth` block. It authenticates against a **dedicated Snowflake OAuth integration** the Data team created for this (registered for `mcp-remote`'s default callback port `3334` and `/oauth/callback` path), scoped to `session:role:ANALYST`.

**Alternatives considered**:
- **Native `type: http` + `oauth` block** — the form Snowflake's setup guide documents for Claude Code; what we first shipped.
- **Claude Desktop's built-in Snowflake connector** — admin-gated and carries a known limitation; ruled out (no admin available).
- **Asking the Data team to regenerate a `+`-free client id** so the native connector would work — unnecessary once `mcp-remote` solved it, and it wouldn't have fixed Cowork.
- **PAT / bearer-token auth** (Snowflake's other connectivity path) — viable but needs per-user PATs plus a network policy; heavier for non-technical teammates than browser OAuth.

**Why `mcp-remote`**:
- **It fixes a client bug.** The Snowflake OAuth client id contains a `+`. Older Claude Code clients (e.g. the Antigravity extension on 2.1.123) put that `+` into the authorize URL *un-percent-encoded*, so Snowflake reads it as a space → "OAuth client integration with the given client id is not found." Verified directly against Snowflake's authorize endpoint. `mcp-remote` runs its own OAuth and percent-encodes correctly (`%2B`), so it works regardless of the host client's version. (A fixed terminal CLI — 2.1.167 — also works natively, but we can't assume every teammate's client is fixed.)
- **It works in Cowork.** Cowork's native connector surface is admin-gated with no general OAuth connector, but it *does* spawn a local `command:` stdio server from `claude_desktop_config.json` — the same path the plugin's Plain MCP already uses there. `mcp-remote` is a local stdio server, so the same path carries Snowflake. The native `type: http`+`oauth` form does **not** work in Cowork.
- **One config across surfaces** — terminal, Antigravity, the desktop Code tab, and Cowork all use the same block.

**Trade-offs accepted**:
- An extra `npx`/node process per session (already true for Plain).
- The callback port must be free at auth time; if `3334` is occupied, `mcp-remote` silently picks a random port and the redirect no longer matches the registered URI, so auth fails. Don't run two clients through the auth flow at once.
- The client id is committed in `.mcp.json`. It's a **public** OAuth client identifier (PKCE, no secret), shared openly by the Data team, so this is acceptable — no op-inject needed (contrast "Credential handling" above).

**When to revisit**:
- If/when all teammate clients are on a Claude Code version that percent-encodes the client id correctly *and* a non-admin-gated OAuth path exists in every surface (incl. Cowork), the native `type: http`+`oauth` block would be simpler.
- If the Data team rotates to a `+`/`/`-free client id, the native form becomes viable for fixed clients — but `mcp-remote` is still needed for Cowork, so there's little reason to switch.

**Notes for contributors**:
- The dedicated OAuth integration is **separate** from the one in Snowflake's setup guide (which uses port `3118` + `/callback` for the native flow). Don't conflate the two client ids / ports.
- Cowork users need the same `snowflake` block in their `claude_desktop_config.json` — the plugin's `.mcp.json` isn't read by Cowork's connector surface the same way. See the Snowflake MCP Access Notion guide.
- The skill guidance lives in two places **by design** — the standalone `cortex-snowflake` skill (triggers on its own for ad-hoc data questions) and `skills/payrails-debug/references/snowflake.md` (read during debugging). The overlap is intentional; both point at the same MCP and rules.

---

## Plugin distribution: GitHub-hosted in `payrails-hub` (eventually)

**Decision**: The plugin will ship in a GitHub repo named `payrails-hub` once security review approves it. Currently it lives in `edwin-payrails/payrails-debug-plugin` (a Payrails-affiliated personal namespace) as a stand-in.

**Alternatives considered**:
- Ship in the Payrails backend repo (`payrails/backend`)
- Ship in a public repo
- Don't host externally; bundle via internal artifact server

**Why `payrails-hub` (eventually)**:
- `payrails-hub` was created (Linear AI-16) specifically as a central repository for Claude skills used across the organization.
- Akshay Sharma suggested `payrails-hub` as the appropriate location for plugins.
- Syed Hasan's PS-368 remediation reinforced that tooling should not live in the backend repo.

**Why not `payrails/backend`**:
- The backend repo is the Payrails product codebase, reviewed and owned by many teams. SE-team debugging tooling does not belong in product code.
- Putting tooling in backend would put every SE tooling change through backend code review and would set a pattern where any team's internal tooling ends up in the backend repo.

**Why `edwin-payrails/payrails-debug-plugin` for now (instead of going straight to `payrails-hub`)**:
- Publishing to `payrails-hub` requires a pre-merge security review (König and Syed) and approval to land internal tooling at the org level.
- Until that approval lands, hosting in a Payrails-affiliated personal namespace lets development progress without blocking on the security review timeline.
- Access stays controlled — the repo is private, with collaborator access granted individually as needed.
- After approval, migration to `payrails-hub` is straightforward (move the repo, update README references, notify teammates of the new install URL).

**Why not public**:
- The plugin contains Payrails-internal knowledge (merchant names in reference files, internal workflows). A sanitized public version could be considered separately someday.

**When to revisit**:
- After security review, when migration to `payrails-hub` is approved, this becomes the actual home (no longer "eventually").
- If Payrails decides to publish a public-facing version, we'd extract a sanitized subset.

---

## Edu's `payrails-debug` skill: adapted, not rewritten from scratch

**Decision**: The original `payrails-debug` skill (authored by Eduardo Janicas) was migrated into the plugin with surgical edits, preserving the core workflow, tone, and structure.

**Why adapt rather than rewrite**:
- Edu's design was already correct in structure and content. The only mismatches were location-bound (filesystem paths) and tool-bound (MCP references).
- Preserving the original means Edu remains an effective owner if he wants to evolve it; rewriting would break that continuity.
- Pure modification would have been incomplete — restructuring path references and removing tool dependencies isn't surface-level.

**When to revisit**:
- If the debugging workflow itself changes (e.g., a meaningfully new investigation step gets added that doesn't fit the existing UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE flow).
- If Edu wants to reclaim ownership and reshape the skill significantly.
- If patterns from real debugging sessions reveal a fundamentally different workflow shape.

**Notes for contributors**:
- Edu should get a courtesy heads-up before any major changes to this skill.
- New learnings from real debugging sessions get captured via the `payrails-knowledge-update` skill, which writes to the reference files (not the SKILL.md itself).

---

## No Payrails MCP in v1 (may be added later)

**Decision**: The plugin does not include the Payrails MCP server (which lives in the backend repo at `cmd/payrails_mcp` and requires Go and Podman to run).

**Why exclude for v1**:
- The Payrails MCP's three debugging-relevant tools — `oas_find_operations`, `oas_get_operation`, `auth_get_token` — are all replaceable through other paths:
  - **OAS lookups**: Read/Grep on `doc/oas/src/` in the cloned backend repo. Files are organized by service, well-structured, fast to grep. Same source data the MCP serves, just accessed directly.
  - **Auth tokens**: direct curl using the documented auth pattern in `payrails-knowledge.md`. Cleaner than the MCP wrapper for staging/prod targets.
- Removing the MCP eliminates Go and Podman from prerequisites — both required only to run it.
- Keeping the MCP could have added meaningful setup friction with little to no debugging capability gain as noticed so far.

**When to revisit**:
- If a new Payrails MCP tool emerges that has no Read/Grep/curl equivalent.
- If the OAS source files move or change format such that direct grep becomes less reliable.
- If a teammate workflow relies on the MCP's wrapper conventions in a way that direct calls don't support.

**Notes for contributors**:
- Users still clone the backend repo (code is needed for reading service implementations and connector logic). They just don't compile or run anything from it.
- If you find yourself wanting Payrails MCP functionality during debugging, check `payrails-knowledge.md` and the OAS files first. The replacement paths are intentional, not accidental.

---

## v1 maintainer model and the cache-vs-canonical behavior

**Decision**: For v1, the plugin's source-of-truth lives in the GitHub repo. When teammates use the plugin, what they have on their machine is a versioned cache (`~/.claude/plugins/cache/...`), not the canonical source. Edits made via skills like `payrails-knowledge-update` write to that cache, not back to GitHub.

**What this means for changes**:
- If a teammate runs `payrails-knowledge-update` during debugging and captures a new finding, that update is saved to their local plugin cache. It improves their debugging session, but it does not propagate to GitHub or to other teammates' caches.
- For a finding to flow back to all teammates, someone with repo access has to promote it: copy the cache edit into the canonical clone, commit, and push. From there, when other teammates next refresh their plugin cache, they pick up the change.
- Reaching the canonical clone and pushing requires GitHub access to the plugin repo. That access is currently granted on a per-person basis (since the repo is in `edwin-payrails/payrails-debug-plugin` for now). Once the plugin moves to `payrails-hub`, access becomes automatic for Payrails GitHub org members.

**Why this model for v1**:
- Setting up a robust contribution-flow system before the plugin is widely used would be premature.
- For v1, an informal flow (teammates report findings via Slack/Linear, the maintainer applies them as PRs) is faster to operate and easier to evolve.
- Once the plugin stabilizes and moves to `payrails-hub`, a more formal contribution flow can be established (see `CONTRIBUTING.md`).

**When to revisit**:
- Once the plugin moves to `payrails-hub` and is more widely available.
- When `CONTRIBUTING.md` formalizes the contribution flow.
- When usage volume makes the informal flow burdensome.

**Note on local-path install nuance**: When the maintainer installs the plugin via a local-directory marketplace (pointing at the canonical clone), the runtime appears to reflect canonical edits without an explicit refresh, even though `installPath` shows a cache directory. This means knowledge-update skill writes are visible to running skills and `git diff` will show them in the canonical clone — making them commit-ready directly. The exact mechanism (transparent cache-from-source-on-load, symlinks, or runtime-aware loading) is opaque, but the empirical behavior makes the local-path-install-for-maintainer recommendation work as intended.

---

## Two install paths in the README (CLI primary, UI alternative)

**Decision**: README documents two install paths. CLI install is recommended primary; Antigravity UI install is alternative.

**Alternatives considered**:
- CLI-only (don't document the UI path)
- UI-only (the original approach in early versions)

**Why both, with CLI primary**:
- Antigravity-embedded Claude Code lacks `/plugin install` slash commands (confirmed). Standalone Claude Code CLI users need terminal commands documented.
- Phase 2 testing surfaced that Antigravity's UI marketplace-add doesn't always trigger the install (the plugin doesn't appear in the Plugins tab). The CLI install command is more reliable.
- CLI is testable autonomously — Claude Code can drive it via its bash tool. UI requires manual clicks. For agent-driven setup, CLI wins.
- UI is still documented because some users prefer clicking.
- Updates are also CLI-primary: the UI Plugins-tab toggle-off-on flow has been observed to be unreliable in some Antigravity versions (toggle completes but doesn't pull the new version). `claude plugin update` from the terminal is the working mechanism.

**When to revisit**:
- If Antigravity adds reliable UI install across all versions, UI could move back to primary.
- If standalone Claude Code CLI deprecates the `claude plugin install` command (unlikely).

---

## Cache-staleness as acceptable behavior

**Decision**: When the maintainer pushes a new version, teammates' local installs do not automatically update. They have to refresh the marketplace cache and update the plugin explicitly to pick up the change. We accept this rather than building auto-update mechanisms.

**Alternatives considered**:
- Auto-update on every Claude Code session start (fetches newest from GitHub each time)
- A push-based notification system that prompts teammates when a new version exists

**Why version-pinned caches**:
- Performance: skipping a network fetch per session start matters when sessions start often.
- Offline support: teammates can work without network if their cache is current.
- Reproducibility: a teammate can pin to v0.1.4 and know exactly what they're running, even if v0.1.5 is out — useful when investigating issues that might depend on plugin behavior.

**The cost we accept**: teammates who don't actively refresh their cache stay on old behavior until they do. We mitigate this with version-bump discipline (so version-aware refresh logic correctly detects "newer version available").

**When to revisit**:
- If a critical security issue requires forcing all teammates to update fast (current model wouldn't handle that gracefully).
- If the plugin grows in scale where stale-cache confusion outweighs the performance benefits.

---

## `<plugin-dir>` placeholder over hardcoded paths in the README

**Decision**: When the README needs to reference the plugin directory (for example, in the `payrails-claude` shell function template, or in steps that involve `cd` into the clone), it uses the placeholder `<plugin-dir>` rather than a hardcoded path like `~/Documents/Payrails/payrails-debug-plugin`.

**Alternatives considered**:
- Hardcode `~/Documents/Payrails/payrails-debug-plugin` (matches the maintainer's setup)
- Use a different placeholder convention like `$PLUGIN_DIR` or `/path/to/plugin-dir`
- Have multiple READMEs for different organization styles

**Why `<plugin-dir>`**:
- Different teammates organize their code differently. Some keep all repos under `~/code`, others under `~/Documents/Work`, others under `~/<project>`. Hardcoding one path breaks the README for everyone whose conventions differ.
- Angle-bracket placeholders are a universal documentation convention — readers (human or agent) immediately recognize them as "fill this in with your value" rather than literal text.
- A single placeholder is simpler than maintaining branching docs for different organization styles.
- Verified to work for both human readers and Claude Code in autonomous-install scenarios. Claude Code substitutes the placeholder with whatever path it picks for its clone, without leaking the maintainer's path expectations into its install.

**Why not just `~/code/payrails-debug-plugin` (a popular convention)**:
- Same hardcoding problem on a smaller scale. Some teammates don't use `~/code`. Whichever default we pick, someone's convention breaks.
- The placeholder approach makes "fill this in" explicit rather than burying it in a default that might or might not match.

**When to revisit**:
- If a strong reason emerges to give a default value alongside the placeholder (some readers find pure placeholders ambiguous about whether *anything* goes there). Could move to `<plugin-dir, e.g. ~/code/payrails-debug-plugin>` style if needed.

**Notes for contributors**:
- Whenever you add a new README step that references the plugin directory, use `<plugin-dir>` not a literal path. This is a discipline carried forward from v0.1.6.
- The `payrails-claude` shell function template in the README uses `<plugin-dir>` and `<your-default-workspace>` as two distinct placeholders for two different things — keep them separate.

---

## Move-aside backups over in-place markers for test isolation

**Decision**: When test setup requires temporarily neutralizing a maintainer-machine artifact (such as the `payrails-claude` shell function in `~/.zshrc`), the approach is to back up the file and write a clean modified version, with restoration via `cp` from the backup. *Not* to use in-place comment markers that the test reverses by string match.

**Alternatives considered**:
- In-place comment markers: prefix the lines being neutralized with a recognizable string (e.g., `# PHASE4_RERUN_COMMENTED_OUT: ...`), so a later reset can `sed` to remove the prefix.
- Move-aside backups: copy the file to `<file>.maintainer-backup`, write a modified version, restore by copying back.

**Why move-aside (and not in-place markers)**:
- In-place markers were tried during Phase 4 testing and *backfired*. When Claude Code subsequently inspected `~/.zshrc` (per the README's setup instructions to check for the function's presence), it found the marker-commented function and interpreted it as a "partial setup that needs fixing" — attempting to overwrite the entire commented block with a new active function.
- Move-aside is unambiguous: the modified file simply doesn't contain the function. Nothing for Claude Code to "fix."
- Restoration from backup is one command (`cp`) and produces a byte-identical copy of the original. No risk of leftover markers, regex misses, or partial reverses.
- The in-place approach assumed the marker prefix would be self-evidently "do not touch" — but Claude Code doesn't natively recognize arbitrary prefix conventions and will treat unusual comment patterns as setup anomalies to repair.

**Why not in-place markers**:
- Even with cleverer marker text (e.g., `# DO_NOT_TOUCH_TEST_BACKUP:`), there's no guarantee Claude Code will respect the marker. It may still try to "improve" what looks like incomplete setup.
- The marker approach is brittle — it's an attempt to communicate intent through a side-channel that wasn't designed for that. Move-aside removes the entire ambiguity.

**When to revisit**:
- If a future scenario requires reverting an edit *while* preserving other edits the user made in between (move-aside loses any edits made to the file between Reset A and Reset C). That's not a current concern but could matter for longer-running test cycles.

**Notes for contributors**:
- This pattern applies to any maintainer-machine artifact that needs to be neutralized for a fresh-teammate test, not just `~/.zshrc`. Same logic for `.env`, `.env.tpl`, the Grafana binary, etc. All of those use move-aside backups in `PLUGIN_LIFECYCLE.md`'s Reset playbooks.
- The naming convention for backups: `<file>.maintainer-backup`. Distinguishes from `.bak` files left by `sed -i` and similar.

---

## Documentation philosophy

**Decision**: 
- README is human-reader-facing only — no AI-specific instructions.
- Setup steps live in README.
- Rationale and internals live in DESIGN_DECISIONS.md (this file) and PLUGIN_LIFECYCLE.md.
- Conditional prerequisites state the fallback in human language ("if missing, skip and continue").
- README stays minimal even after security findings or test-mechanic discoveries — those go to PLUGIN_LIFECYCLE.md, not README.

**Why no AI-specific instructions in README**:
- A well-written human-readable doc is also readable by Claude Code or any agent. That's a side-effect benefit, not the design goal.
- "If you are an AI, do X" instructions would be brittle (what if the AI doesn't recognize itself as one?) and create a hostile reading experience for humans.
- Conditional fallback wording works for both audiences without singling out either.

**Why split into multiple docs**:
- README is for setup and operational use. A teammate hitting "how do I install this?" or "Grafana shows Failed, what do I check?" should find the answer in README without wading through architectural rationale.
- DESIGN_DECISIONS.md is for the rare moment someone asks "why was this chosen?" before changing it.
- PLUGIN_LIFECYCLE.md is for understanding internal mechanics when something behaves unexpectedly, including test-time guidance for maintainers.

**Why README stays minimal even when new findings would seem to warrant adding to it**:
- Findings about test mechanics, security observations specific to install paths, or maintainer-only concerns belong in PLUGIN_LIFECYCLE.md or this file, not in the README.
- Adding such content to README dilutes its purpose (setup-and-use) and makes the user wade through internal concerns that don't apply to most use cases.
- Examples of findings that explicitly do NOT go to README: Path A's heredoc-write hazard (PLUGIN_LIFECYCLE.md instead), `~/.zshrc` shell function suppressing question-asking in tests (PLUGIN_LIFECYCLE.md), gh multi-account caveats during tests (PLUGIN_LIFECYCLE.md). README's reader is a teammate setting up the plugin for daily use, not a maintainer running test phases.

**When to revisit**:
- If documentation grows so much that further splits are warranted.
- If a contributor reports being unable to find information in the expected place.

---

## Updating this doc

If you discover a new design decision or learn something that changes the rationale for an existing one, add it here. Keep the format consistent (Decision → Alternatives → Why → When to revisit).

If a decision is overturned (e.g., we DO eventually containerize the Grafana MCP), don't delete the original entry — add a new entry below documenting the change and why, and reference the original. Preserves the historical reasoning.

For decisions about active-development internals (debugging workflow shape, MCP loading order, cache propagation mechanics), see `PLUGIN_LIFECYCLE.md` instead.

For workflow questions (how to contribute, branch naming, PR conventions), see `CONTRIBUTING.md`.