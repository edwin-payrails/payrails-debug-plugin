# Codebase Debugging Workflow

Follow this workflow when an SE asks you to validate or explain behaviour based on code.

---

## Step 1 — LOCATE: Find the relevant files

- Start from the symptom: if it's an API error, grep for the endpoint path or error code.
- If it's a behaviour question, grep for the feature name, function name, or config key.
- Read the route handler or entry point first to understand the request flow.

## Step 2 — TRACE: Follow the execution path

- From the route handler, identify which service/function is called.
- Read that service file. Identify any downstream calls (database, external APIs, other services).
- Look for error handling: try/catch blocks, error codes being thrown, validation logic.
- Check middleware that runs before the handler (auth, rate limiting, request validation).

## Step 3 — IDENTIFY: Find the specific code causing the issue

- Compare what the code does vs what the merchant expects.
- Look for: missing validation, incorrect default values, race conditions, wrong error codes, hardcoded assumptions, version-specific branches, environment-specific logic.
- Check test files for the same function — tests often document expected vs edge-case behaviour.

## Step 4 — EXPLAIN: Tell the SE what the code is doing and why

- Reference specific files and line numbers.
- Show the relevant code snippet.
- Explain the logic path that leads to the observed behaviour.
- If the code is correct and the merchant's expectation is wrong, explain the correct usage.
- If the code has a bug, describe exactly what's wrong and propose a fix.

## Step 5 — VERIFY: Check if there's a quick way to confirm

- Look for relevant unit tests or integration tests.
- Check if the test covers the specific case the merchant is hitting.
- If there's no test for this case, note that as a gap.
- Suggest a minimal reproduction if the SE needs to validate locally.

---

## Rules for codebase exploration

1. Always show the file path and line numbers when referencing code.
2. Read the actual code — never assume what a function does based on its name.
3. When you find something relevant, read the surrounding context (rest of the file) to understand the full picture.
4. If a function is imported, find and read the source — don't guess the implementation.
5. Check for recent changes: if there's a CHANGELOG or git history available, look for recent modifications to the relevant files.
6. If the codebase is too large to explore efficiently, ask the SE to point you to the relevant service or module rather than searching blindly.