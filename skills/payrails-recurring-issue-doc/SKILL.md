---
name: payrails-recurring-issue-doc
description: >
  Draft an internal knowledge base entry (in Notion) from a resolved merchant debugging
  session or a recurring conceptual question, for future sessions to reference. Scope:
  specific resolved case patterns and recurring explanations worth saving. Trigger only
  when the user explicitly asks: "document this for the KB", "save this as a pattern",
  "add this to the debugging knowledge base", "record this resolved issue", "document
  this explanation". Do NOT trigger automatically during or after debugging — only on
  explicit request. Do NOT use this skill for durable platform facts about API patterns,
  tool usage, or codebase conventions — those go in `payrails-knowledge-update`, which
  writes to the debug skill's reference files. This skill writes to the Merchant
  Debugging Patterns Notion database.
argument-hint: "<resolved issue or recurring explanation to document>"
---

# Payrails Recurring Issue Doc

You draft internal knowledge base entries for the Payrails Solutions Engineering team's
Merchant Debugging Patterns database in Notion. Each entry documents a resolved
debugging pattern, a recurring procedure, or a recurring conceptual explanation that's
specific enough and recurring enough to be worth referencing in future debugging sessions.

This is internal documentation — for the SE team and for future Claude Code sessions
debugging similar issues. Not customer-facing. Write for a technical reader who knows
Payrails terminology.

Write everything in British English.

---

## Notion target

All entries go to the Merchant Debugging Patterns database:

- **Database URL:** https://www.notion.so/47141def527d46b8bbc8f3ee7688feb3
- **Database ID:** `47141def-527d-46b8-bbc8-f3ee7688feb3`
- **Data source ID:** `1c7d9858-959a-4ca9-b1f1-30cfd6c7ad26`

Use the data source ID for queries and inserts via the Notion MCP.

---

## Usage

```
/payrails-recurring-issue-doc <resolved issue or pattern to document>
```

Examples:
- `/payrails-recurring-issue-doc Careem's GPay tokenisation was failing because their tokenizationSpecification had gateway: adyen — needed gateway: payrails`
- `/payrails-recurring-issue-doc Document how to check Temporal workflow state when a payment execution hangs`
- `/payrails-recurring-issue-doc Explainer on how Payrails handles 3DS SCA challenges across providers`

---

## Before starting

This skill documents established, recurring content. Before drafting, determine which
category the content fits into:

- **Troubleshooting** — a specific problem with a specific symptom and a specific fix.
  Focus: *resolving something that's broken*. Most entries will be this type.
- **How-to** — a repeatable procedure. Focus: *executing a task that comes up again
  and again*. Example: "how to check Temporal workflow state when a payment hangs."
- **Explainer** — a recurring conceptual question with no fix or procedure. Focus:
  *understanding how something works*. Example: "how Payrails handles 3DS SCA challenges
  across providers", "what Payrails workflow codes mean."

**Scope gates — all three types must meet these bars:**

- The content is recurring (not a one-off). A pattern, procedure, or question that has
  come up before or will likely come up again.
- For Troubleshooting: the fix has been verified to work. Document in-progress
  investigations in Linear, not here.
- For Explainer: the explanation is confirmed and accurate. Don't document partial
  or speculative understanding.
- The content is generalisable — applies to multiple merchants or debugging contexts.
  One-off merchant-specific quirks belong in that merchant's own Notion page or a
  Linear ticket, not the KB.

**If the content doesn't fit any of the three types:**

- If it's actionable platform knowledge Claude Code would use *during* debugging
  (e.g., "single-quote API secrets because they contain shell special chars",
  "Temporal run_id must be a query param not a path segment"), use
  `payrails-knowledge-update` instead. It writes to the debug skill's reference
  files rather than the Notion KB.
- If it's a one-off detail or purely contextual information that won't be
  referenced again, it probably doesn't need documenting. Signal-heavy content
  beats noise-heavy content. Better to skip a marginal entry than clutter the
  KB with patterns no one will reuse.

---

## Step 1 — Understand the source material

Parse the input to identify:

- **What was the problem, procedure, or question?** The specific symptom/task/concept.
- **What was the root cause, the steps, or the explanation?** The actionable content.
- **What was the fix?** (Troubleshooting only) Specific steps that resolved it.
- **How specific is this?** Tied to a particular PSP, payment method, product area?
- **How recurring is this?** Has it happened multiple times already? Likely to recur?
- **Which article type fits?**
  - **Troubleshooting** — symptom → root cause → fix
  - **How-to** — repeatable procedure with prerequisites and steps
  - **Explainer** — conceptual explanation of how something works

Pick by **intent**, not just surface:
- Title starts with a symptom or error → probably Troubleshooting
- Title starts with "How to..." → probably How-to
- Title starts with "How does..." / "What is..." / "Why does..." → probably Explainer

Edge cases are OK. When genuinely unsure between two types, pick the one whose
template best captures what you have.

If the input mentions a Plain thread reference, Linear ticket, or Slack discussion,
look them up for full context (see Step 2).

---

## Step 2 — Look up context (if source references exist)

Gather context from any sources the input references:

- **Plain** (via Plain MCP) — if a thread ID is referenced, pull the full thread.
  Understand what the merchant reported, what Payrails communicated back, and any
  nuance in how the issue was framed.
- **Linear** (via Linear MCP) — if a ticket is referenced, read it. The ticket may
  contain engineering notes, final fix details, or links to the PR that shipped the
  fix. These can clarify the root cause.
- **Slack** (via Slack MCP) — if a thread or channel discussion is referenced, read
  it. Internal discussions often capture why one approach was chosen over another —
  useful for the "If the recommended fix doesn't work" section.
- **Notion** (see Step 3) — always search the KB for existing similar entries
  before drafting.

Don't redo the debugging investigation. That was already done. You're here to
document what was learned, not to verify it again.

---

## Step 3 — Search Notion for existing similar entries

Before drafting, query the Merchant Debugging Patterns database using the Notion MCP
(data source ID `1c7d9858-959a-4ca9-b1f1-30cfd6c7ad26`) for entries that might cover
the same or a similar pattern.

Use the structured properties to narrow the search:
- Article type
- Product area
- PSP
- Payment method
- Tags

Also scan the Problem Summary field for entries with similar-sounding titles.

Present any matches to the user with a brief summary of each and ask:

- **If there's a close match:** "An existing entry covers this. Should I update it in
  place (refresh the fix, add what we learned), or is this a genuinely different
  problem/procedure/explanation that warrants a new entry?"
- **If no match:** "No existing entry covers this. I'll draft a new one."

**Prefer updating existing entries in place.** Duplicates drift — one entry's fix
or explanation gets updated, the other goes stale. Only create a new entry when the
content is genuinely distinct.

---

## Step 4 — Draft the entry

Present the draft in chat for review before creating or updating the Notion entry.
Use the appropriate template for the article type chosen in Step 1. All templates
below use section headers that become the body of the Notion page. Omit sections
that don't apply to this specific entry — blank sections are worse than omitted ones.
Forcing content where none exists creates noise that misleads future readers.

### Template: Troubleshooting

```
# [Specific problem title — include the specific failure mode, error code, or
   condition that distinguishes this from other problems in the same area.
   Example: "Apple Pay tokenisation failure when `gateway` is not 'payrails'"
   not "Apple Pay not working"]

## Symptoms
[What the SE or merchant observes. Include exact error messages, HTTP codes, or
specific behavioural symptoms that a future SE would use to recognise this pattern.]

## Root cause
[Why this happens — a clear, technical explanation. Name the specific misconfiguration,
platform behaviour, or integration issue that causes it.]

## Steps to reproduce
[Optional. Include only if reproducing is straightforward and useful for verification.
Skip if the pattern is observed-in-the-wild and not easily reproducible.]

## Solution
[The fix that worked. Specific enough that a future SE can follow it:
- Exact configuration changes
- Specific API calls
- Specific field values to set
- Any verification steps to confirm the fix worked]

## If the recommended fix doesn't work
[Optional. Alternative approaches, or the next investigation step if the primary
fix doesn't apply to a variation of the problem.]

## References
- Plain thread: [URL if applicable]
- Linear ticket: [ID or URL if applicable]
- Slack thread: [link if applicable]
- Related KB entries: [links to similar or related entries in this KB]
```

### Template: How-to

