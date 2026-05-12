# MWF Schema Reference

This file documents the structure of Payrails Modular Workflow (MWF) JSON configurations. Read this before constructing or modifying step `params` blocks — the shapes are specific and getting them wrong will produce a config that the workflow engine rejects.

## Top-level structure

```json
{
  "uiConfig": {
    "edges": [],
    "nodes": [],
    "overrideAutoLayout": false,
    "visibleActionStatusesByStepCode": {}
  },
  "steps": []
}
```

- **uiConfig.edges** — routing edges for the canvas. Each `id` follows `<fromStepCode>-<toStepCode>` and optionally a `-<suffix>` when multiple edges exist between the same pair (e.g., `authorize-sendActionCompletedNotification-1`). `vertices` is an array of `{x, y}` waypoints for rendering; empty `[]` is fine for a straight line.
- **uiConfig.nodes** — canvas positions. One entry per step. `id` equals the step `code`. `position` is `{x, y}`.
- **uiConfig.overrideAutoLayout** — usually `false`. Set true only if the user has hand-placed nodes.
- **uiConfig.visibleActionStatusesByStepCode** — map of step code → list of action statuses shown for that step. When adding a new action step, you can omit or leave empty; the engine will fill defaults.
- **steps** — the actual workflow. Order in the array is the authoring order, not execution order. Execution follows `nextActions`.

## Step shape (common fields)

Every step has:

```json
{
  "name": "Human-readable name",
  "code": "uniqueStepCode",
  "type": "trigger" | "action" | "condition",
  "params": { ... }
}
```

- `code` is the step's unique identifier. Use camelCase. Reference this from `nextActions.params.code`, from edge ids, and from node ids.
- `name` is only for display; be descriptive.
- `type` determines the shape of `params`.

## Step type: trigger

Entry point into a workflow. Typically one per "action" (authorize, capture, cancel, refund, lookup).

```json
{
  "name": "Start Authorize",
  "code": "triggerAuthorize",
  "type": "trigger",
  "params": {
    "type": "clientAPI",
    "params": {
      "path": "/authorize",
      "method": "POST"
    },
    "responseMapping": [
      { "from": "output.name", "to": "name" },
      { "from": "output.executedAt", "to": "executedAt" },
      { "from": "output.actionId", "to": "actionId" },
      { "from": "output.workspaceId", "to": "workspaceId" },
      { "from": "output.links", "to": "links" }
    ],
    "nextActions": [
      {
        "type": "addWorkflowExecutionStatus",
        "params": { "status": "authorizeRequested" }
      },
      {
        "type": "addNextStep",
        "params": { "code": "checkCreateInstrumentSupport" }
      }
    ],
    "settings": {}
  }
}
```

Notes:
- `params.type` is the trigger type. `clientAPI` is the most common (invoked via Payrails client API).
- `params.params` contains trigger-specific config (e.g., path + method for clientAPI).
- `nextActions` is a flat array of actions executed when the trigger fires. Order matters.
- `addWorkflowExecutionStatus` emits a status event. `addNextStep` routes to the next step.
- `responseMapping` defines what fields to map from the response back into the execution context.

## Step type: action

Performs an operation (authorize a payment, create an instrument, send a notification, etc.).

### Simple action (single branch)

```json
{
  "name": "Create or Get Instrument",
  "code": "createOrGetInstrument",
  "type": "action",
  "params": {
    "type": "createInstrument",
    "nextActions": {
      "onCompleted": [
        {
          "type": "addNextStep",
          "params": { "code": "checkInstrumentResult" }
        }
      ]
    },
    "settings": {}
  }
}
```

### Action with multiple lifecycle hooks

```json
{
  "name": "Force 3DS path - Authorize Payment",
  "code": "authorize",
  "type": "action",
  "params": {
    "type": "authorize",
    "expiration": "PT30M",
    "settings": {
      "threeDSMode": "Force",
      "instrumentCreationDisabled": true
    },
    "nextActions": {
      "onPaused":    [ { "type": "addNextStep", "params": { "code": "checkAuthorizePausedReason" } } ],
      "onCompleted": [ { "type": "addNextStep", "params": { "code": "checkAuthorizeResult" } } ],
      "onUpdated":   [ { "type": "addNextStep", "params": { "code": "checkAuthorizeUpdatedResult" } } ]
    }
  }
}
```

Notes:
- `params.type` identifies the action. Observed values: `authorize`, `capture`, `cancel`, `refund`, `createInstrument`, `lookup`, `notify`, and fraud/3DS variants. See `workflow-studio-concepts.md` for the full catalog.
- `nextActions` is an **object** keyed by lifecycle hook, unlike triggers and conditions where it's an array.
  - `onCompleted` — fires when the action finishes (success or failure — check with a condition).
  - `onPaused` — fires when the action pauses (e.g., waiting on 3DS challenge, async provider flow).
  - `onRequested` — fires when the action was submitted to a provider and is awaiting an async response.
  - `onUpdated` — fires on a late status update for an already-completed operation (reconciliation). Only on payment actions (Authorize/Capture/Cancel/Refund).
