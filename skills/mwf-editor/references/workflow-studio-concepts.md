# Workflow Studio — Concept Reference

This file captures the conceptual model behind Payrails Workflow Studio, based on the official product docs. Use it to understand *what* a workflow is supposed to do so you can make sensible editing decisions — the JSON shape lives in `mwf-schema.md`.

## What a workflow represents

A workflow describes the full lifecycle of a payment: authorize → capture, cancel, refund, lookup, plus side concerns like fraud checks, 3DS, instrument creation, and notifications. Each top-level operation has its own **trigger** as an independent entry point. All these flows coexist in one MWF config.

The only supported workflow code today is `payment-acceptance`.

## The three step types (canvas semantics)

| Type | Canvas color | Role |
|---|---|---|
| **Trigger** | green | Entry point. Fires on an API call or system event. |
| **Action** | blue | Does real work (authorize, capture, refund, fraud check, 3DS, notify, etc.). |
| **Condition** | gray (or amber in our diagrams) | Branches flow based on rules. |

Notes:
- The Mermaid color scheme the skill uses (green trigger / blue action / amber condition) deliberately makes conditions amber rather than gray, so they visually pop as decision points. Keep this convention unless the user asks otherwise.
- A **terminal step** is one with no outgoing connections (the `Notify` action is always terminal).

## Connections and outcomes

Steps connect via **outcomes**:

- **Trigger → next step**: direct connection. In JSON this is `params.nextActions` (a flat array) containing one or more `addNextStep` entries.
- **Action → next step**: via named outcomes. In JSON, `params.nextActions` is an object keyed by outcome name.
- **Condition → next step**: via matching rules + a default. In JSON, `params.rules[].actions` and `params.defaultActions`.

### Action outcomes

Payment actions (Authorize, Capture, Cancel, Refund) have four outcomes:

| Outcome | When it fires | JSON key |
|---|---|---|
| **Completed** | Operation finished (success or failure — check with a condition) | `onCompleted` |
| **Paused** | Operation is waiting for an external event (e.g., 3DS challenge, async provider) | `onPaused` |
| **Requested** | Operation was submitted and awaits async response | `onRequested` |
| **Updated** | A later status update arrived for an already-completed operation | `onUpdated` |

Other action types have fewer outcomes:
- **Fraud Check, Fraud Update, 3DS, Create Instrument, Provision Network Token, Lookup** — Completed, Paused, Requested (no Updated).
- **Notify** — terminal, no outcomes at all.

### Default ("Everything else") branch

Every condition needs a fallback. In JSON this is `defaultActions`. If it's missing, the flow dead-ends — flag this when validating.

Rules are evaluated in order; the first match wins. Multiple checks inside one rule combine with AND; separate rules combine with OR.

## Available triggers

### Client API triggers (fired by client-side integration)
- `Start authorize` → `POST /authorize`

### Merchant API triggers (fired by backend calls)
- `Start capture` → `POST /capture`
- `Start cancel` → `POST /cancel`
- `Start refund` → `POST /refund`
- `Start order update` → `POST /orderUpdate` — used to relay order lifecycle events (shipped, cancelled, etc.) to fraud providers.
- `Start lookup` → `POST /lookup`

### Event triggers (fired by system events)
- `Handle dispute update` — on `DisputeUpdated`. Used to route dispute notifications to the correct fraud vendor for updating their records.
- `Handle payment status update` — on `PaymentStatusUpdated`. Used to process async refund/cancel/capture status changes arriving from providers after the original flow completed.

Event triggers use `params.type: "event"` with `params.params.name` identifying the event. They typically route to a condition step that inspects the event payload and fans out to the appropriate handler.

## Available actions (reference)

### Payment actions (all have Completed/Paused/Requested/Updated outcomes)
| Action | Provider selection | Purpose |
|---|---|---|
| **Authorize** | Yes (Payment) | Reserve funds on the customer's instrument. Has a **3DS mode** setting (Default / Force / Skip). |
| **Capture** | No | Move authorized funds to the merchant. |
| **Cancel** | No | Void a prior authorization before capture. |
| **Refund** | No | Return funds to the customer after capture. |

