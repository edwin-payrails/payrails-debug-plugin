# MWF Patterns Reference

Reusable patterns for common payment workflow scenarios. Use these as starting points when the user asks for a flow that matches one of these shapes. Each pattern describes the intent, the step graph, and the MWF-specific wiring to produce.

## 1. Standard payment acceptance flow

**Intent:** full payment lifecycle — authorize, capture, cancel, refund, lookup — each as an independent trigger chain, ending in Notify for every terminal path.

```
Start authorize ─► [optional: Check instrument support ─► Create Instrument]
                   ─► Authorize
                       ├── Completed ─► Check authorize result ─► Notify (success or failure)
                       ├── Paused    ─► Check paused reason ─► 3DS ─► Authorize (retry)
                       ├── Requested ─► Notify (pending)
                       └── Updated   ─► Check updated result ─► Notify (reconciliation)

Start capture ─► Capture ─► Check capture result ─► Notify
Start cancel  ─► Cancel  ─► Check cancel result  ─► Notify
Start refund  ─► Refund  ─► Check refund result  ─► Notify
Start lookup  ─► Lookup  ─► (return options, terminal)
```

**Wiring tips:**
- Each of the 5 triggers is a separate entry point in `steps[]` — put them near the top of the array for readability.
- Result-checking conditions can be shared across success/failure handling if the logic is identical (e.g., `sendActionCompletedNotification` is commonly a single node reached from multiple branches).
- Status assignments via `addWorkflowExecutionStatus` should happen on every terminal branch.

## 2. Authorize with fraud check

**Intent:** run a fraud provider check before actually authorizing the payment; block risky transactions, allow the rest through.

```
Start authorize ─► Fraud Check
                   ├── Completed ─► Check fraud decision
                   │                 ├── Approved ─► Authorize ─► ... (normal flow)
                   │                 ├── Review   ─► Notify (manual review queue)
                   │                 └── Decline  ─► Notify (declined)
                   └── Requested ─► Notify (pending)
```

**Wiring tips:**
- Insert `fraudCheck` action between `triggerAuthorize` and `authorize`. Update the trigger's `addNextStep.code` to point at `fraudCheck` (or at a pre-fraud condition step if you want to skip for certain methods).
- Add a condition step (`checkFraudDecision`) on `fraudCheck`'s `onCompleted` with rules for `approved` / `review` / `decline`.
- Fraud Check uses provider selection (type: Fraud), so preserve `settings.providerConfigId` if present.

## 3. Conditional routing by payment method

**Intent:** send different payment methods through different paths (e.g., card goes through fraud check + forced 3DS, wallets skip 3DS, BNPL has its own flow).

```
Start authorize
    │
    ▼
Decide path (condition on paymentMethodCode)
    ├── card                         ─► Fraud Check ─► Authorize (3DS Force)
    ├── applePay, googlePay          ─► Authorize (3DS Skip)
    ├── klarna, afterpay             ─► Authorize (BNPL settings)
    └── everything else              ─► Authorize (generic)
```

**Wiring tips:**
- The decider is a `condition` step using `IS ONE OF` for grouped methods.
- Each branch routes to a different `authorize` step (duplicated action with distinct `code`s like `force3DSAuthorize`, `skip3DSAuthorize`, `authorize`). In the uploaded examples, this is exactly the `force3DSAuthorize` / `skip3DSAuthorize` pattern.
- Each per-branch Authorize needs its own downstream result-checking condition, or they can converge on a shared `checkAuthorizeResult`.

## 4. Auto-capture with delay

**Intent:** automatically capture funds after a successful authorization, optionally after a delay (e.g., 24h for order review).

```
Authorize ─► Check authorize result
              ├── Success ─► [delay 24h] ─► Capture ─► Check capture result ─► Notify
              └── Otherwise ─► Notify (auth failed)
```

**Wiring tips:**
- Add a `delay` on the `addNextStep` from the success branch of `checkAuthorizeResult` to the `capture` step.
- This means no separate `triggerCapture` is needed for the auto-captured path (but keep the manual `triggerCapture` entry point for merchant-initiated captures).
- The Capture action doesn't need provider selection — it uses the same provider as the original Authorize.

