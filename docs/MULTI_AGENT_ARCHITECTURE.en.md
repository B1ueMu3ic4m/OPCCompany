<!-- Translated from MULTI_AGENT_ARCHITECTURE.md; the Chinese original remains authoritative for internal history. -->

# OPC Multi-Agent Architecture Upgrade Plan

Last updated: 2026-05-07

Current status: The multi-agent architecture upgrade has reached the single-user local formal-use baseline. This document keeps the plan and architecture notes; current acceptance status, latest test counts, and bundle version are governed by the internal project constitution (local only) and `docs/RUNBOOK.md`.

## Goals for this round

Upgrade OPC from "has multiple employees and task lists" to "has traceable multi-agent collaboration chains".

Completion status: the underlying collaboration model for this round's multi-agent architecture upgrade is in place, covered by `runMultiAgentArchitectureClosureDrill`, the architecture health check, and tests. If the default product has not yet run a closure drill, the Terminal Hall shows unclosed or to-be-strengthened; this means the current product lacks drill evidence, not that code capability is missing.

2026-05-07 formal-use baseline additions:

- Employee prompts, work-order prompts, rework prompts, collaboration messages, and CLI session resumes now have token budget boundaries.
- Default visible Boss UI does not show maintenance-class risks, backend paths, or underlying command parameters.
- The Terminal Hall "Run All" first shows a Chinese confirmation when it would trigger multiple employees with the default reporting prompt, so the whole team's CLI quota is not accidentally consumed.
- Further enhancement only addresses real blockers or explicitly requested new goals; problems are no longer expanded just to keep the loop running.

This round first stabilized the underlying collaboration model; since 2026-05-01, the Communication Gateway and history index have entered the verifiable-enhancement stage:

- The CTO can turn the Boss's goal into a structured task graph.
- The CTO leaves message records when dispatching tasks to employees.
- Employees can report results back to the CTO on completion.
- Reviewers can receive review requests.
- The Boss only sees results, risks, pending approvals, and delivery summaries.
- All processes must be verifiable by tests, not just fake UI display.

Current CLI enhancement status:

- Resident protocol-based employees prefer running tasks in real terminal workspace seats; OPC wraps command sending, single-line literal input, output capture, timeout interruption, and window closing in a persistent-terminal session abstraction cached per product and per employee, and keeps writing `.opc/jobs` job archives, terminal logs, and runtime session state.
- Custom one-shot CLI employees get `HOME` and XDG directories redirected to the current product's execution directory, reducing cross-product and real-user-Home leak risk.
- Products can explicitly enable strict sandboxing; once enabled, one-shot commands are blocked by the system sandbox from reading or writing sensitive directories under the user's Home while the current product's execution directory stays readable/writable. This capability is off by default and does not affect existing subscription CLI login state.
- The first stage of Codex / Claude / Gemini session resume is wired in: when CLI output contains an explicit session ID, OPC binds that ID to the current employee, current product, and current backend configuration, and keeps it bucketed per product; later tasks only resume the matching session under the same product, and switching products never overwrites the old product's session; the "most recent session" selection that could cross-wire employees is never used. Long-lived protocol profiles, status observation, long-output boundary protection, persistent-terminal polling diagnostics, single-line literal input, Chinese recovery advice, the controlled manual-retry entry, the auto-input-loop safety gate state machine, the injectable send-closure executor core, and the CTO internal coordinator are all in place; cross-CLI real-terminal-seat auto input remains a future enhancement.
- Persistent-terminal execution now has unfinished-task gating and timeout-interruption escalation: before sending, it checks whether the real terminal seat has an unclosed OPC marker, and refuses to overwrite if present; on timeout it sends a normal interrupt first, then a hard interrupt, and closes the unresponsive seat with a failure record if still unclosed.
- Persistent-terminal sessions distinguish two input paths: full-task submissions use OPC markers, timeout interruption, and job archives; single-line literal input only injects one line of stdin into the same long-lived seat, without writing markers, without job archives, and without affecting the full-task marker detection or timeout handling.
- Manual interaction rounds are extended to Codex / Claude Code / Gemini per the CLI protocol profiles, with a Chinese product entry in the Terminal Hall / CTO maintenance area: the CTO selects an employee, enters one line, and OPC explicitly initiates the send; before sending, the tool's dedicated standalone-line ready prompt must be observed so input is never misfired into a plain terminal; after sending, completion is judged by the profile's standalone-line ready prompt (`codex>` / `claude>` / `gemini>`) or the round-end signal; non-interactive backends, backends without a configured ready prompt, or seats that are not ready are rejected in Chinese; the ready real-terminal path for auto input loops has been verified with fake REPL + tmux seats for real sends, completion-signal stops, and no Boss chat / no job archive side effects, and auto loops vs. manual rounds are distinguished by separate terminal log tags; timeouts never kill seats, create job archives, or start model tasks; the Boss view does not show this entry.
- The real-terminal auto interaction loop is wired into the CTO maintenance area: the CTO must explicitly provide task context and a maximum turn count; OPC generates one line of next-step text per round and sends it to the current employee's real terminal seat; before sending, a read-only preflight checks the terminal workspace, the employee seat, and the dedicated ready prompt, and rejects directly in Chinese without consuming turns when not ready; auth anomalies, busy, transient anomalies, or wait timeouts stop the loop; this entry writes no Boss chat, creates no CLI job archives, and does not bypass Delivery & Acceptance; unit tests can still verify the gate through injected send closures.
- Real-terminal-seat readiness judgment is upgraded to "the most recent non-empty line fully matches the dedicated prompt" (`CLIInteractionProfile.endsWithReplReadyPrompt`), and manual single-round REPL and auto-loop preflight share the same judgment, so stale `codex>` / `claude>` / `gemini>` prompts lingering in long scrollback no longer misclassify a seat still "processing..." as ready. Each real-terminal auto-loop start outputs a Chinese "readiness check" audit written to three places: (1) the `[OPC Auto-Loop Readiness Audit]` block in the employee terminal log, (2) `TerminalAutoInteractionLoopReport.summaryText`, (3) a structured `VerificationRecord("Real Terminal Auto-Loop Readiness Audit")` (preflight passed → Passed, preflight rejected → Has Warnings); the CTO maintenance view reads it via `selectedProductLatestTerminalAutoLoopReadinessAudit` and `selectedProductTerminalAutoLoopReadinessAuditSummary()`; `multiAgentArchitectureAuditText()` also ends with a one-line Chinese summary. The audit body does not expose underlying parameters, `rawValue`, backend signatures, or ANSI; the Boss Command Center and Delivery & Acceptance Center filter out this maintenance record.
- The Boss Command Center, product-detail delivery area, Delivery & Acceptance Center, and automated-acceptance drawer all read the same delivery-acceptance filter list; real terminal workspace, terminal log refresh, persistent-terminal audit, CLI-chain preflight, product isolation health check, runtime-session audit, anomaly recovery, history index/archive, and safety checkpoints stay as technical maintenance records in the CTO maintenance view, while real delivery evidence stays visible.
- Prompt recognition passes through `CLIInteractionProfile.normalizedForPromptMatching(_:)` before contains/endsWith checks: simulates a terminal by "line + cursor", stripping ESC CSI / OSC control sequences; recognizes `CSI K` / `ESC[0K` clearing cursor-to-end-of-line and `ESC[2K` clearing the whole line; CR only resets the cursor to column 0 without erasing the tail; BS only moves the cursor, and only the shell-standard `\b \b` overwrites with spaces; other C0 bytes and DEL are dropped; Chinese, `\t`, and `\n` are preserved. Prompts wrapped in color or terminal titles are recognized correctly; a bare `processing...\rcodex>` is rejected because the tail `sing...` is still displayed; the prompt is ready only when a line-clearing control like `CSI K` / `ESC[2K` appears or subsequent characters fully overwrite the residual tail. This recognition enhancement is CTO-maintenance-side CLI tolerance; the Boss Command Center does not show it, and no ANSI / `rawValue` / full command arguments are exposed.
- The same normalization also feeds auth-anomaly / busy / transient-anomaly diagnostic-signal detection: colored `error: not authenticated`, OSC-wrapped `warning: rate limit`, CR-overwritten `error: please login`, shell-standard `\b \b`-corrected `error: not authenticated`, colored `error: 429`, and `error: network timeout` are all recognized; meanwhile the `isDiagnosticLine` prefix gate and the `lineContainsAnyDiagnosticSignal` word gate stay unchanged, so the colored path `/var/log/timeout-429-busy.log`, the colored identifier `NetworkTimeout429BusyProbe`, and `timeout / network / 429 / busy` inside OSC-wrapped Chinese prompt echoes are still not misjudged. The auth-anomaly → transient-anomaly → busy status priority is also kept, and same-line mixes like `error: 429 rate limit` still report the transient anomaly first.
- Chinese diagnostic phrases: the codex / claude / gemini profiles each get their Chinese auth ("unauthorized" / "please log in" / "please log in again" / "auth failed" / "auth anomaly" / "login failed"), busy ("service busy" / "already busy" / "already running" / "rate limited" / "quota exhausted" / "please retry later" / "overloaded" (Claude only)), and transient-anomaly ("request timeout" / "connection timeout" / "network anomaly" / "network error" / "connection failed" / "temporarily unavailable") phrases, and `diagnosticPrefixes` gains Chinese line-start prefixes. Chinese phrases hit via the two-stage "substring hit + neighboring characters must not be `/\-_.` path marks" check, avoiding false hits from Chinese paths or ordinary user-prompt echoes.
- Real-terminal auto-loop stop audit: when a real-terminal-path loop stops on auth anomaly / CLI still busy / transient anomaly / wait timeout, a `VerificationRecord("Real Terminal Auto-Loop Stop Audit")` (status "Has Warnings") and a `[OPC Auto-Loop Stop Audit]` terminal-log block are written in sync; the body is the Chinese stopReason.title + operatorHint, without exposing the underlying enum; the new title is registered in `technicalMaintenanceVerificationTitles` and auto-filtered from Boss/delivery views; the CTO maintenance view reads it directly via `selectedProductLatestTerminalAutoLoopStopAudit`.
- Employee recovery advice is wired into the Terminal Hall / CTO maintenance area: it shows a Chinese summary and suggested actions from the latest status observation; auth anomalies and busy continue to block automatic reopening; only "transient anomaly" offers a controlled "Manual Retry Once" entry, requiring an explicit CTO click, and a single retry never enters an implicit loop nor appends unconfirmed next-round input to the CLI; this panel is not in the Boss Command Center, writes no Boss chat, no acceptance records, and no job archives.
- The CTO maintenance area provides a "Persistent Terminal Availability Audit": read-only checks that the terminal tool, real terminal sessions, control window, and employee seats are all present; no model tasks, no job archives, no employee-state changes; the same state is wired into the "Multi-Employee Architecture Health Check" as its seventh check item. The architecture health check only reads the in-memory snapshot from the last audit/startup, so UI refresh does not repeatedly re-read terminal state.
- The Communication Gateway is layered: outbound reports can be generated and sent to ready channels; inbound phone instructions must pass channel-enabled / instruction-permission / config-ready gates; HMAC, timestamp, and nonce verification are in place as the security primitives fronting the future external inbound service.
- The local history index is wired in as a sidecar index with the main snapshot still authoritative; the Terminal Hall maintenance area can rebuild and audit the history index and copy old records into local archive tables.