- `settings` holds action-specific config. For Authorize, this includes `threeDSMode` (`"Default"` / `"Force"` / `"Skip"`) and `instrumentCreationDisabled`. Other actions have their own setting shapes (retry policies, provider config ids, etc.).
- `expiration` is ISO 8601 duration (`PT30M` = 30 minutes). Used for paused/async actions.
- **Notify is terminal** — its `nextActions` is typically empty or absent; don't add downstream steps.

## Step type: condition

Branching logic based on runtime values.

```json
{
  "name": "Should Create Instrument",
  "code": "checkCreateInstrumentSupport",
  "type": "condition",
  "params": {
    "rules": [
      {
        "name": "If Payment Method Is Card or Wallet",
        "condition": {
          "field": "output.authorize.paymentComposition[0].paymentMethodCode",
          "operator": "IS ONE OF",
          "value": ["card", "payPal", "googlePay", "applePay"]
        },
        "actions": [
          {
            "type": "addNextStep",
            "params": {
              "code": "createOrGetInstrument",
              "mapping": [
                { "from": "output.authorize.scope", "to": "scope" },
                { "from": "output.authorize.paymentComposition[0].paymentInstrumentId", "to": "id" }
              ]
            }
          }
        ]
      }
    ],
    "defaultActions": [
      {
        "type": "addNextStep",
        "params": { "code": "authorize" }
      }
    ],
    "settings": {}
  }
}
```

Notes:
- `rules` are evaluated in order. First matching rule wins — its `actions` are executed and remaining rules are skipped.
- Each rule has `name` (for display), `condition`, and `actions`.
- `condition.operator` supports `=`, `!=`, `>`, `<`, `>=`, `<=`, `IS ONE OF`, `IS NOT ONE OF`, `CONTAINS`, `EXISTS`, `NOT EXISTS`.
- `condition.field` is a dot-path into the execution context (e.g., `output.authorize.result`, `success`).
- `defaultActions` run if no rule matches. If omitted, the flow ends at this condition — usually you want at least a default.
- Actions inside rules can include `mapping` to transform values into the next step's expected fields.

### Compound AND conditions

When a rule needs to match on multiple fields simultaneously, the `condition` object uses a **binary tree** structure with `left`, `operator: "AND"`, and `right`. Each leaf has `{field, operator, value}`. Nest deeper ANDs by putting another AND node in `right`.

```json
{
  "name": "Skip 3DS for cards, if BIN is in allowlist",
  "condition": {
    "left": {
      "field": "success",
      "operator": "=",
      "value": true
    },
    "operator": "AND",
    "right": {
      "left": {
        "field": "output.paymentMethod",
        "operator": "=",
        "value": "card"
      },
      "operator": "AND",
      "right": {
        "field": "output.data.bin",
        "operator": "IS ONE OF",
        "value": ["400127", "400528", "40301504"]
      }
    }
  },
  "actions": [ ... ]
}
```

This is the shape used in production. Do **not** use a flat `conditions: [...]` array — the engine expects the nested binary tree.

### Multi-target fan-out from a single rule

A rule's `actions` array can contain **multiple** `addNextStep` entries to route to two or more steps simultaneously. This is common for patterns like "retry the authorize AND notify the merchant at the same time" or "cancel the payment AND send a notification":

```json
{
  "name": "Decision: Prevent",
  "condition": { "field": "output.fraudScoreResponse.decision", "operator": "=", "value": "Prevent" },
  "actions": [
    { "type": "addWorkflowExecutionStatus", "params": { "status": "authorizeFailed" } },
    { "type": "addNextStep", "params": { "code": "sendActionCompletedNotification", "mapping": [{"from": "output.actionId", "to": "actionId"}] } },
    { "type": "addNextStep", "params": { "code": "cancel", "mapping": [{"to": "reasonDescription", "value": "Automatic Cancel due to fraud decision Prevent"}] } }
  ]
}
```

When a rule fans out, each `addNextStep` target executes — the flow branches into parallel paths. Add corresponding `uiConfig.edges` for each target with `-1`, `-2` suffixes.

## nextActions action types

Across triggers, actions, and conditions, the `nextActions`/`actions`/`defaultActions` arrays use these action types:

| `type` | Purpose | `params` |
|---|---|---|
| `addNextStep` | Route to another step | `code` (required), `mapping` (optional), `delay` (optional) |
| `addWorkflowExecutionStatus` | Emit a status event | `status` (string) |
| `addError` | Record an error on the execution | `errorCode`, `message` |

### Mapping types

`mapping` inside `addNextStep` supports two forms:

- **Field-to-field** (rewiring): `{"from": "output.authorize.scope", "to": "scope"}` — copies a value from the execution context into the next step's input.
- **Static value injection**: `{"to": "meta.customer.country.code", "value": "SE"}` — injects a constant value with no `from` field. Used for injecting country codes, reason descriptions, risk exemption indicators, boolean flags, etc.

Both forms can be mixed in the same `mapping` array.

### Delays on edges

`addNextStep` can include a `delay` field with an ISO 8601 duration string to schedule the next step for later execution:

- `"P1D"` — 1 day delay (common for scheduled auto-capture)
- `"P0D"` — zero delay, meaning "next provider attempt" / immediate retry (the engine still treats this as an async re-entry)
- `"PT5M"` — 5 minute backoff

```json
{ "type": "addNextStep", "params": { "code": "capture", "delay": "P1D", "mapping": [{"to": "reasonDescription", "value": "Automatic Capture on successful authorization"}] } }
```

### Execution status conventions

Every terminal branch should emit an execution status via `addWorkflowExecutionStatus` so merchant monitoring stays accurate. The naming convention is `{action}{Outcome}`:

| Status | When |
|---|---|
| `authorizeRequested` | Trigger fires |
| `authorizeSuccessful` | Auth success (including post-fraud-check success) |
| `authorizeFailed` | Auth failure, fraud prevent, instrument failure |
| `authorizePending` | Paused for 3DS or external action |
| `captureSuccessful` / `captureFailed` | Capture result |
| `cancelSuccessful` / `cancelFailed` | Cancel result |
| `refundRequested` | Refund trigger fires |
| `refundSuccessful` / `refundFailed` | Refund result |

Updated-result conditions also emit statuses (e.g., a previously-failed auth that becomes successful emits `authorizeSuccessful`).

## Edge id convention

Edges use `<fromCode>-<toCode>` as their id. If there are multiple edges between the same pair of steps (e.g., an action with both `onCompleted` and `onPaused` routing to the same downstream step), suffix with `-1`, `-2`, etc.

Examples:
- `triggerAuthorize-checkCreateInstrumentSupport`
- `authorize-sendActionCompletedNotification`
- `authorize-sendActionCompletedNotification-1` (second edge between same pair)
- `checkCreateInstrumentSupport-authorize-default` (the default branch of a condition — the `-default` suffix is a common convention when you want to make the branch semantics explicit)

## Blank template (for new workflows)

Minimum viable MWF with one trigger, one action, one notification:

```json
{
  "uiConfig": {
    "edges": [
      { "id": "triggerMyAction-myAction", "vertices": [] },
      { "id": "myAction-sendActionCompletedNotification", "vertices": [] }
    ],
    "nodes": [
      { "id": "triggerMyAction", "position": { "x": 50, "y": 400 } },
      { "id": "myAction", "position": { "x": 700, "y": 400 } },
      { "id": "sendActionCompletedNotification", "position": { "x": 1400, "y": 400 } }
    ],
    "overrideAutoLayout": false,
    "visibleActionStatusesByStepCode": {}
  },
  "steps": [
    {
      "name": "Start My Action",
      "code": "triggerMyAction",
      "type": "trigger",
      "params": {
        "type": "clientAPI",
        "params": { "path": "/my-action", "method": "POST" },
        "responseMapping": [],
        "nextActions": [
          { "type": "addNextStep", "params": { "code": "myAction" } }
        ],
        "settings": {}
      }
    },
    {
      "name": "My Action",
      "code": "myAction",
      "type": "action",
      "params": {
        "type": "myActionType",
        "nextActions": {
          "onCompleted": [
            { "type": "addNextStep", "params": { "code": "sendActionCompletedNotification" } }
          ]
        },
        "settings": {}
      }
    },
    {
      "name": "Send Action Completed Notification",
      "code": "sendActionCompletedNotification",
      "type": "action",
      "params": {
        "type": "sendNotification",
        "nextActions": { "onCompleted": [] },
        "settings": {}
      }
    }
  ]
}
```

## Common editing patterns

**Insert a condition step between A and B:**
1. Add a new condition step with `code: "checkX"` routing to B in a rule and to a fallback in `defaultActions`.
2. Change A's `nextActions.addNextStep.code` from `B` to `checkX`.
3. Add `uiConfig.nodes` entry for `checkX` at a position between A and B.
4. Remove edge `A-B`, add edges `A-checkX` and `checkX-B` (plus `checkX-<fallback>`).

**Add a retry branch to an action:**
1. Typically done by adding a condition step on the action's `onCompleted` that checks `success` and routes back to the action on failure (with some retry counter in mapping), or forward on success.

**Remove a step:**
1. Find all steps whose `nextActions`/`actions`/`defaultActions` reference the removed step's code. Rewire each to the removed step's downstream target (or to the upstream's next logical hop).
2. Delete the step from `steps[]`, its `uiConfig.nodes` entry, and all `uiConfig.edges` mentioning its code.