## 5. Retry on failure

**Intent:** retry a failed action (authorize, capture, etc.) a bounded number of times with backoff.

```
Authorize ─► Check authorize result
              ├── Retryable (error is transient, retry count < 3) ─► [delay 5m] ─► Authorize
              ├── Success ─► Notify
              └── Otherwise ─► Notify (failed, non-retryable)
```

**Wiring tips:**
- Create a self-loop: the retry edge points from `checkAuthorizeResult` back to `authorize` (use a suffix like `checkAuthorizeResult-authorize-retry` on the edge id for clarity).
- Use a condition rule that checks both retryability (e.g., error code is a timeout) AND retry count (`retryCount <= 3`).
- Add a delay on the retry edge to back off.
- The workflow engine tracks retry count internally; you don't need to manage it in the JSON.

## 6. Forced vs skipped 3DS (parallel branches)

**Intent:** some flows must force 3DS (SCA, compliance, high-risk methods), others should skip it. Keep them as parallel branches.

```
Start authorize ─► Decide 3DS path (condition)
                     ├── Force 3DS ─► [Force3DS: Create Instrument ─► Authorize (threeDSMode=Force)]
                     └── Skip 3DS  ─► [Skip3DS:  Create Instrument ─► Authorize (threeDSMode=Skip)]
```

**Wiring tips:**
- This produces step codes like `decide3DSpath`, `force3DSCreateOrGetInstrument`, `force3DSAuthorize`, `skip3DSCreateOrGetInstrument`, `skip3DSAuthorize`. Preserve the naming when editing.
- Each Authorize sets a distinct `settings.threeDSMode` (`"Force"` or `"Skip"`).
- The two branches can have separate result-checking conditions (`force3DSCheckInstrumentResult`, `skip3DSCheckInstrumentResult`) that ultimately converge on a shared downstream step.

## 7. Updated-outcome handling (reconciliation)

**Intent:** handle late status updates from a provider (e.g., an authorization that initially succeeded but later got reversed).

```
Authorize
   └── Updated ─► Check updated result
                    ├── Previously failed, now successful ─► Notify (corrected to success)
                    ├── Previously successful, now failed ─► Notify (reversal)
                    └── Everything else ─► (log, no action)
```

**Wiring tips:**
- The `Updated` outcome appears as `onUpdated` in the action's `nextActions` object.
- Typically routes to a dedicated condition step like `checkAuthorizeUpdatedResult` → a dedicated notification step `sendActionUpdatedNotification` (separate from `sendActionCompletedNotification`).

## 8. Notification fan-out

**Intent:** all terminal paths should end in a Notify step so the merchant backend is informed. Multiple upstream steps converge on the same Notify.

```
Check authorize result ──┐
Check capture result   ──┼──► sendActionCompletedNotification (single node)
Check cancel result    ──┤
Check refund result    ──┘
```

**Wiring tips:**
- Reuse a single `sendActionCompletedNotification` step across all lifecycle flows (authorize/capture/cancel/refund). Do not duplicate it per flow.
- For the `Updated` outcome, use a separate `sendActionUpdatedNotification` to distinguish reconciliation events.
- In `uiConfig.edges`, multiple incoming edges to the same notify step get `-1`, `-2`, ... suffixes to stay unique.

## 9. Multi-vendor fraud scoring (pre-auth + post-auth)

**Intent:** Route transactions to different fraud score providers based on the merchant/shop, run a pre-auth fraud check before authorize, and optionally run a post-auth fraud update after successful authorization. If the fraud provider rejects, auto-cancel the payment.

