---
name: payrails-thread-debug
description: >
  Autonomous Payrails merchant issue investigator. Takes a reported problem from a
  Plain support thread OR a Slack message, fetches the details, and runs the full
  payrails-debug investigation by itself — no SE hand-holding required.
  Trigger this skill when the user points to a reported merchant problem to investigate:
  - Plain — a thread reference like "t-2141"/"T-2141" or a Plain thread link
    ("look into thread t-XXXX", "debug this Plain thread", "investigate this support ticket").
  - Slack — a link to a SPECIFIC Slack message TOGETHER WITH a debugging request such as
    "take care of this problem in Slack", "investigate this Slack message", "debug this".
    A Slack link on its own is NOT a trigger — it must come with intent to investigate,
    since a link may be pasted for other reasons.
  Also trigger when the user pastes a Plain reference, or a Slack link with debugging
  intent, alongside merchant credentials (clientId/clientSecret).
  IMPORTANT: for a Slack-sourced problem you need the link to the SPECIFIC Slack message —
  a channel name, or a vague "there's a problem in Slack", is not enough. If you weren't
  given an exact message link, ask for it before proceeding.
  The skill fetches the problem from Plain or Slack, runs the complete payrails-debug
  workflow, and delivers a structured diagnosis with confidence level and a clear
  human/machine action split.
---

# Payrails Thread Debug

You are running an autonomous debugging session for a Payrails merchant issue reported
via a Plain support thread or a Slack message. Your job is to fetch the reported problem,
pass it into the full payrails-debug workflow, and deliver the resulting diagnosis —
without pausing to ask the SE to check things they're not physically required for.

The actual debugging logic, tool usage (API, Grafana, Temporal, codebase, knowledge
files), and output format all live in `../payrails-debug/SKILL.md`. Read that skill
and its knowledge reference at `../payrails-debug/references/payrails-knowledge.md`
before doing anything else.

---

## Step 1 — Collect inputs

First, identify the **source** of the problem and get a precise pointer to it, then
collect the environment and credentials.

**Problem source + pointer** — one of:

- **Plain** — a thread reference (`T-XXXX`, e.g. "t-2141") *or* a Plain thread link.
- **Slack** — a link to the **specific Slack message** (a permalink to the exact message),
  together with a request to investigate or debug it. A Slack link on its own isn't an
  investigation request (it may be pasted for another reason), and a channel name or a
  vague "there's a problem in Slack" is NOT enough — a channel can contain many separate
  issues. If you weren't given an exact message link, ask for it before proceeding.

If the source itself is unclear, ask whether the problem is in Plain or Slack and request
the corresponding reference or link.

**Environment** — production or staging. This matters because the base URL and
credentials differ. If not stated, ask explicitly before making any API calls — don't
guess. Getting this wrong causes repeated failures that waste time and confuse the
investigation.

- Production → Base URL: `https://api.payrails.io`
- Staging → Base URL: `https://rc-api.staging.payrails.io`

**clientId** — the merchant's API client ID for the relevant environment.

**clientSecret** — the merchant's API secret for the relevant environment.

If credentials aren't provided, ask for them. State which environment you need them for.

---

## Step 2 — Read the reported problem

Fetch the problem from its source. Treat it the way the payrails-debug skill treats a
problem brought to it by an SE.

- **Plain** — use the Plain MCP tool to fetch the thread. Search for the thread by its
  `T-XXXX` reference if needed (the internal ID format differs from the display
  reference); a Plain thread link also resolves to the thread.
- **Slack** — use the Slack MCP to read the linked message and its thread. A Slack
  permalink encodes the channel and the message timestamp; read that message plus any
  thread replies to get the full context.

Extract from the source:
- Merchant name and contact
- The exact error or symptom reported
- Any IDs mentioned (execution ID, payment ID, gateway reference, merchantTransactionId)
- What the merchant / reporter is asking for

---

## Step 3 — Run the debugging workflow

Follow the full workflow defined in `../payrails-debug/SKILL.md`:
UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE.

That skill handles the actual debugging: autonomous API, Grafana, and Temporal checks;
codebase exploration; knowledge references; and the output format.

**Autonomous framing — specific to thread-debug sessions:**

Because you were invoked with a reported problem (a Plain thread or a Slack message) and
credentials, the SE expects you to run the full investigation yourself, not pause for
their input. Don't ask the SE to check things they could do manually — the debug skill
will try API, Grafana, Temporal, and codebase lookups first, and only flag genuinely
inaccessible items (PSP dashboards, human-only approval flows) as needing the SE.

Deliver the final result using the output format defined in `../payrails-debug/SKILL.md`.
When populating the "Problem summary" field, include what the merchant reported in the
Plain thread or Slack message and what they're asking for.

**Do NOT make any changes.** Fetching and inspecting data is fine. Creating, modifying,
or deleting anything is not.

---

## After delivering the diagnosis

If the output's "Follow-up communications needed" section flags that a merchant response
or internal escalation (Linear ticket, Slack message) is needed, offer to invoke
`payrails-response-draft` to produce the appropriate draft. Don't draft the communication
yourself — `payrails-response-draft` handles that when the user explicitly requests it.

When you do, pass along the **originating thread link** (the Plain thread URL or Slack
message link you read in Step 2) and the **merchant name**, so a Linear-ticket draft can
attach the thread as a Resource link and the merchant as a customer request without having
to ask for them again.

---

## Notes

- Write in British English for any merchant-facing or Slack/Linear draft text.
- The payrails-debug skill contains team routing info (who owns what) — it will use
  this when filling in the "What needs a human — and who specifically" and
  "Follow-up communications needed" sections.
- If you hit a case where something genuinely cannot be determined via API, Grafana,
  Temporal, or the codebase (e.g. PSP dashboards, human-only approval flows), say so
  explicitly in the output. State exactly what a human would need to look up and where.
