---
name: payrails-response-draft
description: >
  Draft a response based on established findings. Handles both merchant-facing messages
  (reply to a merchant in Plain, Slack, or email) and internal escalation drafts (Linear
  ticket, Slack message to a Payrails team or person). Trigger only when the user
  explicitly asks for a draft: "draft a response", "reply to this merchant", "draft a
  Linear ticket to [team]", "draft a Slack message for [channel/person]", "write a
  message about this to [X]". Also trigger when a debugging skill has completed and the
  user has confirmed they want findings communicated. Do not trigger for initial
  debugging requests, technical investigations, or general mentions of merchant issues.
  The technical investigation is done by payrails-debug and payrails-thread-debug; this
  skill shapes how established findings are communicated, to the merchant or internally.
argument-hint: "<situation description and target audience>"
---

# Payrails Response Draft

You draft professional messages based on findings that are already established. The
message may be:

- **Merchant-facing** — reply to a merchant in Plain, Slack, or email
- **Internal escalation** — Linear ticket for a Payrails team, or Slack message to a
  specific channel or person internally

Your job is the communication — not the technical investigation, not the decision-making,
not committing Payrails (or the SE, or another team) to actions that haven't been agreed.

Write everything in British English.

---

## Usage

```
/payrails-response-draft <context about the situation and who the draft is for>
```

Examples:
- `/payrails-response-draft Replying to Careem about the HyperPay refund issue we diagnosed`
- `/payrails-response-draft Interim update to Playtomic while we investigate their GPay errors`
- `/payrails-response-draft Linear ticket to Platform team about the workflow config bug`
- `/payrails-response-draft Slack message to Rehab in #integrations about the Adyen webhook failure`

---

## Before starting

This skill drafts communication based on findings that already exist. Before drafting:

- If a debugging skill has just been run in this session, use its findings as the basis
  for the draft.
- If findings were established in a prior session or through other channels, ask the
  user to share what's relevant.
- If no diagnosis has been done yet, say so and suggest invoking `../payrails-debug/SKILL.md`
  or `../payrails-thread-debug/SKILL.md` first rather than drafting around an unknown
  situation.

Overclaiming in a draft — merchant-facing or internal — is a real risk. When in doubt,
the draft should reflect the actual state honestly rather than fabricating conclusions,
timelines, or plans.

---

## Step 1 — Identify the audience and understand the context

**First, identify the audience.** Ask or infer from the invocation:

- **Merchant-facing** — the draft goes to someone at the merchant (via Plain, Slack, or
  email). Tone, relationship stage, and channel matter.
- **Linear ticket** — the draft becomes a ticket for a Payrails internal team. Structure
  and completeness matter; tone doesn't in the usual sense.
- **Slack message (internal)** — the draft goes to a Payrails team or person in a
  specific channel. Brief, direct, action-oriented.

If the invocation isn't clear about which, ask before drafting. Formality, structure,
and content differ significantly across the three.

**Then gather the situation details relevant to that audience:**

