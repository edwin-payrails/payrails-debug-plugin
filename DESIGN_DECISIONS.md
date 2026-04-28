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

---

## Credential handling: `op inject` outside the agent (not plaintext, not direct `op` calls)

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

---

## No podman containerization for v1

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

## Documentation philosophy

**Decision**: 
- README is human-reader-facing only — no AI-specific instructions.
- Setup steps live in README.
- Rationale and internals live in DESIGN_DECISIONS.md (this file) and PLUGIN_LIFECYCLE.md.
- Conditional prerequisites state the fallback in human language ("if missing, skip and continue").

**Why no AI-specific instructions in README**:
- A well-written human-readable doc is also readable by Claude Code or any agent. That's a side-effect benefit, not the design goal.
- "If you are an AI, do X" instructions would be brittle (what if the AI doesn't recognize itself as one?) and create a hostile reading experience for humans.
- Conditional fallback wording works for both audiences without singling out either.

**Why split into multiple docs**:
- README is for setup and operational use. A teammate hitting "how do I install this?" or "Grafana shows Failed, what do I check?" should find the answer in README without wading through architectural rationale.
- DESIGN_DECISIONS.md is for the rare moment someone asks "why was this chosen?" before changing it.
- PLUGIN_LIFECYCLE.md is for understanding internal mechanics when something behaves unexpectedly.

**When to revisit**:
- If documentation grows so much that further splits are warranted.
- If a contributor reports being unable to find information in the expected place.

---

## Updating this doc

If you discover a new design decision or learn something that changes the rationale for an existing one, add it here. Keep the format consistent (Decision → Alternatives → Why → When to revisit).

If a decision is overturned (e.g., we DO eventually containerize the Grafana MCP), don't delete the original entry — add a new entry below documenting the change and why, and reference the original. Preserves the historical reasoning.

For decisions about active-development internals (debugging workflow shape, MCP loading order, cache propagation mechanics), see `PLUGIN_LIFECYCLE.md` instead.

For workflow questions (how to contribute, branch naming, PR conventions), see `CONTRIBUTING.md`.