## Architecture principles

### 1. Company hierarchy

```text
Boss
  -> CTO Supervisor
      -> Employee Agent
      -> Review Agent
      -> Artifacts/Acceptance
      -> Boss report/approval
```

The Boss does not directly manage complex branches; the CTO is the default dispatcher.

### 2. Message bus

A new `AgentMessageEnvelope` records all agent collaboration through messages:

- CTO dispatches tasks to employees.
- Employees report results back to the CTO.
- CTO requests reviewer acceptance.
- Reviewers give feedback to the CTO.
- CTO submits reports or approval requests to the Boss.

Messages are not ordinary chat; they are backend collaboration records. Ordinary chat is natural language shown only to the Boss.

### 3. Task graph

The existing `CompanyTask` remains the task node. This round adds a lightweight task-graph view:

- Goal decomposition tasks.
- Parallel employee tasks.
- Review tasks.
- Boss approval tasks.

The closed-loop tracking layer now derives `MultiAgentTaskGraphNode` / `MultiAgentTaskGraphEdge`: `CompanyTask` stays the real task node, but explicit edge evidence is generated from messages, approvals, and acceptance records, showing CTO dispatch, employee report-back, review conclusions, and Boss decision feedback. The architecture health check's explicit task-graph item also checks derived nodes and edges. If more complex dependencies are needed later, the derived graph is upgraded to a persisted task graph.