### Fraud & risk actions (Completed/Paused/Requested)
| Action | Provider selection | Purpose |
|---|---|---|
| **Fraud Check** | Yes (Fraud) | Risk assessment before authorize. |
| **Fraud Score** | Yes (Fraud) | Numeric risk scoring — pre-auth (before authorize) and post-auth (after successful authorize). Returns a `decision` field (`Allow`, `Prevent`, `NoDecision`, `Challenge`) and may include exemption indicators. |
| **Fraud Update** | Yes (Fraud) | Send transaction outcome back to the fraud provider. Used on order updates and dispute events. |
| **3DS** | Yes (3DS) | Handle 3D Secure authentication — typically reached via the Authorize "Paused" outcome. |

### Instrument & token actions (Completed/Paused/Requested)
| Action | Provider selection | Purpose |
|---|---|---|
| **Create Instrument** | No | Create or retrieve a stored payment instrument (tokenization). |
| **Provision Network Token** | Yes (Network Token) | Provision a network token from the card network. |

### Other actions
| Action | Outcomes | Purpose |
|---|---|---|
| **Lookup** | Completed/Paused/Requested | Look up available payment options. |
| **Notify** | (none — terminal) | Send a notification event to the merchant backend. |

## 3DS mode interaction

On the Authorize action, `settings.threeDSMode` controls 3DS behavior:
- **Default** — provider/scheme decides. Recommended default.
- **Force** — always trigger 3DS (used for compliance, SCA-strict paths, or when you know the path requires it).
- **Skip** — never trigger 3DS (shifts fraud liability to the merchant; avoid except for low-risk flows).

When Default or Force produces a "Paused" outcome because 3DS is required, the flow should have `onPaused → Condition (check paused reason) → 3DS action → Authorize (retry)`.

It is common to see **two parallel Authorize branches** in the same workflow:
- One with `threeDSMode: "Force"` + `instrumentCreationDisabled: true` for flows that need forced 3DS.
- One with `threeDSMode: "Skip"` (or Default) for flows that don't.

When you see `force3DSAuthorize` / `skip3DSAuthorize` / `decide3DSpath` step codes, that's the pattern — don't flatten them.

## Rule operators (condition reference)

Comparison: `=`, `!=`, `>`, `>=`, `<`, `<=`
List: `IN`, `NOT IN`, `IS ONE OF`, `NOT IS ONE OF`
Text: `CONTAINS`, `NOT CONTAINS`, `STARTS WITH`, `NOT STARTS WITH`, `ENDS WITH`, `NOT ENDS WITH`

Notes:
- Text comparisons are case-sensitive.
- Missing fields silently don't match → fall through to the default branch. Tell the user if this might be biting them.
- Values for list operators are comma-separated in the UI, arrays in JSON.

## Data mappings

Each `addNextStep` can include a `mapping` array of `{from, to}` pairs that rewire fields from the current execution context into the next step's input. Workflow Studio auto-generates sensible defaults when you draw a connection in the UI; you only need to touch mappings when the next step needs a specific field renamed or pulled from a non-standard path.

When inserting a new step between two existing steps, preserve any mappings that were feeding data into the downstream step — move them to the new edge so the data still reaches its destination.

## Delays

A connection can include a time-based delay — useful for scheduled captures (capture 24h after authorize), retry backoff, and notification throttling. Delays live on the edge/next-step action, not on the target step.

## Execution statuses

Action steps can emit execution status codes for monitoring (e.g., `authorizeRequested`, `authorizeSuccessful`, `captureFailed`). These appear as `addWorkflowExecutionStatus` entries in `nextActions` alongside `addNextStep`. When adding a new terminal path, add an appropriate status event so the merchant's monitoring stays accurate.

## Key design principles (from the Patterns docs)

- **Notify on every terminal path** — both success and failure branches should end with a Notify step so the merchant backend is informed.
- **Always have an "Everything else" branch** — prevents dead-end executions.
- **Group similar payment methods** — use `IS ONE OF ["applePay", "googlePay"]` instead of two rules with identical downstream logic.
- **Per-step provider overrides are allowed** — the same action (e.g., Authorize) can be duplicated with different provider configs per branch.
- **Keep conditions simple** — split large rule sets into multiple sequential conditions when it improves readability.
- **Workflows flow left-to-right with no loops**, with one exception: a "retry" connection back to a previous step (usually with a delay) is allowed.