```
# [Specific how-to title. Example: "How to check Temporal workflow state for a stuck
   payment execution" not "Temporal usage"]

## When to use this
[The specific situation that calls for this procedure. One to two sentences.]

## Prerequisites
[What's needed before starting — credentials, access, information, tools. Skip
if truly nothing is needed.]

## Steps
### 1. [Action verb + specific action]
[Instruction with specific details — URLs, commands, field names, expected output.]

### 2. [Next action]
[Instruction.]

[Continue as needed.]

## Verify it worked
[How to confirm the procedure succeeded. Specific to what success looks like here.]

## Common issues
[Optional. Problems that sometimes come up during this procedure, and how to
resolve each.]

## References
- Plain thread: [URL if applicable]
- Linear ticket: [ID or URL if applicable]
- Slack thread: [link if applicable]
- Related KB entries: [links to similar or related entries in this KB]
```

### Template: Explainer

```
# [Specific concept, framed as the question or topic.
   Example: "How Payrails handles 3DS SCA challenges across providers"
   Example: "What Payrails workflow codes mean and when each applies"]

## Short answer
[1-3 sentence summary that's usable on its own. Most readers will stop after this
section. Make it carry the essential answer.]

## Detailed explanation
[Fuller answer with the mechanism, relevant components, decision rules, or examples.
Keep to 200-400 words. Link out to detailed docs or code for anyone who needs to
go deeper.]

## When this matters
[Optional. What kinds of debugging sessions, merchant questions, or configurations
this Explainer helps with.]

## References
- Relevant docs: [links]
- Related KB entries: [links to similar or related entries]
- Codebase pointers: [if relevant]
```

---

## Step 5 — Set the Notion properties

Alongside the body content, fill in the database properties. Present these to the user
for confirmation before creating the entry.

```
**Problem Summary (title):** [same as the specific title from the body]
**Article type:** [Troubleshooting / How-to / Explainer]
**Product area:** [Orchestration / Vault / Tokenization / Analytics / Workflows /
                   SDK / Portal / Auth / Other]
**PSP:** [Stripe / Checkout.com / Adyen / Unzer / Braintree / Payplug / HIpay / TAP /
          Lean / Mercado Pago / Authorize.net / Nuvei / Worldpay / Rapyd / PCI Proxy /
          Network International / CraftGate / Revolut / Amazon Payment Services /
          Noon Payments / Chargebee / N/A / Other — one or multiple]
**Payment method:** [Card / Apple Pay / Google Pay / PayPal / SEPA / BNPL / iDeal /
                     Klarna / Bancontact / Mada / Pago Efectivo / Multibanco /
                     Mobile Money / Bank Transfer / Open Banking / N/A / Other —
                     one or multiple]
**Tags:** [Short keywords not captured by other fields — e.g. "3ds", "mtls",
           "tokenisation", "webhook". Leave blank if none apply.]
**Confidence:** [High / Medium / Low]
**Last updated:** [Today's date in YYYY-MM-DD]
**Related Plain thread:** [URL or blank]
**Related Linear issues:** [Comma-separated IDs or URLs, or blank]
**Contributed by:** [Default to the SE running the skill — your name. Ask if unclear.]
```

**Guidance on each property:**

- **Article type** — match the template chosen in Step 1.
- **Product area** — the Payrails area the content lives in. If it genuinely spans
  multiple areas, pick the most central one and note the others in Tags.
- **PSP / Payment method** — specific to the scenario. Use N/A only if genuinely
  not PSP-specific or payment-method-specific (common for Explainers). Use Other
  when an integration exists but isn't in the select options (prompt the user to
  add it to the schema later).
- **Confidence** — honest about how well-validated this content is:
  - **High** — verified multiple times, root cause / procedure / explanation fully
    understood, content has held up
  - **Medium** — resolved or established once with confidence, but not yet validated
    across multiple instances
  - **Low** — worked once, unclear if the fix/procedure/explanation generalises, or
    only partially understood
- **Contributed by** — defaults to the SE running the skill. Fill automatically if
  you know who's invoking you; ask only if genuinely unclear.

**Blank fields are fine.** If a property doesn't apply to this entry, leave it
blank. Forced content is worse than absence. The database is designed for partial
entries; filters will simply skip entries with blank fields for that filter.

---

## Step 6 — Create or update the Notion entry

When the user confirms the draft:

- **For a new entry:** use the Notion MCP to insert a new row into the database
  (data source ID `1c7d9858-959a-4ca9-b1f1-30cfd6c7ad26`). Set all the properties
  confirmed in Step 5. Set the page body to the templated content from Step 4.
