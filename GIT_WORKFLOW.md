# Git Workflow — releasing and rolling back the plugin

How to ship a change to the Payrails Debug Plugin, and how to roll one back. This is the
single home for the release and rollback git flow.

**What's elsewhere (and why):**
- **CONTRIBUTING.md** — the contributor model (who can contribute, how learnings flow
  back, semver policy). The short branch→PR list there is the summary; this file is the
  detail.
- **PLUGIN_LIFECYCLE.md** — the `.env.tpl` *mechanics* (Maintainer commit cycle), the
  teammate-side **Update flow** (two caches), and the **Reset A/B/C** test playbooks.
- **BUILD_HANDOFF.md** — finding #14 (the `.env.tpl` discipline) and finding #17
  (directory-install loads live from the repo).

---

## The mental model (read once)

- **A branch is a label on commits. Uncommitted edits belong to no branch** — they move
  freely onto whatever branch you create next. So editing in the working tree while on
  `main` is fine as long as you haven't committed; `git checkout -b <branch>` carries the
  changes onto the new branch.
- **The `version` field in `.claude-plugin/plugin.json` is what distributes a change.**
  Teammates' update only triggers when the number goes **up**. Nothing reaches a
  GitHub-installed teammate until the version bumps *and* they update.
- **Every release is the same steps** (below). A feature, a fix, or a rollback differ only
  in *what's in the change* — the mechanics are identical every time.
- **The maintainer's own install loads live from this repo** (finding #17), so the
  maintainer sees changes without pushing. Pushing + version bump is for *GitHub-installed
  teammates*.

---

## Normal release flow

Run these in order from the repo root. `<repo>` = `~/Documents/Payrails/payrails-debug-plugin`.

### Chunk 1 — start from latest

```
git checkout main
git pull
```
- Expected: `Already up to date.` or a fast-forward. You're on a clean, current `main`.
- Wrong: divergence / conflict — resolve before continuing.

### Chunk 2 — branch

```
git checkout -b <prefix>/<short-name>
```
- Use `feat/`, `fix/`, `docs/`, or `chore/`. Uncommitted edits move onto this branch.

### Chunk 3 — make the change + bump the version

- Make your edits.
- Bump `version` in `.claude-plugin/plugin.json` (semver — see CONTRIBUTING.md: new
  MCP/skill = minor; bug fix / bundle sync / docs = patch). **A behavior change that isn't
  version-bumped will not reach teammates.**

### Chunk 4 — revert `.env.tpl` to placeholders (finding #14) — BEFORE staging

The maintainer's working `.env.tpl` holds real `op://` references for daily use. Those
must never be committed (they leak personal vault structure).

```
git checkout .env.tpl
git status
```
- Expected: `.env.tpl` does **not** appear as modified. It will not be staged.
- Wrong: `.env.tpl` still listed — re-run; if already staged, `git restore --staged .env.tpl` then revert.

### Chunk 5 — stage, sanity-check, commit

```
git add -A
git status --short
git diff --cached --name-only
```
- Expected: your intended files staged; `.env.tpl` **not** in the list. `BUILD_HANDOFF.md`,
  `CLAUDE.local.md`, `.env`, and the briefing/transition docs never appear (they're
  gitignored). If the change includes the Temporal bundle, confirm
  `mcp-servers/temporal/index.mjs` is staged.

```
git commit -m "<type>: <summary> (v<x.y.z>)"
```
- **No AI-attribution / `Co-Authored-By` footer** (maintainer convention).

### Chunk 6 — push and open the PR

```
git push -u origin <prefix>/<short-name>
gh pr create --base main --title "..." --body "..."
```
- The push *creates* the remote branch; the PR is opened from it.

### Chunk 7 — merge

```
gh pr merge <PR#> --merge --delete-branch
```
- Merges with a merge commit and deletes the branch (local + remote).

### Chunk 8 — sync local main

```
git checkout main
git pull
```
- You pull your *own* merged work because the merge commit was created on GitHub.

### Chunk 9 — restore the maintainer `.env.tpl` (finding #14) — AFTER merge

So daily `payrails-claude` (`op inject`) works again. Replace the placeholders with the
maintainer's real refs:

```
sed -i '' \
  -e 's|op://<your-vault>/<your-grafana-item>/username|op://<MAINTAINER_VAULT>/<MAINTAINER_ITEM>/username|' \
  -e 's|op://<your-vault>/<your-grafana-item>/password|op://<MAINTAINER_VAULT>/<MAINTAINER_ITEM>/password|' \
  .env.tpl
```
- See PLUGIN_LIFECYCLE.md ("Maintainer commit cycle") for the exact maintainer values.
- After this, `git status` shows `.env.tpl` modified again — that's the daily working
  state, **left uncommitted**. The next release starts again at Chunk 4.

### Chunk 10 — distribute (GitHub-installed teammates only)

Teammates need **both** caches refreshed: refresh the marketplace cache (UI refresh icon),
then `claude plugin update payrails-debug@payrails-debug-plugin`. See PLUGIN_LIFECYCLE.md
"Update flow". (The maintainer's own directory-install already tracks the repo live — no
update step needed there. Whether claude-app / cowork auto-picks-up or needs a reinstall
is environment-specific — verify in that surface.)

---

## Reset playbooks are NOT part of a push

