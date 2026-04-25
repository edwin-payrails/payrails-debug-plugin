# Payrails Platform Knowledge

## Table of Contents
1. [API Basics](#api-basics)
2. [Common Error Patterns](#common-error-patterns)
3. [Provider-Specific Gotchas](#provider-specific-gotchas)
4. [Team Routing](#team-routing)

---

## API Basics

- **Base URL (staging):** `api.staging.payrails.io` — for staging environments
- **Base URL (production):** `api.payrails.io` — for production merchants. Staging credentials do NOT work here and vice versa.
- **Auth:** mTLS + Bearer token via API key, or OAuth
  - API credentials: https://docs.payrails.com/docs/api-credentials-1
  - mTLS configuration: https://docs.payrails.com/docs/mtls-configuration-1
- **SDK Docs:** https://docs.payrails.com/docs/sdk
- **API Reference:** https://docs.payrails.com/reference
- **Full Docs:** https://docs.payrails.com/docs

### Key Endpoints

| Endpoint | Purpose | Docs |
|----------|---------|------|
| `/auth/token/{clientId}` | OAuth token | https://docs.payrails.com/reference/getoauthtoken |
| `/merchant/client/init` | Client initialisation | https://docs.payrails.com/reference/clientinit |
| `/merchant/workflows/{workflowCode}/executions` | Create or list workflow executions. List supports `filter[merchantReference]`, `filter[holderReference]`, `filter[lastStatus]`, `filter[workspaceId]` | https://docs.payrails.com/reference/createexecution |
| `/merchant/workflows/{workflowCode}/executions/{executionId}` | Get full execution state (status, errors, amounts, links) | https://docs.payrails.com/reference |
| `/merchant/workflows/{workflowCode}/executions/{executionId}/history` | Full event timeline — PSP results, webhook delivery, rule engine context. Most powerful single call for transaction-level debugging. | https://docs.payrails.com/reference |
| `/merchant/workflows/{workflowCode}/executions/{executionId}/actions` | List actions currently available on an execution | https://docs.payrails.com/reference |
| `/payment/payments` | List payments. Supports `filter[merchantReference]`, `filter[holderId]`, `filter[holderReference]`, `filter[providerReference]`, `filter[status]`, `filter[anyReference]`, `filter[instrumentId]`, and more. Returns `providerReference`, `authorizationFailureResult`, `capturedAmount`, `refundedAmount`. | https://docs.payrails.com/reference |
| `/payment/payments/{paymentId}` | Get a single payment record by ID | https://docs.payrails.com/reference |
| `/payment/payments/{paymentId}/operations` | List PSP operations on a payment — useful for seeing exactly what was sent/received at the provider level | https://docs.payrails.com/reference |
| `/payment/payments/{paymentId}/operations/{operationId}/logs` | Raw operation logs — deepest level of provider request/response detail | https://docs.payrails.com/reference |
| `/payment/providers/{providerId}/proxy` | Vault proxy | https://docs.payrails.com/reference/vaultproxy |
| `/config/configurations/merchant/versions/{version}` | Get a specific environment configuration version by number. Response has `.config.featureflags` (all lowercase) for feature flags, plus `.version`, `.description`, `.createdAt`. Requires merchant bearer token. | — |
| `/config/configurations/merchant/current/history` | Activation history for the environment configuration — most recently activated version is first in `.results`. Each entry has `.version`, `.description`, `.setBy`, `.setAt`. Use this to confirm what version is currently active and who activated it. | — |

### API Lookup Tips (learnt from live debugging)

**Always use single quotes around API secrets in curl commands.**
Payrails API secrets frequently contain special shell characters (`$`, `!`, `^`, `*`, `@`). Using double quotes causes the shell to interpret these, silently corrupting the value and producing `invalid_client` errors that look like stale or wrong credentials. Always wrap the secret in single quotes:
```bash
curl -X POST "https://rc-api.staging.payrails.io/auth/token/{clientId}" \
  -H 'x-api-key: {clientSecret}'
```
If the secret itself contains a single quote, use `$'...'` quoting instead. Do not use double quotes for secrets.

**Always Grep/Read `doc/oas/src/` in the backend repo before guessing endpoint paths.**
Trial-and-error curl is slower and teaches you nothing reusable. Search the OAS spec files first to confirm the correct path structure for any endpoint you haven't used before.

**If `doc/oas/src/` Grep returns zero results, check `https://docs.payrails.com/reference` next — do not guess.**
The local OAS spec does not cover every endpoint (e.g. `/auth/users` is not in it). If the filesystem search returns nothing, the API reference docs are the authoritative next step. Going to backoffice endpoints or guessing paths without checking the docs first is wrong and wastes time.

**All list endpoints use `filter[field]` bracket notation for query params — not bare params.**
e.g. `filter[merchantReference]=...`, `filter[holderId]=...`, `filter[lastStatus]=...`. Using bare params like `merchantReference=...` will either return unfiltered results or a `request.not-found` error. When in doubt, read the OAS spec file for the endpoint in `doc/oas/src/` to see the exact parameter names before calling.

**Use direct curl to obtain a staging auth token — no MCP tool or local proxy needed.**
```
curl -X POST https://rc-api.staging.payrails.io/auth/token/{clientId} \
  -H 'x-api-key: {clientSecret}'
```

**Merchant-reported payment/execution IDs are almost always production IDs.**
Dashboard URLs follow the pattern `{merchant}.payrails.io/workspaces/{workspaceId}/...` — those are production. Staging credentials cannot look up production records. Always confirm the environment before attempting API lookups, or you'll get 404s that look like missing data but are just the wrong environment.

**Finding a merchant's workspace ID without the dashboard.**
If you need a workspace ID and don't have it, search internal Slack for the merchant's name alongside `payrails.io/workspaces/`. Dashboard URLs embedded in Slack messages contain the workspace UUID, e.g. `kissmyapps.payrails.io/workspaces/e00c965f-5bd1-4267-9e7c-e1701f7c1285/...`.

**Execution responses include hypermedia links for valid next actions.**
The `links` object in a GET execution response tells you exactly which actions are available for that execution's current state (e.g. `capture`, `cancel`), including the ready-to-use URL. Use this instead of guessing whether an action is valid — if the link isn't there, the action isn't permitted in the current state.

**`notificationUrl` is a field on the provider config — fetch it, don't construct it.**
`GET /payment/providers/{providerId}/configs` (or the provider config list endpoint) returns `notificationUrl` as a field on each config object. When a merchant needs to know what URL to register with a PSP for webhook delivery, fetch the provider config and read `notificationUrl` directly. The format embeds the holder ID and provider config ID and is not guessable without knowing both.

**`additionalData` on a provider config is a merchant-facing passthrough — not a webhook config.**
When a PSP notification is received and processed, `additionalData` from the provider config is forwarded to the merchant's Payrails event payload as `providerConfig.additionalData` (via `ProviderConfigAdditionalData`). It is NOT read by connectors during notification processing — `NotificationRequest` does not carry it. Storing or not storing values there has no effect on notification routing, HMAC validation, or any other processing. It is purely optional reference data the merchant receives echoed back in their events.

**Environment config feature flags are at `.config.featureflags` — all lowercase, nested under `.config`.**
When fetching `/config/configurations/merchant/versions/{version}`, the feature flags object is at `.config.featureflags` (all lowercase). Not `.featureFlags` (camelCase) and not at the root level. Using the wrong path returns `null` silently.

**`modularizedWorkflows.enabled` in the active environment config controls whether a merchant is actually on the modular workflow.**
Even if a merchant has a modular workflow configuration version set up in the workflow portal, if their active environment config has `.config.featureflags.modularizedWorkflows.enabled: false`, they are NOT running the modular workflow. A misconfigured environment config version (e.g. created from a wrong template) can silently disable MWF. When diagnosing "modular workflow not behaving as expected", always check the active environment config version and verify these fields:
- `modularizedWorkflows.enabled` — must be `true`
- `merchantActionEventsEnabled` — must be `true`
- `supportedWorkflowCodes` — must be `["payment-acceptance"]` (not `[""]`)
- `workflowStepEventsEnabled` — must be `true`
- `supportedWorkflowFeatures.payment-acceptance.enableExecutionCreation` — must be `true`
Use `/config/configurations/merchant/current/history` to confirm which version is active before fetching that version to inspect.

**Getting paymentId from an executionId.**
The execution itself does not expose a `paymentId` field. To get to the payment record, fetch the execution history and look inside `executionActionCompleted` events: `paymentComposition[].paymentId`. That UUID is the ID to pass to `GET /payment/payments/{paymentId}` and `GET /payment/payments/{paymentId}/operations`.

**Payment record fields useful for debugging.**
`GET /payment/payments/{paymentId}` returns:
- `amount` — the authorised amount
- `capturedAmount` — what was actually captured (different from `amount` on partial captures)
- `refundedAmount` — total refunded so far
- `providerReference` — the PSP's reference. Note: for some providers (Worldpay confirmed) this echoes the Payrails `merchantReference` rather than the PSP-assigned ID. The operation-level `providerReference` (from `/operations`) is the more authoritative PSP reference.
- `providerAdditionalMeta` — provider-specific metadata. For Worldpay this contains `paymentID` (Worldpay's own payment ID, format `payXXXXX`) and hypermedia action links (`captureLink`, `cancelLink`, `refundLink`, `partialCaptureLink`).

---

## Common Error Patterns

### Cloudflare Error
**Cause:** Misconfigured mTLS certificate.
**Fix:** Verify the mTLS certificate is correctly installed and matches the environment. Check Dashboard → Settings → API Credentials → mTLS Configuration.

### Unknown ID
**Cause:** Operating on the wrong workspace.
**Fix:** Confirm the merchant is using the correct workspace ID / API key pair for the target environment.

### Payment Method Not Displaying on SDK
**Cause:** Usually one of:
1. Payment method not enabled in the merchant's settings
2. Using the wrong workflow config version
**Fix:** Check Dashboard → Payment Methods to confirm the method is enabled. Then verify the workflow config version matches what the SDK is requesting.

### Client Init Response
The data in the client init response is **base64 encoded**. Decode it on the frontend to find more information about the payment to be processed. SEs and merchants often miss this — if someone says "client init returns garbage", remind them to decode.

### Workflow Code
The workflow code is **always** `payment-acceptance`. If a merchant is using a different value, that's the problem.

---

## Provider-Specific Gotchas

### Adyen
_[Add common Adyen issues as they arise]_

### Stripe
_[Add common Stripe issues as they arise]_

### Checkout.com
_[Add common Checkout.com issues as they arise]_

### Tabby

**`additionalData` is not required for Tabby webhooks to function.**
The Tabby connector does not read `additionalData` from the provider config at any point during notification processing. Webhook notifications are received, parsed, and processed without it. If a merchant or SE asks what to put in the Additional Data section for Tabby webhook setup, the correct answer is: nothing is required. See the note on `additionalData` passthrough in API Basics below.

**`CheckHmacKeyAndGetIdempotencyKey` does not validate signing headers.**
Despite the name, the Tabby connector's notification handler only builds an idempotency key (`token+ID+created_at`). Tabby's webhook signing headers (`header.title` / `header.value` from Tabby's webhook registration response) are not validated. Notifications are accepted without signature verification.

### Worldpay

**`acquirerReference` is not populated for Worldpay transactions.**
All Worldpay payment operations (`Authorize`, `AuthorizeNotification`, `Capture`, `CaptureNotification`) return `acquirerReference: ""` — the Worldpay connector does not map any PSP field to this. If a merchant asks for an ARN or RRN for a Worldpay transaction, Payrails cannot provide it directly from the standard API response.

**Where to look for the closest available references in raw logs.**
The raw Worldpay notification payloads (accessible via `GET /payment/payments/{id}/operations/{opId}/logs`) contain:
- `downstreamReference` — Worldpay's acquirer/downstream reference. Present in both the `authorized` and `sentForSettlement` notification bodies. This is NOT a standard 23-digit bank ARN — it is Worldpay's own internal reference (typically ~11 digits). Do not present it to a merchant as the ARN.
- RRN (`retrievalReference`) — Worldpay provides this in the synchronous authorize API response, not in the async notification. The connector does not store it. Raw authorize operation logs may be empty if the connector does not persist the synchronous response body.

**Worldpay payment IDs: there are multiple, and they differ.**
For a single Worldpay transaction you will encounter:
- Payment record top-level `providerReference` — often echoes the Payrails `merchantReference`, not a Worldpay ID
- Authorize operation `providerReference` (from `/operations`) — the Worldpay-assigned payment reference at auth time (alphanumeric, ~24 chars, no prefix)
- `providerAdditionalMeta.paymentID` on the payment record — Worldpay's own payment ID (format `payXXXXX`), distinct from the above

When escalating to the integrations team to retrieve ARN/RRN from Worldpay, share all three so they can find the transaction.

### HyperPay

**ProviderTimeout ≠ transaction did not happen at HyperPay.**
When Payrails marks an execution as `authorizeFailed` with reason `ProviderTimeout`, HyperPay may have successfully processed the transaction on their side before the timeout fired. This is a known recurring issue (Linear: INT-2391, status: Backlog as of Apr 2026).

To confirm whether HyperPay actually processed the transaction:
- Query HyperPay's Reporting (Status) API using the execution's `merchantReference` (find it in the GET execution response)
- HyperPay doc: https://hyperpay.docs.oppwa.com/integrations/reporting
- If HyperPay returns a successful record, the funds may be held at the issuer and must be voided directly with HyperPay

**Symptom pattern:** Payrails shows `authorizeFailed` / `ProviderTimeout`, but the user reports being charged. Check HyperPay's Reporting API before telling the user no charge occurred.

**Where to find `providerReference` and ARN:**
- `GET /merchant/workflows/.../executions/{id}/history`: action composition events contain `providerReference` and `acquirerReference` (the ARN). If the provider responded before the timeout, these fields will be populated here.
- `GET /payment/payments?filter[merchantReference]=...`: the payment record contains `providerReference`. An empty string here means the PSP never returned a reference — the timeout fired before they responded.

For ProviderTimeout cases: fetch the payment record first to check `providerReference`. If empty, fetch execution history to confirm no partial provider response was recorded. If both are empty, HyperPay's Reporting API (using the `merchantReference`) is the only way to determine if they processed it.

---

## Team Routing

| Issue Type | Contact | Slack Channel |
|------------|---------|---------------|
| API errors / platform issues | Atakan | #payments-acceptance |
| SDK issues | Basel and Akshay | #checkout |
| Provider issues | Rehab | #integrations |
| Infrastructure / downtime | Vigilante | #platform |
| Modular workflow / workflow config issues | #team-workflows-platform (has a weekly support rotation — post in the channel, not DMs to individuals; the person on support duty will pick it up) | #team-workflows-platform |