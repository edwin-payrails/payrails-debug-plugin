---
name: payrails-knowledge-update
description: >
  Updates the payrails-debug skill's reference files with durable platform facts learned
  from a completed debugging session. Scope: API patterns, auth behaviours, tool usage
  (Grafana queries, Temporal patterns), codebase navigation conventions, provider-specific
  behaviours confirmed from API data or schema — things Claude Code should actionably use
  during future debugging. Trigger this skill when the user says things like "update the
  knowledge files", "note this down for future sessions", "save what we learned about how
  X works", "update the skill files". Do NOT trigger during active debugging — only after
  a session has concluded. Do NOT use this skill for documenting specific resolved cases
  (e.g., "Careem hit error Y, fix was Z") — that's `payrails-recurring-issue-doc`'s job
  (it writes to the Notion KB). This skill writes to the reference files inside the
  payrails-debug skill folder.
---

# Payrails Knowledge Update

You are updating the payrails-debug skill's reference files with durable platform facts
learned from a completed debugging session. The goal is to leave the files better than
you found them so that future Claude Code instances debugging similar issues start from
a stronger position.

This skill is for **actionable platform knowledge** — facts, patterns, and conventions
that Claude Code uses during debugging. For documenting **specific resolved cases**
(one merchant's one problem with its root cause and fix), use `payrails-recurring-issue-doc`
instead — that writes to the Merchant Debugging Patterns Notion database.

This is a deliberate, careful act — not automatic. Read before you write. Verify before
you assert. When in doubt, ask rather than drop — surface the ambiguous item to the user
with a brief explanation of why you're uncertain, and let them decide whether to include
it. Reserve this for substantive uncertainty; don't surface every minor formatting choice.

---

## Step 1 — Read the relevant files first

Before writing anything, read the current state of the files likely to be affected. At
minimum, read these core files:

- `../payrails-debug/SKILL.md`
- `../payrails-debug/references/payrails-knowledge.md` — API endpoints, error patterns, provider gotchas, team routing
- `../payrails-debug/references/codebase-workflow.md` — codebase exploration process

Read these additional files when the session touched the relevant area:

- `../payrails-debug/references/temporal.md` — Temporal staging access, namespace format, query patterns, codec decryption
- `../payrails-debug/references/grafana.md` — Grafana instance selection, who manages access
- `../payrails-debug/references/providers/gpay.md` — Google Pay tokenisation error patterns

Provider-specific files live under `../payrails-debug/references/providers/`. Create a new
file there (e.g. `adyen.md`, `stripe.md`) when provider-specific learnings from the session
warrant a dedicated file. When uncertain whether to create a new provider file or add to
`payrails-knowledge.md`, prefer adding to the existing file unless the provider content
has grown enough to warrant separation.

You need to know what's already there before deciding what to add, change, or leave alone.

---

## Step 2 — Decide what is worth adding

### Sources worth extracting from

Only draw learnings from sources that reflect durable, structural facts about the platform:

- **OAS spec** — confirmed endpoint paths, HTTP methods, query parameter names and formats
- **Codebase schema files** — confirmed field names and their meaning (`doc/oas/src/`)
- **Live API calls that succeeded** — confirmed response shapes, field values, what they mean
- **Grafana queries that worked** — confirmed namespace conventions, useful log query patterns
- **Temporal queries that worked** — confirmed workflow state patterns, codec decryption behaviours

Do NOT carry findings from Slack, Linear, Notion, or Plain threads into the knowledge
files. Those are case-specific context — useful for the session, but not generalizable
platform knowledge.

### What to add

- **Correct API endpoints** you confirmed by calling them successfully — exact path,
  filter/query param syntax. Verify against the OAS before documenting.
- **Diagnostic patterns** — what a specific field value or response shape means in
  practice, confirmed from actual responses or schema files.
- **"X didn't work, Y did"** — where you tried one approach, it failed, and you found
  a working alternative. Document both: what to avoid and what to do instead, so future
  instances don't repeat the wrong approach. Make the working approach prominent; describe
  the failing one only enough to recognise and avoid it.
- **Provider-specific behaviour** confirmed from live API data or schema.
- **Grafana or Temporal patterns** that worked — useful query shapes, namespace quirks,
  or codec-decryption notes that future sessions can reuse.

### How to update existing entries

When a session reveals new information that relates to existing documented guidance:

- **Augment rather than replace** when the new finding is case-specific (e.g., "this approach didn't work for merchant X, but a different approach did"). The old guidance may still work for other merchants or contexts. Keep both, and note the distinguishing condition that determines which applies.
- **Replace** only when the new finding genuinely supersedes the old (e.g., the documented endpoint is deprecated platform-wide, the tool was renamed, the schema changed for everyone). The old guidance is wrong, not just inapplicable to this case.
- **When uncertain** whether the old guidance is wrong or just doesn't fit this case, default to augmenting. A rule that fits 80% of merchants is still useful documentation; removing it loses information for those merchants.
- **When augmenting**, structure the entry so future sessions can quickly see which approach to try first, and what the fallback is if it fails. The "try first, fall back" framing fits naturally here.

### What NOT to add

- If something didn't work and you found no alternative — do not document it as
  impossible or "cannot be done". Leave it out entirely. A future Claude Code instance
  may find a way you didn't. Documenting a dead end as permanent will mislead future
  instances into not trying.
- Do not document endpoint paths or query param formats you guessed but never confirmed
  worked.
- Do not add things already covered well enough in the existing files.
- Do not add case-specific findings from Slack/Linear/Notion (e.g. "HyperPay timed out
  in this specific transaction on 2 Apr 2026") — only generalizable platform knowledge.
  Case-specific resolved patterns belong in the Merchant Debugging Patterns Notion KB
  (via `payrails-recurring-issue-doc`), not these reference files.

### Where to add it

Route each learning to the file that best matches the subject matter:

- **`payrails-knowledge.md`** — general API patterns, auth behaviours, error codes, team
  routing updates, and provider gotchas that aren't big enough to warrant a dedicated
  provider file
- **`temporal.md`** — Temporal-specific: new query patterns, codec behaviours, namespace
  conventions, workflow-type discoveries
- **`grafana.md`** — Grafana-specific: new instance learnings, access-control changes,
  useful log query patterns or namespace quirks
- **`providers/<provider>.md`** — provider-specific error patterns and fixes (GPay, Adyen,
  Stripe, Checkout.com, etc.). If the provider doesn't yet have a file and the new
  content warrants it (2+ distinct patterns, or a pattern that's clearly going to recur),
  create a new file. Otherwise add to `payrails-knowledge.md` under the provider gotchas
  section.
- **`codebase-workflow.md`** — new patterns for navigating the Payrails backend codebase
  (where specific kinds of logic live, common exploration strategies, file-structure
  conventions)
- **`SKILL.md`** — structural changes to the debugging workflow itself, new tools in the
  "Tools at your disposal" list, new or changed sections. Rare — most learnings go into
  a reference file, not the skill file itself.

If a learning genuinely spans multiple files (e.g., a Temporal pattern that also involves
an API call), document the primary context in the file that owns the subject, and
reference the related file briefly from there rather than duplicating content.

---

## Step 3 — Check for conflicts before writing

If a learning you want to add contradicts something already written:

1. Verify which is correct — Grep and Read the OAS spec files in `doc/oas/src/` before deciding.
2. If you confirm the existing entry is wrong, correct it. Note briefly why the previous
   understanding was incomplete, so future instances understand the correction isn't arbitrary.
3. If you cannot confidently determine which is right, leave the existing entry as-is
   and do not add a conflicting one. A wrong update is worse than a missing one.

---

## Step 4 — Write the updates

Apply your updates to the relevant file(s). Follow this style:

- Write for a future Claude Code instance debugging a live merchant issue — not for a
  human reader.
- Positive guidance only: say what works, say what to use, say what to try.
- Place entries under the most relevant existing section, or add a new subsection if
  nothing fits.
- Keep entries concise. The knowledge files are read at the start of every debug session
  — they should be fast to absorb, not exhaustive.

---

## Step 5 — Confirm what you changed

After making updates, briefly state:
- Which file(s) you updated
- What you added or changed, and why
- Anything you considered but decided not to add, and why

This gives the user a chance to review the decision before the session ends.