```
Start authorize ─► Create Instrument ─► Check instrument result
    ─► Check if eligible for fraud score (condition on merchant/shop)
         ├── Vendor A eligible (AND: paymentMethod + shop code) ─► Pre-Auth Fraud Score (Vendor A)
         ├── Vendor B eligible (paymentMethod match)            ─► Pre-Auth Fraud Score (Vendor B)
         └── Not eligible                                       ─► Authorize (Default 3DS)
    ─► Check pre-auth fraud score result
         ├── Prevent                  ─► Notify (declined)
         ├── Allow + Low Value        ─► Authorize (Skip 3DS, exemption=lowValue)
         ├── Allow + TRA              ─► Authorize (Skip 3DS, exemption=transactionRiskAnalysis)
         ├── NoDecision / Challenge   ─► Authorize (Force 3DS)
         ├── Timeout / Error          ─► Authorize (Force 3DS, no post-auth)
         └── Fraud Failed             ─► Notify (error)

Post-auth path (after successful authorize):
    Check authorize result
         ├── Success ─► Post-Auth Fraud Score (vendor-matched)
         │               ├── Prevent ─► Notify + Cancel (auto)
         │               └── Allow   ─► Notify + Schedule Capture
         └── Failed  ─► Retry or Notify
```

**Wiring tips:**
- Pre-auth fraud score steps are duplicated per vendor with distinct codes: `preAuthFraudScoreVendorA`, `preAuthFraudScoreVendorB`. Same for post-auth: `postAuthFraudScoreVendorA`, `postAuthFraudScoreVendorB`.
- The eligibility condition uses AND compound conditions (merchant shop code + payment method).
- Post-auth success branches fan out to both `sendActionCompletedNotification` AND `scheduleCaptureByPaymentMethod`.
- Fraud prevention after post-auth fans out to both `sendActionCompletedNotification` AND `cancel` (with static value mapping: `{to: "reasonDescription", value: "Automatic Cancel due to fraud decision Prevent"}`).
- The authorize step after fraud scoring uses `settings.instrumentCreationDisabled: true` since the instrument was already created.
- Use `meta.risk.exemptionIndicator` static value mappings (`lowValue`, `transactionRiskAnalysis`) when routing to authorize variants based on fraud decisions.

## 10. Scheduled capture by payment method

**Intent:** After successful authorization, auto-capture with method-specific timing — e.g., Klarna requires instant capture, while card payments use a 24h delay.

```
Check authorize result
    ├── Success ─► Schedule capture by payment method (condition)
    │               ├── Klarna variants (instant)   ─► Capture (no delay)
    │               └── Everything else              ─► Capture (delay P1D)
    └── Failed  ─► Notify
```

**Wiring tips:**
- The condition uses `paymentMethodCode IS ONE OF ["klarna", "klarnaPayNow", "klarnaPayLater", "klarnaPayOverTime"]` for instant capture.
- Delay is specified on the `addNextStep` params: `"delay": "P1D"` for the default branch.
- Both branches use static value mapping to set `reasonDescription` (e.g., `"Automatic Capture on successful authorization"`).
- The success branch of `checkAuthorizeResult` often fans out to BOTH `sendActionCompletedNotification` AND `scheduleCaptureByPaymentMethod` simultaneously.

## 11. Smart retry with simultaneous notification

**Intent:** On authorization failure, retry with the next PSP while simultaneously notifying the merchant of the intermediate failure. This gives the merchant visibility without waiting for the final outcome.

```
Check authorize result
    ├── Success               ─► Notify (success)
    ├── Failed + retryable    ─► [Notify (intermediate failure)] + [Authorize (retry, delay P0D)]
    └── Failed (terminal)     ─► Notify (final failure)
```

**Wiring tips:**
- The retry rule's `actions` array contains TWO `addNextStep` entries — one to `sendActionCompletedNotification` and one back to the authorize step.
- Use `delay: "P0D"` on the retry `addNextStep` — this signals "next provider attempt" to the engine.
- The retry `addNextStep` carries a mapping to pass through the instrument ID: `{from: "output.results[0].paymentInstrumentId", to: "paymentComposition[0].paymentInstrumentId"}`.
- AND compound conditions distinguish retryable failures (e.g., specific error codes, attempt count limits) from terminal failures.
- Add `uiConfig.edges` for both the retry loop and the notification path, with suffix conventions like `checkAuthorizeResult-authorize-retry` and `checkAuthorizeResult-sendActionCompletedNotification-1`.

