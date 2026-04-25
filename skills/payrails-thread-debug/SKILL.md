---
name: payrails-thread-debug
description: >
  Autonomous Payrails merchant issue investigator that reads a Plain support thread and
  runs the full payrails-debug investigation by itself — no SE hand-holding required.
  Trigger this skill when the user provides a Plain thread ID (like "t-2141", "T-2141",
  "look into thread t-XXXX", "debug this Plain thread", "investigate this support ticket")
  and wants a full autonomous diagnosis including direct API calls. Also trigger when the
  user pastes a Plain thread reference alongside merchant credentials (clientId/clientSecret).
  The skill fetches the problem from Plain, runs the complete payrails-debug workflow,
  and delivers a structured diagnosis with confidence level and clear human/machine action
  split.
---

# Payrails Thread Debug

You are running an autonomous debugging session for a Payrails merchant issue reported
via a Plain support thread. Your job is to fetch the thread, pass the issue into the
full payrails-debug workflow, and deliver the resulting diagnosis — without pausing to
ask the SE to check things they're not physically required for.

The actual debugging logic, tool usage (API, Grafana, Temporal, codebase, knowledge
files), and output format all live in `../payrails-debug/SKILL.md`. Read that skill
and its knowledge reference at `../payrails-debug/references/payrails-knowledge.md`
before doing anything else.

---

## Step 1 — Collect inputs

You need four things before starting. Collect any that aren't already provided:

**Plain thread ID** — the T-XXXX reference (e.g. "t-2141"). If not given, ask for it.

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

## Step 2 — Read the Plain thread

Use the Plain MCP tool to fetch the thread. The thread is your problem input — treat
it the way the payrails-debug skill treats a problem brought to it by an SE.

Search for the thread by its T-XXXX reference if needed (the internal ID format differs
from the display reference).

Extract from the thread:
- Merchant name and contact
- The exact error or symptom reported
- Any IDs mentioned (execution ID, payment ID, gateway reference, merchantTransactionId)
- What the merchant is asking for

---

## Step 3 — Run the debugging workflow

Follow the full workflow defined in `../payrails-debug/SKILL.md`:
UNDERSTAND → SEARCH → DIAGNOSE → FIX → ESCALATE.

That skill handles the actual debugging: autonomous API, Grafana, and Temporal checks;
codebase exploration; knowledge references; and the output format.

**Autonomous framing — specific to thread-debug sessions:**

Because you were invoked with a Plain thread and credentials, the SE expects you to
run the full investigation yourself, not pause for their input. Don't ask the SE to
check things they could do manually — the debug skill will try API, Grafana, Temporal,
and codebase lookups first, and only flag genuinely inaccessible items (PSP dashboards,
human-only approval flows) as needing the SE.

Deliver the final result using the output format defined in `../payrails-debug/SKILL.md`.
When populating the "Problem summary" field, include what the merchant reported in the
Plain thread and what they're asking for.

**Do NOT make any changes.** Fetching and inspecting data is fine. Creating, modifying,
or deleting anything is not.

---

## After delivering the diagnosis

If the output's "Follow-up communications needed" section flags that a merchant response
or internal escalation (Linear ticket, Slack message) is needed, offer to invoke
`payrails-response-draft` to produce the appropriate draft. Don't draft the communication
yourself — `payrails-response-draft` handles that when the user explicitly requests it.

---

## Notes

- Write in British English for any merchant-facing or Slack/Linear draft text.
- The payrails-debug skill contains team routing info (who owns what) — it will use
  this when filling in the "What needs a human — and who specifically" and
  "Follow-up communications needed" sections.
- If you hit a case where something genuinely cannot be determined via API, Grafana,
  Temporal, or the codebase (e.g. PSP dashboards, human-only approval flows), say so
  explicitly in the output. State exactly what a human would need to look up and where.