The delivery evidence store and Acceptance Gates in the architecture health check must hang on the same closed-loop trace: only `MultiAgentClosureTrace.artifactIDs` / `verificationIDs` / `reviewGateIDs` can close the corresponding modules. Scattered product reports, acceptances, or gate records only count as "to be strengthened" and cannot replace one complete evidence chain from CTO decomposition to Boss acceptance.

### 4. CTO Supervisor Loop

A new deterministic scheduling entry:

- `startCTOSupervisorGoal(goal:)`
- `advanceCTOSupervisorLoop()`

Phase one uses deterministic logic; the planning part goes to a real model later:

1. Create the CTO decomposition task.
2. Create tasks for UI/engineering/review employees.
3. Write to the work queue.
4. Dispatch through the message bus.
5. Employees notify the CTO when done.
6. The CTO triggers review and Boss reporting.

### 5. UI layering

The Boss Command Center only shows:

- Whether Boss approval is pending.
- Product progress.
- Recent deliveries.
- Employee progress summaries.

The flow graph / employee workbench can show:

- Agent message chains.
- CTO scheduling status.
- Employee queues.
- Review report-backs.

## Code scope in place

### Added

- `AgentMessageKind`
- `AgentMessageStatus`
- `AgentMessageEnvelope`
- `CompanyStore.agentMessages`
- `CompanyStore.selectedProductAgentMessages`
- `CompanyStore.postAgentMessage(...)`
- `CompanyStore.acknowledgeAgentMessage(...)`
- `CompanyStore.startCTOSupervisorGoal(goal:)`
- `CompanyStore.advanceCTOSupervisorLoop()`

### Reworked

- `CompanySnapshot` gains `agentMessages`, schema upgrade.
- `createTask` / `enqueueWorkItem` / `completeWorkItem` / `requestApproval` gain message-bus integration.
- The internal project constitution (local only) change log adds this round's upgrade.
- UI adds a lightweight "multi-agent collaboration chain" view, placed in the flow graph / employee workbench first, not piled onto the Boss Command Center.

### Tested

- Starting a CTO goal creates tasks, work queue items, and messages.
- Non-product-team members cannot receive that product's messages.
- Employees report results back to the CTO after completing work items.
- Review tasks generate review-request messages.
- Messages persist with the snapshot.
- Boss approval requests can be traced to their source through the message chain.

## Acceptance criteria

- `swift test --no-parallel` all pass.
- New tests cover the multi-agent message bus and CTO scheduling.
- The app opens.
- Computer Use can see at least one visual entry or state related to multi-agent collaboration.
- The Boss Command Center does not gain a pile of backend control buttons.

Current acceptance status:

- `swift test` covers the message bus, CTO scheduling, employee handover, review/rework/re-review, Boss approval feedback, closed-loop tracing, the delivery evidence store, and Acceptance Gates.
- `multiAgentArchitectureClosureDrillCompletesCollaborationChain` asserts that after the real terminal workspace starts and completes the closure drill, all seven architecture checks pass at 100% completion.
- The Terminal Hall provides CTO entries such as "Multi-Employee Architecture Health Check", "Run Closure Drill", and "View Closure Details"; the Boss Command Center keeps results, risks, approvals, and delivery entries without stacking backend buttons.
- The CLI interaction status observer has added diagnostic-context matching tests: `timeout`, `network`, `429`, `busy` inside path names, identifiers, and ordinary prompts do not trigger transient-anomaly or busy, while real errors, auth, and quota/busy output are still classified.
- The auto-input-loop safety gate and internal coordinator have added tests: missing task context is rejected, exceeding the max turn count stops, external/multiline input is rejected, auth anomalies, busy, transient anomalies, and timeouts stop, and completed state ends; selecting the Boss, off-team employees, or missing CTO task context never calls the send closure; the Boss Command Center enumeration does not add this entry.

## Explicit cross-employee handover (employee → employee)

