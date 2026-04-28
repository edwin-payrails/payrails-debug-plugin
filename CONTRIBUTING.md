# Contributing

This document covers how to contribute to the Payrails Debug Plugin — reporting issues, suggesting improvements, sharing debugging learnings, and (for those with repo access) updating the plugin directly.

The contribution model is intentionally informal for v1. As the plugin matures and migrates to `payrails-hub`, the flow will become more structured.

---

## Quick orientation

The plugin has three audiences with different contribution flows:

- **Users (most teammates)** — install the plugin and use it for debugging. Report what works and what doesn't.
- **Contributors (teammates with repo access)** — can submit changes directly via PR.
- **Maintainer** — owns the canonical repo, applies findings reported by users, merges PRs from contributors, releases new versions.

For the current state of the plugin (v1), most Payrails SEs are users. The maintainer is the primary developer. Contributors are added on a per-person basis as the plugin grows.

---

## If you found a debugging insight worth keeping

This is the most common contribution case. You're debugging a real merchant issue, the plugin helps you investigate, and you discover something useful — a new error pattern, a provider gotcha, a workflow shortcut. Two ways to capture it:

### Option 1 — Use the `payrails-knowledge-update` skill (in your debugging session)

Invoke the skill explicitly during or right after your debugging session. It captures the finding into the appropriate plugin reference file (`payrails-knowledge.md`, `temporal.md`, `providers/<name>.md`, etc.).

**Important caveat**: when the plugin is installed from GitHub, this skill writes to your local plugin cache, not back to the GitHub repo. The update improves your future debugging sessions, but it doesn't propagate to other teammates until someone with repo access promotes it to the canonical clone.

### Option 2 — Report it informally

Drop a note in Slack (`#ai` or `#payments-acceptance`) describing what you learned. The maintainer will fold it into the next plugin update. Examples of the kind of message that's useful:

- "When debugging X with provider Y, I noticed Z. Worth documenting."
- "The auth pattern in `payrails-knowledge.md` needs an update for staging API V2."
- "I found a recurring issue pattern; might be worth a runbook."

The maintainer will follow up if more detail is needed before applying.

---

## If you have direct repo access

If you have GitHub access to the plugin repo and want to make a change yourself:

### For documentation or skill-content changes

1. Clone or pull the repo locally.
2. Branch off `main`: `git checkout -b <prefix>/<short-description>` (use `fix/`, `feat/`, `docs/`, or `chore/` prefixes).
3. Make your change.
4. Bump the plugin version in `.claude-plugin/plugin.json` if your change affects plugin behavior (any code, skill, or MCP change). Pure-documentation changes can skip the bump while no teammates are using the plugin actively; once teammates have installed, bump on every change.
5. Open a PR with a clear description.
6. Once merged, teammates need to refresh their plugin to pick up the change — see the README's update section.

### For new MCPs or new skills

Open an issue or thread first to discuss the design. New skills affect plugin scope and other teammates' installs, so a quick alignment check before coding saves rework. Once aligned, follow the same branch + PR flow.

### Versioning

The plugin uses semver:
- Patch (0.1.X → 0.1.Y): bug fixes, README updates, troubleshooting additions.
- Minor (0.X.0 → 0.Y.0): new features (new MCPs, new skills).
- Major (X.0.0 → Y.0.0): breaking changes.

Currently the plugin is in pre-1.0 (0.1.X) territory.

---

## How learnings flow back from cache to canonical

This is the part that's not obvious. The plugin has two distinct copies of itself once installed:

1. **The canonical repo on GitHub** — the source of truth.
2. **The local plugin cache on each user's machine** — what their Claude Code actually loads at runtime.

When the `payrails-knowledge-update` skill writes a learning, it writes to the cache, not the canonical. That means:

- The user's session benefits immediately.
- Other teammates don't see the change.
- A version-bump-driven cache refresh on the user's machine will overwrite the local edit.

For the learning to actually propagate, the change needs to land in the canonical repo. The flow:

1. The user (or maintainer, if the user reported it via Slack) finds the cache-side change at `~/.claude/plugins/cache/payrails-debug-plugin/payrails-debug/<version>/skills/payrails-debug/references/<file>.md`.
2. Someone with repo access copies that change into the canonical clone (`~/Documents/Payrails/payrails-debug-plugin/skills/payrails-debug/references/<file>.md`).
3. They commit and push.
4. The next plugin update propagates the change to all teammates' caches.

For this reason, **active contributors who expect to make frequent changes should install the plugin via local-path** (pointing directly at their canonical clone) rather than from GitHub. That way, their `payrails-knowledge-update` writes go directly to the canonical, eliminating the cache-promotion step.

---

## What kinds of contributions are wanted

**Especially welcome**:
- Provider-specific gotchas (new files under `skills/payrails-debug/references/providers/`)
- New API endpoint patterns or auth quirks
- Recurring error patterns with consistent root causes
- Updates to `temporal.md`, `grafana.md`, or other reference files when the underlying systems change

**Discuss first**:
- New MCPs (affects every teammate's setup)
- New skills (affects skill-discovery behavior)
- Changes to credential handling
- Changes to the install flow

---

## Reporting bugs

If something in the plugin doesn't work as expected:

1. Check `README.md`'s troubleshooting section first.
2. Check `PLUGIN_LIFECYCLE.md` if the issue is about install/uninstall/update mechanics.
3. If still stuck, ping the maintainer in Slack with: what you did, what you expected, what happened, and whether you can reproduce it.

For security-sensitive issues (credential handling, auth flow problems), contact the maintainer directly rather than posting in public channels.

---

## Future state (post-v1)

After the plugin migrates to `payrails-hub`, the contribution model will become more structured:

- All Payrails GitHub org members get automatic access (no per-person invites).
- A more formal PR review process (probably requiring a reviewer beyond the maintainer for non-trivial changes).
- Potentially a contribute-knowledge-updates pattern that lets teammates push learnings back without manual cache promotion.
- A clearer release cadence and changelog.

This document will be updated when those changes happen.

---

## Updating this doc

If the contribution flow changes — new processes, new tooling, new policies — update the relevant section here. Keep the structure, but don't be afraid to remove sections that no longer apply (e.g., the cache-to-canonical promotion section will eventually become obsolete if a contribute-knowledge-updates pattern replaces it).

For decisions about *why* the contribution model is shaped this way, see `DESIGN_DECISIONS.md`.

For internal mechanics of how the plugin behaves at install/runtime, see `PLUGIN_LIFECYCLE.md`.