## 12. Event-driven payment status handling

**Intent:** Handle external payment status updates (refund/cancel/capture events from providers) and dispute events that arrive asynchronously via event triggers.

```
Handle Payment Status Updated (event trigger)
    ─► Check external payment event (condition)
         ├── refund + successful     ─► Notify (status: refundSuccessful)
         ├── refund + failed         ─► Notify (status: refundFailed)
         ├── cancel + successful     ─► Notify (status: cancelSuccessful)
         ├── cancel + failed         ─► Notify (status: cancelFailed)
         ├── capture + successful    ─► Notify (status: captureSuccessful)
         └── capture + failed        ─► Notify (status: captureFailed)

Handle Dispute Updated (event trigger)
    ─► Check last authorize provider (condition)
         ─► Route dispute fraud update (condition on vendor)
              ├── Vendor A shops ─► Fraud Update (Vendor A)
              └── Default        ─► Fraud Update (Vendor B)
              ─► Notify
```

**Wiring tips:**
- Event triggers use `params.type: "event"` with `params.params.name` set to `"PaymentStatusUpdated"` or `"DisputeUpdated"`.
- The `checkExternalPaymentEvent` condition uses AND compound conditions combining action type (refund/cancel/capture) with success/failure status.
- Each branch emits the appropriate `addWorkflowExecutionStatus` and routes to notification with `{from: "output.actionId", to: "actionId"}` mapping.
- Dispute handling can involve multi-step routing: first identify the last authorize provider, then route to the vendor-specific fraud update action.

## 13. BIN-based and flag-based 3DS routing (post-instrument)

**Intent:** After instrument creation, decide the 3DS path based on card BIN lists, country mismatch, or merchant-supplied risk flags rather than (or in addition to) the simple payment-method-based routing.

```
Check instrument result
    ├── Customer ≠ issuer country          ─► Authorize (Force 3DS, flag: force3DS=true)
    ├── Card BIN in allowlist              ─► Authorize (Skip 3DS, flag: force3DS=false)
    ├── meta.risk.force3DS = false         ─► Authorize (Skip 3DS)
    ├── meta.risk.force3DS = true          ─► Authorize (Force 3DS)
    ├── Success (default cards)            ─► Authorize (Default 3DS)
    └── Instrument failed                  ─► Notify (failure)
```

**Wiring tips:**
- Uses three separate authorize action steps: `authorizeWithout3DS` (Skip), `authorizeWith3DS` (Force), `authorize` (Default), each with its own `checkResult` condition downstream.
- BIN-based rules use AND conditions: `success = true AND output.paymentMethod = "card" AND output.data.bin IS ONE OF [...]`.
- Static value mappings inject `{to: "meta.risk.force3DS", value: true/false}` alongside the instrument ID mapping.
- Country mismatch rules use `NOT` operator: `output.data.issuerCountry NOT = output.data.customerCountry` (or equivalent field paths).
- Each authorize variant has its own result-checking condition, but retry-on-failure rules can cross-route between variants (e.g., failed Force 3DS retries through Skip 3DS for specific error codes like fraud decline or visa prepaid anonymous).

## 14. Order Update with vendor-routed fraud update

**Intent:** When a merchant sends an order update (e.g., order shipped, order cancelled), route the fraud update notification to the correct fraud vendor based on the shop code.

```
Start Order Update (clientAPI trigger, POST /orderUpdate)
    ─► Check shop code (condition)
         ├── Shop codes for Vendor A    ─► Fraud Update (Vendor A) ─► Notify
         └── Everything else            ─► Fraud Update (Vendor B) ─► Notify
```

**Wiring tips:**
- The `triggerOrderUpdate` uses `params.type: "clientAPI"` with `params.params: {path: "/orderUpdate", method: "POST"}`.
- The shop code condition uses `IS ONE OF` with a list of shop identifiers.
- Each fraud update step uses `params.type: "fraudUpdate"` and routes `onCompleted` to `sendActionCompletedNotification`.
- The mapping from the condition passes `{from: "output.fraudUpdate.status", to: "orderStatus"}` to the fraud update step.