- `AgentMessageKind.employeeHandoff` is structured handover evidence between employees, distinct from CTO-mediated dispatch, report-back, review, and approval.
- `CompanyStore.postEmployeeHandoff(productID:fromAgentID:toAgentID:taskID:subject:body:)`:
  - Only allows records between two different non-Boss employees inside the same product team;
  - cross-product, cross-product-task, Boss-involved, self-handover, or missing-employee cases return nil and write a risk event;
  - writes to `agentMessages` (status pending confirmation) without writing Boss home chat, creating `.opc/jobs/`, or triggering model tasks, satisfying § 5.3's "cross-employee handover must leave message and artifact records" compliance requirement;
  - `selectedProductID` is the default productID and can be passed explicitly so current-product isolation cannot be bypassed by misplaced calls.
- The closure drill `runMultiAgentArchitectureClosureDrill` inserts an "engineer → reviewer" handover between engineering completion and review start, so the closed-loop trace's message evidence chain includes task dispatch, employee handover, review requests, employee report-back, approval requests, and approval results.
- The employee workbench "My Collaboration Inbox", product detail "Employee Collaboration Chain", flow graph "Message Flow / Collaboration Chain", and the "Employee Collaboration Message Center" all reuse `AgentMessageRow` and automatically show the Chinese title "Employee Handover" and a blue handover icon; the Boss Command Center does not show it.

## Single-message confirmation in the employee inbox (employee → employee)

- `CompanyStore.acknowledgeSelectedAgentMessage(_ messageID:)`: single confirmation requires "current product + `toAgentID == selectedAgentID` + pending confirmation"; failing any condition returns false with no state change and does not affect outbound messages, other employees' messages, or cross-product messages.
- On success, `acknowledgedAt` is written and a Chinese "employee collaboration inbox: one message confirmed" event is appended to the event stream. No Boss home message, no model task, no job archive.
- `AgentMessageRow` accepts an optional `onAcknowledge` closure: the employee workbench "My Collaboration Inbox" and the employee message center (`AgentMessageCenterSheet(scope: .agent)`) show the Chinese button "Confirm This Message" on inbound pending messages; product-level panels (product detail "Employee Collaboration Chain", flow graph "Message Flow / Collaboration Chain", `AgentMessageCenterSheet(scope: .product)`) stay read-only and never confirm on someone else's behalf.
- The batch "Mark My Messages Read" button is kept: single confirmation is the per-message closure path and the batch button is the cleanup path; they coexist. The employee handover audit `runEmployeeHandoffAuditForSelectedProduct` can reduce the pending count to passing under both paths.

## Quick employee-handover launch from the employee workbench (employee → employee)

- `CompanyStore.selectedAgentHandoffRecipients` / `selectedAgentHandoffTaskCandidates` / `postSelectedAgentHandoff(toAgentID:taskID:subject:body:)`: with the currently selected employee as sender, filter same-product-team, non-Boss, non-self employees as handover recipients, and the current product's tasks whose `ownerID` equals that employee as linkable tasks (sorted by status priority).
- Internally it still calls `postEmployeeHandoff`, keeping the same-product gate and Boss/cross-team protections; when subject or body is empty, the message bus falls back to Chinese copy.
- `AgentDeskWorkspace` adds a Chinese "Initiate Employee Handover" panel right next to "My Collaboration Inbox": a dropdown to pick the recipient, a dropdown to pick the task (including a "No Linked Task" option), input fields for subject and body, and a send button; on success it shows "Written to the employee collaboration message bus; awaiting confirmation in the recipient's inbox" and clears the inputs.
- Selecting the Boss / an employee not in a team / no available recipient shows Chinese empty states and disables sending; the panel is not in the Boss Command Center; no model tasks, no job archives, no Boss home messages. The Store layer rejects attaching tasks the current employee does not own to a quick handover, so stale UI selections or external calls cannot cross-wire tasks.
- Manual handovers and closure-drill handovers reuse the same bus and are counted together by the "Employee Handover Pending Confirmation Audit".

## Employee handover pending-confirmation audit (CTO backend)