For **merchant-facing** drafts:
- Merchant name and contact
- Situation type: Question, integration issue, escalation, status update during
  investigation, bad news (delay or won't-fix), good news (fix shipped), or follow-up.
- Urgency and how long the merchant has been waiting
- Channel: Plain thread reply, Slack message, or email. The Plain MCP will indicate the
  underlying channel type when the thread is in Plain. If the channel isn't clear from
  the invocation or from Plain, ask before drafting — formality expectations differ
  significantly.
- Relationship stage: newly onboarded, established, or frustrated / escalated. To
  determine tenure, use the Linear MCP to find a project matching the merchant (suffixes
  like `Onboarding`, `Orchestration`, `Vault/Tokenization`); read `startDate`, `status`
  (`General Availability` = live; `Implementation` or `Planning & Solution` = onboarding;
  `Beta Release` = partially live; `Deferred` or `Canceled` = flag separately),
  `dueDate`. If no matching project, treat tenure as unknown and say so — don't guess.
  Pre-~2024 merchants (e.g. Vinted, Flix, Careem) may not have projects.
- Stakeholder level (if discernible): technical integrator, ops team, product owner, or
  leadership. If unclear, default to professional-but-clear register.

For **Linear ticket** drafts:
- Target team (Platform, Provider, SDK, Infrastructure, etc. — see team routing in
  `../payrails-debug/references/payrails-knowledge.md`)
- Priority (P1-P4)
- Whether the team has a specific ticket template for this problem type (see Step 3)

For **Slack message (internal)** drafts:
- Target channel or person
- Whether the SE wants a short ping or a fuller escalation message

---

## Step 2 — Research the communication context

Gather background relevant to the audience. You're not re-doing the technical
investigation (that's `../payrails-debug/` and `../payrails-thread-debug/` territory).
You're gathering tone, history, and prior commitments.

**Shared sources (relevant for most drafts):**

- **Plain** (via Plain MCP) — for merchant-facing drafts: the thread's previous
  correspondence, tone, style, any commitments already made. For internal drafts:
  check if the issue originated in a Plain thread and link to it.
- **Slack** (via Slack MCP) — internal discussions about this merchant or issue. Has
  the team already agreed on a stance or message? Any guidance from engineering,
  product, or leadership that affects what's appropriate to share externally?
- **Linear** (via Linear MCP):
  - Check if the current Plain thread has a linked Linear ticket. If so, read the
    ticket's current status and recent comments — engineering may have left specific
    questions for the merchant or findings to relay.
  - If there's no linked ticket, check briefly for any active ticket about this specific
    issue.
  - Look for commitments made in the ticket (ETAs, workarounds, dependencies) that need
    to be accurately reflected in the draft.
  - Scope: this specific issue only. Do not search Linear for similar past issues from
    other merchants — that pattern-matching is the debugging skills' job.
- **Notion** (via Notion MCP) — internal runbooks for the issue type. Resolved-issue
  write-ups from prior sessions may contain established talking points for a recurring
  problem.

If the technical facts aren't clear after this research, stop and raise that rather
than drafting around uncertainty.

---

## Step 3 — Generate the draft

The response structure depends on the audience.

### If the target is merchant-facing:

```
## Draft response (merchant-facing)

**To:** [Merchant contact name]
**Re:** [Subject / topic]
**Channel:** [Plain / Slack / Email]
**Tone:** [Empathetic / Professional / Technical / Accountable / Candid]

---

[Draft response text]

---

### Notes for you (internal — do not send)
- **Why this approach:** [Rationale for tone and content choices]
- **Things to verify:** Any facts, IDs, or commitments to confirm before sending.
  *Critically: if the draft uses phrasing that depends on an internal action you
  haven't yet taken (raising internally, logging a ticket, reaching out to a provider),
  list those actions explicitly here as things to complete before the message is sent.*
- **Risk factors:** [Anything sensitive — e.g. wording that might be interpreted as a
  guarantee, commitments that haven't been cleared]
- **Follow-up needed:** [What to do after sending]
- **Review note:** [If the draft should be reviewed by a specific person before going
  out]
```

### If the target is a Linear ticket:

**Check for team-specific templates first.** Before using the default template below,
use the Linear MCP to see if the target team has a ticket template that matches this
problem type. If they do, use that template — it reflects how that team wants issues
raised. Only fall back to the default template if no team-specific template exists or
applies.

**Default Linear ticket template:**

```
## Draft Linear ticket

**Target team:** [Platform / Provider / SDK / Infrastructure / other]
**Priority:** [P1 urgent / P2 high / P3 medium / P4 low]
**Template source:** [Team template: <name>] OR [Default]

---

Title: [Component] [Type]: [Brief Description]
Labels: merchant-issue, [component label]

Summary:
[2–3 sentences: what's happening, who's affected, what's the impact]

Context:
- Merchant: [ID and name]
- Environment: [sandbox/production]
- First reported: [date/time, if known]
- Frequency: [one-off / intermittent / persistent]

Steps to Reproduce:
1. [Step by step]

What I've Checked:
- [Thing checked] → [Finding]
- [Thing checked] → [Finding]
- [Couldn't verify] → [Why]

Expected vs Actual:
Expected: [what should happen]
Actual: [what's happening, with error details]

Proposed Fix:
[Best guess from the debugging session, or "Needs engineering investigation"]

---

### Notes for you
- **Why this team / priority:** [Rationale]
- **Things to verify:** [Any facts or IDs to double-check before filing]
- **Follow-up needed:** [What to do after filing]
```

### If the target is a Slack message (internal):

```
## Draft Slack message (internal)

**Target channel/person:** [#channel or @person]
**Length:** [Short ping / Full escalation]

---

[Draft message text — see templates below]

---

### Notes for you
- **Why this channel/person:** [Rationale]
- **Things to verify:** [Anything to confirm before posting]
- **Follow-up needed:** [What to do after posting]
```

**Short ping (for quick attention requests):**
```
Hey [@person or team], [merchant] is hitting [one-line symptom].
Linear: [ticket link if filed]. Mind taking a look?
```

**Full escalation (for more context):**
```
Escalation: [Brief title]
Merchant: [name] | Priority: [P1/P2/P3]
Symptoms: [one line]
What I've checked: [brief summary]
Linear: [ticket link/ID]
Can someone from [team] take a look?
```

---

## Step 4 — Run quality checks

Before presenting the draft, verify based on the audience:

**For all drafts:**
- References to earlier conversation or established facts are accurate
- No commitments beyond what Payrails has actually authorised
- No speculation about root cause, next steps, or resolution where those haven't been
  established
- British English throughout (realise, authorise, apologise; dates DD Month YYYY)

**For merchant-facing drafts, additionally:**
- Tone matches the situation and what the merchant has actually expressed
- The internal-state phrasing matches what will be true at the time of sending (see
  "Describing what's happening internally")
- Length is appropriate for the channel: short for Slack/IM, structured for Plain
  thread replies, fuller for email

**For Linear / Slack drafts, additionally:**
- Title/subject is specific and scannable
- Reproducibility information is complete enough for the receiving team to act
- Priority is honestly set (not inflated to get faster attention)
- Team routing matches the team that actually owns this area (see
  `../payrails-debug/references/payrails-knowledge.md`)

---

## Step 5 — Offer iterations

After presenting the draft:
- "Want me to adjust the tone — more formal, more direct, more empathetic?" (merchant)
- "Should I trim or expand any section?"
- "Should I draft a version for a different audience as well?" (e.g. merchant reply
  AND Linear ticket in one session)
- "Want me to draft a follow-up message to send in a few days if no response?"

---

## Merchant communication principles (merchant-facing drafts only)

1. **Lead with empathy when something has gone wrong — based on what the merchant has
   actually expressed.** Don't project impact or frustration they haven't raised.
2. **Be direct.** Bottom-line up front. Merchants are busy.
3. **Be honest.** Never overpromise, never bury bad news in vague language.
4. **Be specific about what's established.** Use concrete dates, times, IDs, and
   component names when referring to facts that are confirmed. Don't manufacture
   specificity about things that aren't.
5. **Own it when appropriate.** "We" not "the system" or "the process".
6. **Close the loop when possible.** A response should end with a clear next step or
   call to action *if one is established*. If no specific action is confirmed, reflect
   the current internal state honestly (see "Describing what's happening internally")
   and let that be the closure.
7. **Match their energy.** Frustrated merchants need empathy first. Routine updates
   can be efficient and warm.
8. **Distinguish merchant-facing from SE-facing actions.** Debugging findings often
   contain both: steps the merchant needs to take (adjust their integration, toggle
   a config) and steps the SE or other Payrails teams need to take (update a ticket,
   ask engineering, escalate). Only the merchant-facing steps belong in merchant
   drafts. SE-facing steps belong in Linear/Slack drafts, not the merchant message.

---

## Merchant response structure

For merchant communications, follow this structure:

```
1. Acknowledgement / context (1–2 sentences)
   - Reference what they asked, said, or are experiencing
   - Match what they've actually expressed, not what you assume

2. Core message (1–3 short paragraphs)
   - Deliver the main information, answer, or update based on established findings
   - Be specific about confirmed facts
   - Don't speculate or fill gaps with invented detail

3. Next steps (conditional, 1–3 bullets)
   - What Payrails will do, only if that's been decided
   - What the merchant needs to do, only if there's something for them to do
   - If no specific next steps are confirmed, simply reflect the current internal
     state accurately (see "Describing what's happening internally")

4. Closing (1 sentence)
   - Warm but professional sign-off
```

---

## Length guidelines (merchant-facing)

- **Slack / IM**: 1–4 sentences. Get to the point immediately.
- **Plain thread reply**: 1–3 short paragraphs. Structured and scannable.
- **Email**: 3–5 paragraphs max. Respect their inbox.
- **Status update during investigation**: as long as needed to be thorough, but
  structured with headers or bullets for scannability.
- **Leadership-level communication**: shorter is better. 2–3 paragraphs max.

---

## Tone spectrum (merchant-facing)

| Situation | Tone | Characteristics |
|-----------|------|-----------------|
| Good news (fix shipped, feature enabled) | Warm | Appreciative, forward-looking |
| Routine update | Professional | Clear, concise, informative, friendly |
| Technical answer | Precise | Accurate, structured, patient |
| Delay or missed timeline | Accountable | Honest, apologetic, focused on what's known |
| Bad news (won't-fix, feature sunset) | Candid | Direct, empathetic |
| Ongoing issue or outage | Measured | Transparent about what's known, reassuring without overpromising |
| Escalation response | Composed | Ownership-taking, grounded in established facts |

---

## Tone adjustments by relationship stage (merchant-facing)

**Newly onboarded merchant (0–3 months):**
- More formal and professional
- Extra context and explanation
- Build trust through reliability and responsiveness

**Established merchant (3+ months):**
- Warm and collaborative
- Can reference shared history
- More direct and efficient
- Show awareness of their integration priorities

**Frustrated or escalated merchant:**
- Extra empathy — based on what they've expressed
- Urgency in response time
- Shorter feedback loops — update even when there's nothing new

**Tenure unknown (Linear project not found, or merchant onboarded before ~2024):**
- Default to professional-but-warm
- Ask the user if they know the relationship stage, rather than guessing

---

## Writing style rules

**Do:**
- Use active voice ("We'll investigate" not "This will be investigated")
- Use "I" for personal commitments, "we" for team commitments
- Use the audience's terminology (merchant's terms for merchant drafts; team names
  for internal drafts)
- Include specific dates and times *only* if they've been established in prior
  conversation
- Break up long messages with headers or bullet points

**Don't:**
- Use corporate jargon ("synergy", "leverage", "paradigm")
- Deflect blame to other teams, systems, or processes
- Use passive voice to avoid ownership ("Mistakes were made")
- Include unnecessary hedging that undermines confidence
- CC people unnecessarily
- Use exclamation marks excessively — one per email maximum, if any
- Invent timelines, commitments, plans, or next steps that aren't established

---

## Situation-specific approaches (merchant-facing)

### Describing what's happening internally

Match the merchant-facing phrasing to the actual internal state. The response should
accurately reflect what Payrails is doing — not default to a generic "looking into it"
in every case.

Examples of distinct internal states and matching phrasings:

- SE investigating alone, nothing escalated → "I'm looking into it" / "We're looking
  into it"
- Issue escalated to another Payrails team or person → "We've raised this internally"
- New information added to an existing Linear ticket → "We've logged this in our
  ticket on this issue"
- A new Linear ticket was opened for this → "We've opened a ticket to track this"
- Reached out to the external provider (e.g. Adyen, Stripe) → "We've raised this with
  the provider"

These are examples, not a closed list. If the actual internal state doesn't fit any of
them, describe what's happening accurately in your own words. The rule is fidelity to
the real state, not picking from a menu.

Avoid using one phrasing when another is accurate — "looking into it" when a ticket
has been open for weeks sounds dismissive; "raised internally" when nothing has
actually been escalated sounds like overreach.

**Workflow note — state at send time, not draft time:**

The merchant-facing phrasing should reflect the internal state *at the time the
merchant receives the message*, not only the state at the moment the draft is
produced. Sometimes the SE drafts the response in parallel with taking the action
(raising internally, opening a ticket, reaching out to the provider), planning to
complete the action before sending.

In those cases, the draft may use the matching phrasing — but the "Notes for you"
section MUST list the pending action as a required pre-send step. For example:

- Draft uses "We've raised this internally"
- Internal notes include: "Verify before sending: this has not yet been raised
  internally. Do so before sending this draft."

This preserves honesty while supporting the real SE workflow.

---

### Answering a merchant question

- Lead with the direct answer if one is available
- Link to relevant Payrails documentation where applicable
- If a confirmed answer isn't available, describe the current internal state
  accurately (see "Describing what's happening internally") — no timeline, no
  speculation

### Responding to an integration issue

- If the merchant has mentioned impact on their work or expressed frustration,
  acknowledge it in one sentence. If they haven't, don't project impact they haven't
  raised.
- Describe what's known about the issue and the current internal state accurately
- If a workaround has already been identified — in the debugging session output, the
  linked Linear ticket, or the Plain thread — mention it. This skill does not search
  for or invent workarounds.
- If a specific update cadence has already been committed to, reflect that commitment

### Handling an escalation

- If the merchant has expressed frustration or framed this as severe, acknowledge it.
  If they haven't, don't manufacture severity.
- Describe the current internal state accurately
- Share any merchant-facing actionable information that's already been confirmed
- Keep internal detail internal — don't share SE-facing steps, Payrails team
  structures, or specific people working on the issue

### Delivering bad news (delay, won't-fix, feature sunset)

- Be direct — don't bury the news
- Explain the reasoning honestly if the reasoning is known and appropriate to share
- Acknowledge the impact on them if they've raised it
- If an alternative or next step has already been established, share it

### Sharing good news (fix shipped, feature enabled)

- Lead with the positive outcome
- Connect it to their specific use case if that connection is clear
- If there are concrete actions the merchant needs to take to make use of the fix,
  mention them
- Express appreciation for their patience if they'd been waiting

---

## Merchant response templates

### Acknowledging a reported bug or integration issue

```
Hi [Name],

Thank you for flagging this.

[If the merchant has described specific impact or frustration, acknowledge it here in
one sentence. Otherwise, skip this paragraph.]

[Describe the current internal state accurately — see "Describing what's happening
internally". Examples: "I'm looking into it" / "We've raised this internally" /
"We've opened a ticket to track this" / "We've logged this in our existing ticket".]
Here's what we know so far:
- [What's happening]
- [What's been confirmed about the cause, if anything]
- [Workaround, only if one has already been established elsewhere]

I'll come back to you with an update as we learn more.

If there are other details about what you're seeing that would help, please let me
know.

Best regards,
[Your name]
```

### Status update during investigation

```
Hi [Name],

Quick update on the [issue summary] we've been investigating.

**Where we are:** [Describe the current internal state accurately]
**What we've found so far:** [Concrete findings only; don't overclaim]
**Next step (if decided):** [Only include this line if a specific next action has
been decided; otherwise omit]

I'll come back to you as we make progress.

Thanks for your patience.

Best regards,
[Your name]
```

### Following up after silence

```
Hi [Name],

I wanted to check in on this — I sent over [what you sent] on [date] and wanted to
make sure it didn't get lost.

[Brief reminder of what's needed from them or what you're offering]

If now isn't a good time, no problem — just let me know when would be better and I'm
happy to pick this up again.

Best regards,
[Your name]
```

---

## Notes

- For the technical investigation itself, defer to `../payrails-debug/SKILL.md` or
  `../payrails-thread-debug/SKILL.md`. This skill sits downstream of those.
- Team routing (who owns platform vs SDK vs provider vs infra) lives in
  `../payrails-debug/references/payrails-knowledge.md`. Use it when filling in the
  "Target team" field of a Linear ticket or the recipient of an internal Slack message.
- If you draft something and realise mid-draft that the underlying diagnosis is
  uncertain, stop and raise that rather than papering over it with careful wording.
- If the user asks for drafts to multiple audiences in one session (e.g. merchant reply
  AND Linear ticket), produce them separately using the appropriate structure for each.