# Temporal staging reference

## Access

No authentication required. Query directly via Bash/curl.

- **Primary staging cluster:** `https://status.temporal01.staging.aws.payrails.io`
- **Mixed-EU cluster:** `https://status.temporal01.mixed-eu.aws.payrails.io` (different merchants — check both if needed)

## Namespace format

`{merchant}-backend` — e.g. `playtomic-backend`, `kilohealth-backend`, `eneba-backend`

## Useful queries

**List recent MainWorkflow executions:**
```bash
curl -s "https://status.temporal01.staging.aws.payrails.io/api/v1/namespaces/{merchant}-backend/workflows?pageSize=10&query=WorkflowType%3D%22MainWorkflow%22"
```

**Filter by execution status (Running/Completed):**
```bash
# Running only:
curl -s "...?pageSize=10&query=WorkflowType%3D%22MainWorkflow%22+AND+ExecutionStatus%3D%22Running%22"
```

**Look up a specific execution ID:**
```bash
curl -s "...?pageSize=10&query=WorkflowType%3D%22MainWorkflow%22+AND+WorkflowId%3D%22payment-acceptance%2F{uuid}%22"
```

**Filter by time range:**
```bash
# Use: StartTime BETWEEN "2026-04-15T12:00:00Z" AND "2026-04-15T15:00:00Z"
```
Note: `ORDER BY` is not supported.

**Get workflow runs for a specific workflowId (all run IDs):**
Returns multiple entries for the same workflowId if it was restarted.

**Get workflow history:**
```bash
curl -s "https://status.temporal01.staging.aws.payrails.io/api/v1/namespaces/{merchant}-backend/workflows/{urlencoded-workflowId}/history?execution.run_id={runId}&maximumPageSize=30"
```
⚠️ The run ID must be a **query param** (`execution.run_id=`), NOT a path segment. Using `/runs/{runId}/history` returns 404.
⚠️ History payloads are `binary/zlib` encoded — raw bytes are zlib-compressed AND encrypted. **Do NOT try to decompress with Python `zlib.decompress()` — it will return garbage (`encodingbinary/null`).** Always use the codec server below to decode. This step is mandatory, not optional.

**Common mistake:** Using `http://` instead of `https://` will time out (port 80 is not open). Always use `https://`.

## Decrypting Temporal payloads (codec server)

Temporal history payloads are encrypted, but the **Payrails codec server decrypts non-sensitive fields** without any authentication.

**Codec endpoint (staging):**
```
POST https://rc-api.staging.payrails.io/merchant/temporal/codec/decode
```

**Required header:** `X-Namespace: {merchant}-backend` (e.g. `X-Namespace: playtomic-backend`)
**No auth token required** — the middleware only extracts the merchant name from the header.

**Request format:**
```bash
curl -s -X POST "https://rc-api.staging.payrails.io/merchant/temporal/codec/decode" \
  -H "Content-Type: application/json" \
  -H "X-Namespace: playtomic-backend" \
  -d '{"payloads": [{"metadata": {...}, "data": "..."}]}'
```
Pass the full payload object from the history event as-is. The response returns the same structure with `data` decoded.

**What gets decrypted:** Non-sensitive fields like `holderReference`, `workspaceId`, `merchantReference`, `workflowCode`, event input/output structs. **Sensitive fields stay encrypted** (card numbers, tokens, etc.).

**Confirmed working** (2026-04-15, 2026-04-23): decoded Playtomic `ClientInitWorkflow` and Sunday Natural `AuthorizeWorkflow`. Keys are always readable; sensitive values stay AES-encrypted (prefix `QUVTLUdDTT`). Field structure (whether a value is a string vs object) is preserved even when encrypted — useful for spotting format errors.

**Complete two-step flow:**
```bash
# Step 1: get the raw payload from history
PAYLOAD=$(curl -s "https://status.temporal01.staging.aws.payrails.io/api/v1/namespaces/{merchant}-backend/workflows/{urlencoded-wfId}/history?execution.run_id={runId}&maximumPageSize=5" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for e in data.get('history',{}).get('events',[]):
    if 'workflowExecutionStartedEventAttributes' in e:
        payloads = e['workflowExecutionStartedEventAttributes'].get('input',{}).get('payloads',[])
        print(json.dumps({'payloads': payloads}))
        break
")

# Step 2: send to codec server
echo "$PAYLOAD" | curl -s -X POST "https://rc-api.staging.payrails.io/merchant/temporal/codec/decode" \
  -H "Content-Type: application/json" \
  -H "X-Namespace: {merchant}-backend" \
  -d @- | python3 -c "
import json, sys, base64
resp = json.load(sys.stdin)
for p in resp.get('payloads', []):
    d = p.get('data', '')
    if d:
        print(base64.b64decode(d).decode('utf-8', errors='replace'))
"
```

**For Temporal browser UI:** Click "Data Encoder" button (bottom-left of Temporal UI) → enter `https://rc-api.staging.payrails.io/merchant/temporal/codec` to see decrypted payloads inline.

## Limitations

- Sensitive fields remain encrypted even after codec decryption
- `ORDER BY` not supported in queries
- `BETWEEN` for time ranges works
- The Temporal UI at the same base URL is a React app — use the REST API directly

## Workflow types at Payrails

- `MainWorkflow` — payment-acceptance execution (workflowId: `payment-acceptance/{executionId}`)
- `ClientInitWorkflow` — SDK client init (very short-lived, ~0.1s)

## Key insight for debugging

`MainWorkflow` executions are **short-lived** (10-25s per run) — each action cycle creates a new run under the same workflowId. Between actions, the workflowId may be in COMPLETED state. If `QueryState()` is called when no run is RUNNING → `workflow_execution_not_found`.