- `CompanyStore.employeeHandoffAuditText(staleAfter:)` / `runEmployeeHandoffAuditForSelectedProduct(staleAfter:)`: a purely read-only audit that tallies employee handover messages (`AgentMessageKind.employeeHandoff`) per current product: total, pending, confirmed, and timed-out-pending. Default threshold 180 seconds, minimum 60.
- The report is written to `VerificationRecord("Employee Handover Pending Confirmation Audit")`, the CTO system message, and the event stream; timed-out-pending exists → status failed plus an "employee handover timed out pending confirmation" risk event; only pending exists → status warning; nothing pending → status passed.
- The audit does not modify handover status, create `.opc/jobs/`, or trigger model tasks; clearing pending confirmations remains the job of the corresponding employee clicking "Mark My Messages Read" in "My Collaboration Inbox".
- The UI entry is in `LocalMaintenanceCenter` (CTO and operations backend): a Chinese "Run Employee Handover Audit" button plus an always-visible "Employee Handover Audit Preview" card; the Boss Command Center does not show it.
- Cross-product isolation: only the current product's employee collaboration messages are traversed; after switching products, product B cannot see product A's handovers.

## CLI job ghost audit (CTO backend)

- `CompanyStore.jobArchiveStaleAuditText(staleAfter:)` / `runJobArchiveStaleAuditForSelectedProduct(staleAfter:)`: scans the current product root's CLI job archives and identifies old archives still marked running whose update time exceeds the threshold but have no real employee runtime occupancy.
- The actual audit writes these ghost jobs back as interrupted, preserving the original status, interruption time, and a Chinese interruption reason; jobs with real runtime occupancy or not yet timed out only enter the report and are never interrupted.
- The report only writes `VerificationRecord("CLI Job Ghost Audit")` and the event stream — no Boss chat, no employee collaboration messages, no new job archives, no model tasks.
- The UI entry is in `LocalMaintenanceCenter`: a Chinese "Run CLI Job Ghost Audit" button plus a "CLI Job Ghost Audit Preview" card; the Boss Command Center does not show backend maintenance complexity.
- It pairs with the runtime session health audit: employee runtime sessions are bound to product ownership to detect product drift; after switching products, the same employee's other-product sessions are not treated as current-product runtime occupancy.

## Chinese localization of operations preflight visible copy

- Preflight in the Terminal Hall, CLI-chain stress-test preflight, and the launch plan only show Chinese product wording such as "Run Summary", "Run Checklist", and "Task Injection" — never underlying command parameters, prompt placeholders, or debug switches.
- The runtime session health audit only shows Chinese summaries such as "abnormal occupancy", "most recent error", and "backend config match/mismatch" — no underlying signatures, internal status enums, or error field names.
- The CLI and workspace isolation health check only shows Chinese summaries of employee workspaces, session logs, runtime sessions, and isolated execution areas — no internal file names, metadata paths, or underlying isolated-execution-area directories.
- The real terminal workspace preview only shows whether the terminal tool is ready, the number of connected seats, and each employee's execution-location summary — no underlying session names, window names, or terminal tool paths.
- The local maintenance area's isolation health check and real terminal workspace use default summaries plus collapsed details: the default view serves CTO/Boss-side judgment; collapsed details are only for operations troubleshooting and are not ordinary visible copy.
- The employee workbench's session-status summary converts English exit markers into Chinese exit-code summaries; employee profiles only show the CLI tool name, never full underlying arguments.
- Terminal logs for CLI tasks and chat chains show only Chinese run summaries — no full command arrays, command arguments, or internal session-log file names; abnormal-occupancy recovery and safety checkpoints also show only Chinese status and local archive summaries.
- Employee execution prompts only tell the model "the employee workspace is maintained locally by OPC"; absolute paths under `Library/Application Support` are never handed to the model, so the model cannot echo internal paths into user-visible replies.
- User-configurable names such as Codex, Claude Code, Gemini, OpenAI, model names, and necessary paths are kept; what is hidden is system-generated internal parameters, which does not affect real execution.

## Reviewer personal review queue (employee workbench)

