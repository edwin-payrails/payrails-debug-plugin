# Temporal reference

Temporal workflow state is queried through the **`temporal` MCP server** (bundled
in this plugin). Prefer these tools over raw curl — they handle cluster routing,
failover, retries, and payload decoding for you. (Raw curl against the REST API
still works as a fallback for anything not covered; see the bottom of this file.)

## Tools (all read-only)

| Tool | Use it for |
|---|---|
| `list_workflows` | List recent workflows, filter by type / status / time range |
| `describe_workflow` | All runs (run IDs) + status for one workflow ID |
| `get_workflow_history` | Event history for a specific run |
| `decode_payload` | Decode encrypted payloads via the codec server |
| `get_execution` | **Best for a payment execution ID** — one call returns run metadata, a compact **event index** (the *ordered event sequence* — eventId/type/time only, not event bodies), and **decoded payloads**. Optional `runId` to inspect a non-latest run. For full raw event detail/attributes, use `get_workflow_history`. |
| `search_workflows` | Free-form Temporal visibility query (anything the others don't cover) |
| `list_namespaces` | Discover namespaces on a cluster (when the merchant's namespace isn't the default) |

Every tool takes:
- **`namespace`** — `{merchant}-backend` (e.g. `playtomic-backend`). If a merchant
  doesn't follow that pattern, use `list_namespaces` to find the real one.
- **`environment`** — `"staging"` or `"production"`.

The server auto-routes to the right cluster (merchant vs internal) based on the
namespace, and **falls back to the other cluster in the same environment** if the
first is empty. It never crosses staging↔production.

## Common tasks

**A merchant gave you a payment execution ID** → use `get_execution`:
```
get_execution(namespace="{merchant}-backend", environment="staging", executionId="{uuid}")
```
Returns: all runs (metadata), a compact **event index** for the chosen run (the
*ordered event sequence* — eventId/type/time per event, NOT the event bodies), and
the **decoded payloads** (the events that carried decodable content). For full raw
event detail/attributes, call `get_workflow_history`. To inspect an earlier action
cycle, pass its `runId` (Payrails creates a new run per cycle; get run IDs from the
`allRuns` field or `describe_workflow`). This replaces the old multi-step
curl-history-then-codec flow.

**List recent payment workflows:**
```
list_workflows(namespace="{merchant}-backend", environment="staging", workflowType="MainWorkflow")
```

**Only running ones:**
```
list_workflows(..., workflowType="MainWorkflow", executionStatus="Running")
```

**Time range:** pass `startTimeFrom` / `startTimeTo` (ISO 8601). (`ORDER BY` is not
supported by Temporal; `BETWEEN`-style time bounds work.)

**Anything more specific** → `search_workflows` with a raw query, e.g.
`WorkflowType="MainWorkflow" AND WorkflowId="payment-acceptance/{uuid}"`.

**Inspect one run's history:** `describe_workflow` to get the run ID, then
`get_workflow_history`.

## Large responses

`get_execution` and `get_workflow_history` can be large. When a response exceeds
the inline limit, the tool writes the full JSON to a cache file **inside the
session workspace** (`${CLAUDE_PROJECT_DIR}/.payrails-temporal-cache/`, falling
back to the system temp dir) and returns a compact summary plus the
`_fullDataPath`. Read that file — or slice it with Read offset/limit, or a bash
`jq`/`grep` — to get the complete data without flooding context. If the `_note`
warns it fell back to the system temp dir, this session may not be able to read it
(set `TEMPORAL_OFFLOAD_DIR` to a folder the session can access). Files are swept
after 24h on server startup. Key fields (run counts, event counts, cluster) are in
the inline summary.

Responses are also kept lean automatically without losing information:
- **Search attributes** (`BuildIds`, `TemporalChangeVersion`, …) are returned
  **decoded/readable** (e.g. a list of change tags) rather than as opaque base64.
- **`get_execution` payloads** include the **decoded** form; the redundant raw
  encrypted blob is omitted *when a decoded form exists*. If a payload could not
  be decoded (e.g. the `multitenant-backend` codec gap), its raw `data` is kept.

## Payload decryption (codec)

`get_execution` decodes payloads automatically. To decode payloads you already
have in hand, use `decode_payload`. **What gets decrypted:** non-sensitive fields
like `holderReference`, `workspaceId`, `merchantReference`, `workflowCode`, and
event input/output structs. **Sensitive fields stay encrypted** (card numbers,
tokens — prefix `QUVTLUdDTT`). Field structure (string vs object) is preserved
even when a value stays encrypted — useful for spotting format errors.

**Known gap:** the `multitenant-backend` namespace (config/backoffice workflows)
cannot be decrypted — the codec lacks that namespace's key, so its payloads stay
encrypted. This is expected, not an error.

**Temporal browser UI:** to see decrypted payloads inline in the Temporal web UI,
click "Data Encoder" (bottom-left) → enter the codec base URL for the environment
(staging merchants: `https://api.staging.payrails.io/merchant/temporal/codec`).

## Clusters (for reference / curl fallback)

The MCP server is already configured with these via the plugin's `.mcp.json`; you
normally don't touch them. Listed here for awareness:

- **Staging — merchant namespaces:** `status.temporal01.staging.aws.payrails.io`
- **Staging — internal namespaces** (`payrails-backend`, `demo-backend`, `multitenant-backend`): `status.temporal11.staging.aws.payrails.io`
- **Production:** `status.temporal01.mixed-eu.aws.payrails.io`
  ⚠️ `mixed-eu` is **PRODUCTION**, not a staging alternative. Use
  `environment="production"` to reach it — never query it for staging data.

## Workflow types at Payrails

- `MainWorkflow` — payment-acceptance execution (workflowId: `payment-acceptance/{executionId}`)
- `ClientInitWorkflow` — SDK client init (very short-lived, ~0.1s)

## Key insight for debugging

`MainWorkflow` executions are **short-lived** (10–25s per run) — each action cycle
creates a new run under the same workflowId. Between actions, the workflowId may be
in COMPLETED state. This is normal. (If `QueryState()` is called when no run is
RUNNING → `workflow_execution_not_found`.)

Temporal **retention is short (~5 days)** — workflows that finished more than a few
days ago may no longer exist. The MCP returns a hint about this on not-found.

## Limitations

- Sensitive fields remain encrypted even after codec decryption.
- `ORDER BY` is **not supported** — this is a limitation of Temporal's visibility
  backend (the cluster rejects it: `"ORDER BY clause is not supported"`), not the
  MCP, so no client (REST, SDK, or curl) can change it. Results come in Temporal's
  **default order: most recent first** (by start time). To find a specific
  workflow, **narrow with filters** (`workflowType`, `executionStatus`,
  `startTimeFrom`/`startTimeTo`) rather than sorting. Time-range bounds (`BETWEEN`)
  do work.
- The Temporal UI at the cluster base URL is a React app — the MCP uses the REST API.
- **History pagination is single-page (honest, not silent).** `get_workflow_history`
  (and `get_execution`'s event index) fetch one page. Payrails runs are short (well
  under one page), so in practice this is always complete. If a single run ever
  exceeded one page, the response includes `truncated: true` + a `nextPageToken` so
  you know it's partial. That token is **informational only** — the tools don't
  currently page through it (and never did; the old curl flow was also single-page).
  For the rare full history of an oversized single run, fall back to raw curl using
  the token.

## Raw curl fallback (only if the MCP can't cover something)

The REST API needs no auth. Always use `https://` (port 80 is closed). History
payloads are `binary/zlib` (compressed + encrypted) — do **not** `zlib.decompress`
them yourself (returns garbage); always go through the codec. Run ID must be a
query param (`execution.run_id=`), not a path segment (`/runs/{id}/history` → 404).
```bash
curl -s "https://{cluster}/api/v1/namespaces/{namespace}/workflows?pageSize=10&query={urlencoded-query}"
```