- **For an update:** use the Notion MCP to update the existing row. Preserve the
  existing title and URL (don't create a duplicate page). Update the body content
  and relevant properties. Bump `Last updated` to today. At the bottom of the page
  body, add a short dated change-log note:

  ```
  ---
  **[YYYY-MM-DD]:** [Brief note on what changed and why. Example: "Updated fix steps
  for error X — previous approach no longer works after API v2.3 migration."]
  ```

After creation or update, return the page URL so the user can open the entry in
Notion to verify.

**If the Notion MCP fails** (insert or update error, access denial, schema mismatch):
try one retry for transient-looking failures (network timeout, rate limit). If the
retry also fails, stop and surface the error clearly to the user. Don't retry silently
beyond that — the user decides whether to retry again, investigate the root cause,
or skip this entry.

---

## Step 7 — Offer iterations

After the entry is created or updated:

- "Want me to add more detail to any section?"
- "Should I also create a companion entry for a related pattern?" (e.g., a
  Troubleshooting entry that has a natural How-to companion, or an Explainer that
  explains the concept behind a Troubleshooting entry)
- "Should I flag any existing entries that reference the same area so they can
  be cross-linked?"

---

## Writing principles

1. **Specific titles, not general ones.** "Apple Pay tokenisation failure when
   `gateway` is not 'payrails'" beats "Apple Pay not working". Future searchers
   match on the specific symptom or specific concept. One article = one specific
   topic.
2. **Exact technical detail.** Include real error codes, field names, specific
   HTTP statuses, specific config values. These are what future SEs (and future
   Claude Code sessions) search for.
3. **Concise but complete.** 200–500 words is the sweet spot for body content.
   If an entry needs more than that, link out to a Linear ticket or codebase
   reference rather than inlining extensive detail.
4. **Positive guidance.** Say what works, what to check, what to set. Avoid
   framing things as permanent impossibilities — document the working path.
5. **Skip sections that don't apply.** Blank sections in the template are worse
   than omitted ones. Don't fabricate content to fill a section.
6. **Internal language, not customer language.** Technical terms are fine — this
   isn't customer-facing. Avoid unnecessary jargon, but don't soften precise
   terminology for an imagined lay audience.

---

## Maintenance pattern

Knowledge decays. An entry documented today may be wrong a year from now if the
platform changes. This skill isn't run on a schedule — maintenance happens
organically:

- **When a future debugging session consults an existing KB entry and finds it
  out of date** (documented fix no longer works, platform behaviour has changed,
  explanation no longer reflects how things actually work), refresh the entry
  in place via this skill. Add a dated note at the bottom of the page. Don't
  let stale content accumulate — stale is worse than missing.
- **When a new debugging session reveals new detail that extends an existing
  entry**, update the existing entry rather than creating a near-duplicate.

No formal cadence, no quarterly reviews. The KB stays useful because it's
maintained at the point of use.

---

## When to update vs. create new

**Update existing when:**
- The pattern is the same but the fix / procedure / explanation needs refreshing
  (platform changed, old content no longer works or no longer reflects reality)
- The entry is mostly right but missing a detail, edge case, or variation
- A better workaround, cleaner root cause, or clearer explanation has been discovered
- A new merchant or session confirmed the documented content works

**Create new when:**
- A genuinely different problem / procedure / concept, even in the same product area
  or with the same PSP
- The existing article would need to be split to accommodate this — if adding to
  it would make it muddled, start a new one instead
- The product area, PSP, or payment method is different from any existing entry

---

## Notes

- This skill only touches the Merchant Debugging Patterns Notion database. It does
  not write to Linear, Slack, or other destinations. Those are for other skills
  (active bug tracking in Linear, internal discussion in Slack).
- For durable platform facts (API patterns, tool usage, codebase conventions) that
  Claude Code uses *during* debugging, use `payrails-knowledge-update` — that
  writes to the debug skill's reference files rather than the Notion KB.
- The skill is explicit-triggered only. It does not run automatically at the end
  of a debugging session. If an SE wants an entry documented, they ask.
- Entry body content is free-form markdown on the Notion page. The database
  properties are separate. Don't try to encode the body template as additional
  properties — let the page body hold the long-form content and let the
  properties hold the structured filterable fields.