- `CompanyStore.selectedAgentReviewQueue` only returns the current product's tasks owned by the currently selected employee with status "pending review"; the employee must be a reviewer or have the review skill and must have joined the current product team.
- `CompanyStore.completeReviewByOwner(taskID:summary:)` is the reviewer sign-off path: the task moves to "completed", a "review completed" collaboration message is written, the Acceptance Gate updates to "verification passed", and a Chinese event is appended; no Boss home message, no model task.
- `CompanyStore.rejectReviewByOwner(taskID:reason:)` is the reviewer reject-and-return path: the task returns to "assigned", a "review completed" collaboration message is written, the Acceptance Gate updates to "verification warning", and a Chinese risk event is appended; no Boss home message, no model task.
- `AgentMessageEnvelope.reviewOutcome` records the review result as a structured field: `.passed` for approval, `.rejected` for rejection. Historical messages without this field keep nil so old snapshots load fine; audits and closed-loop tracing do not parse message subjects to determine outcomes.
- If the rejected task is a CTO-loop task like "Review Acceptance: Goal", the Store finds the matching "Employee Execution: Goal" task, returns it to "assigned", and puts it back in the executing employee's queue; the re-dispatch message body includes the rejection reason but starts no model tasks, creates no CLI job archives, and writes no Boss home messages.
- `CompanyStore.selectedAgentReworkQueue` filters the current employee's own rework queue items; the employee workbench "Employee Work Queue" shows a rework count, and queue cards highlight the reviewer's rejection reason with a "Rework" tag and "Reason: …", so engineers do not have to dig through CTO-backend messages.
- `CompanyStore.selectedProductReworkSummaryText()` outputs a current-product rework-tracking summary for the CTO backend: rework queue item count, tasks, statuses, executing employees, and rejection reasons. The summary sits in the "Multi-Employee Architecture Health Check" area, not the Boss Command Center.
- After an engineer completes a rework work item, `completeWorkItem` recognizes the "rejection reason" and reopens the same-goal "Review Acceptance: Goal" task: the review task enters "pending review", a "post-rework re-review" message and a pending-review gate are written, and the completed rework item is removed from the engineer's rework queue; the reviewer's personal pending panel labels it with the Chinese tag "Post-Rework Re-Review".
- After a reviewer signs off the CTO loop's "Review Acceptance: Goal", `completeReviewByOwner` automatically submits the same-goal "Boss Approval: Goal" to the Boss decision center: it writes a CTO-advance message, creates a Boss approval request, and avoids duplicating the same Boss approval.
- After the Boss approves the CTO loop's "Boss Approval: Goal", `decideApproval` closes the same-goal group of CTO decomposition, employee execution, review acceptance, and Boss approval tasks as complete, and writes the acceptance report, the Boss acceptance-passed record, and the acceptance-completed message; ordinary risk approvals keep the "continue running after approval" semantics, unaffected by this final-delivery rule.
- After the Boss rejects the CTO loop's "Boss Approval: Goal", `decideApproval` triggers rework feedback only within the same-goal loop: the Boss approval task leaves the risk list and waits for re-submission after rework, the employee execution task re-enters the executing employee's rework queue, and the review acceptance task returns to await re-review; after rework completes it re-enters the reviewer's personal pending queue, and a passing re-review can submit a new Boss approval. Ordinary risk approvals keep the "blocked after rejection" semantics.
- Final-approval approval/rejection feedback uses the approval record's own productID when writing tasks, queues, messages, and events; even if the Boss processes an old approval from another product tab, the rework queue is never written to the currently selected product. Public manual enqueue entries still only allow current-product tasks into current-product queues.
- The employee workbench shows a "My Pending Review Tasks" panel in reviewer view with two real actions, "Complete Review" and "Reject & Return for Rework"; review opinions enter the collaboration messages and Acceptance Gates.
- This entry belongs to the employee execution view and is not in the Boss Command Center; the Boss still only sees the CTO-consolidated results, risks, approvals, and deliveries.

## Closure drill retrospective summary (CTO backend)

- `CompanyStore.selectedProductClosureDrillSummaryText()` outputs the most recent multi-employee closure drill retrospective summary for the current product: goal, status, completion, tasks, messages, approvals, review gates, artifacts, acceptance counts, and next-step suggestions.
- The summary shows in the CTO backend's "Multi-Employee Architecture Health Check" panel (`ClosureDrillSummaryCard`), not in the Boss Command Center.
- With no closure drill, a unified Chinese empty state is shown: "No multi-employee closure drill has been run yet. Please click 'Run Closure Drill' in the CTO backend first…".
- No backend, CLI, model, or other operations details are exposed; details are still handled by "View Closure Details" and "Open Decision Center".
