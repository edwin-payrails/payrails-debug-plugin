# Google Pay tokenisation failures

## The Error

```
HTTP 400 | code: "request.malformed" | detail: "failed to tokenize google pay token"
```

Occurs on `POST /payment/instruments` or during authorize with paymentToken. The Payrails vault failed to decrypt the Google Pay token.

## Root Cause 1 — Wrong tokenizationSpecification (most common)

If the merchant's Google Pay button is configured with `gateway: "adyen"`, `gateway: "checkoutltd"`, or any other PSP instead of `gateway: "payrails"`, Google encrypts the token with that PSP's public key. Payrails vault cannot decrypt it.

**Fix:** Merchant must use exactly:
```json
{
  "tokenizationSpecification": {
    "type": "PAYMENT_GATEWAY",
    "parameters": {
      "gateway": "payrails",
      "gatewayMerchantId": "<merchant_name_lowercase>"
    }
  }
}
```

`gatewayMerchantId` is the merchant's name in Payrails (e.g. `"careem"`, `"prypco"`). Confirmed by Atakan.

**Source:** Linear TOK-1637 (Feb 2026) — prypco merchant had this exact issue.

## Root Cause 2 — Agnostic Google Pay feature flag not enabled

If the flag is off, the vault expects a different token format. When the merchant sends ECv2 (correct for agnostic), the vault rejects it.

**Symptom:** Same error. In vault logs you'll see a protocol version mismatch.

**Fix:** Enable agnostic GPay feature flag for the merchant in the platform. Must be requested via #payments-acceptance (Atakan).

**Source:** #proj-payment-links (Mar 2026) — MAF had this, fixed by Abiola enabling the flag.

## Root Cause 3 — TEST vs PRODUCTION environment mismatch

If the merchant initialises the Google Pay SDK with `environment: "PRODUCTION"` but is testing against Payrails staging, the token is encrypted with production keys that the staging vault isn't configured with.

**Fix:** Use `environment: "TEST"` for staging.

## Debugging steps

1. Check if agnostic GPay feature flag is enabled for the merchant — check in #payments-acceptance or ask Atakan
2. Ask merchant to confirm their exact `tokenizationSpecification` (especially `gateway` field)
3. Ask merchant to confirm `environment` (TEST vs PRODUCTION) in their GPay SDK init
4. Pull vault logs in Grafana (via the **Grafana MCP**) for the specific `x-request-id` to get the exact decryption error
   - First find the vault correlation ID from backend logs: `query_loki_logs(datasourceUid="grafanacloud-logs", logql='{merchant_name="<merchant>", app="backend"} |= "<x-request-id>"', limit=20)`
   - Then the vault logs: `query_loki_logs(datasourceUid="grafanacloud-logs", logql='{namespace="<merchant>-vault", component="vault-http"} |= "<vault-correlation-id>"', limit=20)`
   - *(Add `startRfc3339`/`endRfc3339` time bounds per `../grafana.md`. The old self-hosted `cluster=` filters were dropped — if a query returns nothing, discover values with `list_loki_label_values(datasourceUid="grafanacloud-logs", labelName="cluster")`.)*

## gatewayMerchantId values confirmed

| Merchant | gatewayMerchantId |
|----------|-------------------|
| careem   | careem            |
| prypco   | prypco            |

For any new merchant it's their merchant name (lowercase, as registered in Payrails).
