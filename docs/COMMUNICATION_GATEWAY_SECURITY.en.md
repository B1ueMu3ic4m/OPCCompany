<!-- Translated from COMMUNICATION_GATEWAY_SECURITY.md; the Chinese original remains authoritative for internal history. -->

# Communication Gateway Security Notes

Last updated: 2026-05-07

Current status: Communication Gateway mobile linkage and the external inbound HTTP service are **not** blockers for current single-user local formal use. The in-app local command center, outbound reporting rules, signature-verification primitives, and action-allowlist logic are retained; external inbound stays off by default and only enters productization evaluation when the user actually needs remote or phone linkage.

## Current boundaries

The OPC Communication Gateway has three layers:

- Local command center: simulates phone commands inside the app, enabled by default, and verifies the full product chain.
- Outbound reporting: triggered in-app by the Boss or CTO, sent to configured-ready Feishu, WeCom, DingTalk, Telegram, or email channels.
- External inbound: a future HTTP service entry, off by default; it must pass signature, timestamp, nonce, and action-allowlist checks before entering OPC.

Phone commands never execute commands directly, never modify files, and never skip Approval Gates. They only write to the communication log, notify the current product team lead, and create traceable tasks.

## Outbound rules

- The channel must be enabled and allow reporting.
- External channels must have a fully configured address; Telegram also requires a chat identifier.
- On send failure, only a redacted host-level address is recorded — never webhook tokens, path secrets, or query parameters.
- The LOCAL channel makes no network request; it only records a local success.

## Inbound signature rules

Before the external inbound service can be connected, it must use:

- HMAC-SHA256 signatures.
- ISO8601 timestamps, with 5 minutes of skew allowed by default.
- nonce anti-replay; the last 1000 nonces must not repeat.
- Signature payload: `timestamp.nonce.body`.
- A passing signature means the nonce is consumed. Even if the subsequent JSON parse fails, the action is not on the allowlist, or fields are missing, a new timestamp, nonce, and signature must be generated and the request re-sent, so the same signed package cannot be replayed to probe multiple action variants.

A pure-logic validation module `CommunicationInboundVerifier` is already in place, covering:

- Missing timestamp / nonce / signature.
- Expired timestamp.
- nonce replay.
- Signature error.
- Valid signature passes.

The external signed entry does not pass arbitrary text straight through. After signature validation, input must still parse as structured JSON and pass the action allowlist:

- `query_status`: only writes a status-query log and a CTO summary; no task creation, no command execution, no file modification.
- `submit_instruction`: converts ordinary instructions in the `text` / `instruction` / `command` fields into traceable tasks.
- `approval_decision`: action name reserved, but currently rejected by default; it will only open after the approval number, decision value, risk feedback loop, and Boss confirmation chain are complete.

Non-JSON input, missing `action`, non-allowlisted actions, empty instructions, and external approval actions are all rejected and written to the communication log.

## Future external HTTP service admission

Before actually listening on a port, all of the following must hold:

- Bind only to `127.0.0.1` by default.
- Off by default; requires a product-level switch to explicitly enable it.
- Only allowlisted actions: query current product status, submit ordinary instruction tasks, handle specific approvals.
- Every inbound request is written to the communication log and the event stream.
- Any high-risk action must still return to the Boss decision center for confirmation.