The **Reset A/B/C** playbooks (PLUGIN_LIFECYCLE.md) clean install state to simulate a fresh
teammate **for testing**. They are **not** run as part of pushing to GitHub. Do not run
them on a normal release.

The only "reset"-like step in a release is Chunk 4 / Chunk 9 — reverting and restoring
`.env.tpl` (finding #14). That happens on **every** push. Reset A/B/C happen **only** when
you're deliberately testing a clean install.

---

## Versioning — which number, and when not to bump

`plugin.json`'s `version` is `MAJOR.MINOR.PATCH` (semver; pre-1.0, so `0.x.y`). This is the
same scheme as CONTRIBUTING.md's "Versioning" section — keep the two in sync.

- **PATCH** (`0.3.X`) — bug fixes, skill/reference content fixes, Temporal **bundle syncs**,
  troubleshooting tweaks. *(e.g. the Temporal MCP updates `0.3.0 → 0.3.1 → 0.3.2 → 0.3.3`.)*
- **MINOR** (`0.X.0`) — new capability: a new MCP or a new skill. *(e.g. bundling the
  Temporal MCP: `0.2.1 → 0.3.0`.)*
- **MAJOR** (`X.0.0`) — breaking changes. *(Pre-1.0, breaking changes still ride in
  minor/patch by convention.)*

**When NOT to bump.** The version only gates what the plugin **loads at runtime** (the
version-pinned cache). So:
- Changes under `skills/**` (incl. `references/**`), `.mcp.json`, `mcp-servers/**`, or
  `.claude-plugin/**` → **bump** (teammates won't get them otherwise).
- Changes to **repo-only docs the plugin never loads** — `README.md`, `CONTRIBUTING.md`,
  `GIT_WORKFLOW.md`, `DESIGN_DECISIONS.md`, `PLUGIN_LIFECYCLE.md` → **no bump**. *(This file
  was added without one.)*
- Gitignored maintainer files (`BUILD_HANDOFF.md`, `CLAUDE.local.md`, the briefing/transition
  docs) are never committed at all.

Rule of thumb: **if a teammate's running plugin would behave differently, bump; if only a
human reading the repo is affected, don't.** A no-bump docs change still goes through the
full flow above (including the `.env.tpl` revert/restore) — it just skips Chunk 3's bump.

---

## Rolling back a release (roll *forward*, never down)

When a shipped version regresses and teammates need the previous behavior back.

**Key rule: re-publish the old content under a *higher* version number.** Do not re-point
`main` at a lower number — teammates who already cached the higher number won't pick a
lower one up (downgrade behavior is unverified), and the cache-bust depends on the version
**increasing**.

**Why you can't roll back by branching from the old commit + merging:** a merge *combines*
changes; it does not *replace*. Merging a branch built from the old commit leaves the bad
feature in place (the PR diff would show only a version bump). To make `main` *lose*
something you must put an explicit *undo* on top of current `main`.

### Use `git revert` (handles added/removed files)

```
git checkout main && git pull
git checkout -b rollback/restore-<old-version>
git revert <bad-commit>
```
- Prefer `git revert` over copying old files: a revert exactly inverts the commit, so files
  the change *added* get removed and files it *deleted* get restored — `git checkout
  <old-commit> -- <paths>` only restores existing paths and won't delete additions.
- If the change landed as a merge commit, revert the underlying `feat:`/`fix:` commit
  (normal commit) rather than the merge, to avoid `-m 1` complications.

Then bump `plugin.json` **up** (e.g. `0.3.3 → 0.3.4`), and run the normal release flow
(Chunks 4–10). Teammates update and get the old behavior back, shipped as a higher version.

### Your work is never lost — keep fixing on a branch

A revert adds a commit; it never deletes the original. To keep working on the fix while
teammates sit on the safe version:

```
git checkout -b fix/<feature>            (off current main, after the rollback shipped)
git revert <the-rollback-commit>         (undo the undo — the feature returns)
```
…then fix on top, bump the version **up** again (e.g. `0.3.4 → 0.3.5`), and ship via the
normal flow. Version timeline goes only up: `0.3.3 (bad) → 0.3.4 (old content back) →
0.3.5 (fixed)`.

### Maintainer-only local fallback

If only the maintainer needs old behavior locally (not the whole team), no GitHub change
is needed — the directory-install loads live from the repo (finding #17):

```
git checkout <good-commit> -- skills/ .mcp.json mcp-servers/
```
Restore with `git checkout main -- skills/ .mcp.json mcp-servers/` afterward.

### Rollback bookmark

The tag `pre-temporal-mcp` marks the clean pre-Temporal-MCP state. Tag a known-good state
before a risky change if you want a named reference: `git tag <name> && git push origin <name>`.

---

## Quick reference — "I made a change, what now?"

1. Branch off latest `main`, make the change, **bump `plugin.json`**.
2. `git checkout .env.tpl` (placeholders) before staging — finding #14.
3. Stage, confirm `.env.tpl` is not staged, commit (no AI footer), push, PR, merge.
4. `git checkout main && git pull`, then restore the real `.env.tpl` refs.
5. Tell GitHub-installed teammates to refresh marketplace + `claude plugin update`.
6. **Do not** run Reset A/B/C — those are for testing a clean install, not for pushes.
