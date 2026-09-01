<!-- Translated from CLI_ORCHESTRATION.md; the Chinese original remains authoritative for internal history. -->

# CLI Orchestration Design

Last updated: 2026-05-07

Current status: CLI orchestration has reached the single-user local formal-use baseline. Codex / Claude Code / Gemini / API backends all have productized configuration and run paths; real terminals, job archives, status observation, exception recovery, and token-budget boundaries are wired in. This document describes the design principles and maintenance boundaries; the latest acceptance records live in the internal project constitution (local only).

## Goals

OPC Company treats subscription command-line tools as schedulable employees. The product never scrapes browser sessions, never uses cookies, and never fakes web logins; it only launches official CLIs, records execution, saves job archives, and folds the results into the CTO coordination, acceptance, and delivery evidence chain.

## Supported subscription CLI backends

### Codex

Default roles:

- CTO agent
- Product architect
- Review agent

Command form:

```bash
codex exec --skip-git-repo-check -m <model> "<prompt>"
```

### Claude Code

Default roles:

- Code engineer
- Refactor engineer
- Test-fix engineer

Command form:

```bash
claude -p --permission-mode auto --model <model> --effort <effort> "<prompt>"
```

### Gemini CLI

Default roles:

- UI designer
- Multimodal analyst
- Visual reviewer

Command form:

```bash
gemini -p --model <model> "<prompt>"
```

## Execution model

Every task becomes a local job:

```text
.opc/jobs/<job-id>/
  brief.md
  cto-plan.md
  agent-task.md
  transcript.log
  artifacts/
  status.json
```

The current runner must keep the following chain:

- Create the job directory.
- When code modification is allowed, create or select an isolated source execution area.
- Generate the command from the employee profile and backend configuration.
- Write stdout and stderr to the Terminal Hall.
- Write the full transcript to the job directory.
- Convert completed, failed, or interrupted results into company events.
- Write a Chinese summary to the CTO.

Current job-archive behavior:

- Every real "Run" click creates `.opc/jobs/<job-id>/` under the current product working directory.
- The job directory contains `brief.md`, `agent-task.md`, `status.json`, `transcript.log`, and an `artifacts/` directory.
- `status.json` is written as running before the process starts, updated to completed or failed after the command finishes, and records the exit code.
- `transcript.log` records the stdout and stderr returned by the command-line process.

## Token budget boundaries

- The first run includes the employee's operational profile plus this round's task.
- CLI session resumes for the same product, same employee, and same backend only send this round's task plus a one-line context hint, never re-sending the full employee profile.
- Work-order prompts keep only a small number of rules, tools, and project-file clues from the import report; long full lists stay in the import report or the job archive.
- The collaboration message bus stores short subjects and limited bodies; long reports should be written to artifacts or audit archives.
- The Terminal Hall default report + Run All first shows a Chinese confirmation, so one misclick cannot consume multiple employees' quota.

## Busy / auth handling boundaries

- Normal busy: do not interrupt when there is output, file changes, test runs, or an explicitly long task.
- Abnormal busy: when there is no output for a long time, no file changes, the pane has returned to the prompt, or logs show socket/API/session failures, diagnose first, then end the abnormally idling task and resume with smaller split tasks.
- Auth anomalies, busy, transient exceptions, and wait timeouts are written to Chinese diagnostics by the status observer; unconfirmed next-round input is never appended to the CLI automatically.
- The job directory enters the `ArtifactRecord` collection as "CLI job archive: <employee>", but is classified as a **technical maintenance artifact** (`CompanyStore.technicalMaintenanceArtifactTitlePrefixes` covers the "CLI job archive: " prefix): the CTO tracks execution evidence through the maintenance artifact center (`selectedProductRecentMaintenanceArtifacts`); the Boss Command Center, product-detail delivery area, Delivery & Acceptance Center, and the operations-suite acceptance drawer all filter this record out via `selectedProductDeliveryArtifacts`, so backend complexity never surfaces on the Boss home screen. Safety checkpoints / closed-loop audit reports / local file indexes are likewise classified as maintenance artifacts.

Current isolation health check:

- Verify each executable employee has its own local employee workspace.
- Verify each employee workspace has session logs.
- Verify each executable employee has running sessions.
- Create a stable `.opc/worktrees/<agent>/source` isolated source execution area for code/test employees. Products with a code repository use the independent repo workspace; non-repo products recognizable as project roots use source-snapshot isolation; when a project root cannot be safely identified, only the isolation directory is registered and the execution directory is never silently switched.
- CLI preflight and the launch plan distinguish the product working directory from the real execution directory. Code/test employees only run inside the isolated directory after it contains a real source execution area; otherwise they keep running in the main working directory with a clear note about the isolation status.
- The default visible preview shows only Chinese summaries: whether the employee workspace exists, whether session logs exist, runtime session status, and whether code-class employees use the isolated execution area or the main working directory; metadata directories, internal session-log file names, and internal paths of isolated execution areas are not shown. Paths needed for troubleshooting live in a collapsed "Expand Operations Details" section, not in default screenshots or normal copy content.

Runtime session health audit:

- The CTO/operations backend adds a "Run Session Health Audit" button (`LocalMaintenanceCenter`), calling `CompanyStore.runRuntimeSessionHealthAuditForSelectedProduct(staleAfter:)`, with a default abnormal-occupancy threshold of 180 seconds (minimum 60 seconds).
- The audit covers the current product team's **executable employees**, checking each one: whether a runtime session exists; whether the session's product ownership belongs to the current product; whether status, capability, and backend configuration match the current employee profile; whether the subscription CLI resolves on this machine; for interface-mode backends, whether the interface URL, interface key, and model name are all present; whether runtime occupancy exceeds the threshold; and failure counts and the most recent error.
- Any anomaly (missing command, backend drift, product drift, missing session, abnormal occupancy, recent failure) → `VerificationRecord` status `.warning`; all healthy → `.passed`. The report is also written to the CTO system message and the event stream.
- **Read-only, no state changes**: it does not modify the running-employee list, does not change employee status, does not write employee collaboration messages, does not create job archives, and does not trigger model tasks. Abnormal occupancy is only highlighted in the report as "advisory, not recovered this run"; actual recovery remains the job of the "Recover Abnormally Occupied Employee Session" button (audit-diagnose first, then decide whether to recover — a deliberate two-stage design).
- Runtime session creation and reuse are both bound to the current product ID; after a product switch, the same employee's old-product session is never silently reused, and abnormal-occupancy recovery only handles sessions of the current product or old-snapshot sessions without a product marker.
- The visible report does not expose underlying backend signatures, internal status enums, or error field names — only Chinese summaries.
- The abnormal-occupancy recovery report must use Chinese status names and Chinese field descriptions, never raw internal enums or field names such as `busy`, `timedOut`, `lastUsedAt`.

CLI job ghost audit:

- The CTO/operations backend adds a "Run CLI Job Ghost Audit" button and a resident preview card (`LocalMaintenanceCenter`), calling `CompanyStore.runJobArchiveStaleAuditForSelectedProduct(staleAfter:)`.
- The audit only scans job status files under the current product root. A job still marked running whose update time exceeds the threshold and whose employee has no real runtime occupancy is treated as a ghost running job.
- Ghost jobs are written back as interrupted, preserving the original status, the interruption time, and a Chinese interruption reason; jobs with real runtime occupancy or not yet timed out are only recorded in the report and are never interrupted.

Terminal log visible summaries:

- CLI tasks, employee chats, and chat corrections show only the tool name, reasoning effort, execution location, and task summary in the Terminal Hall — never echoing the full command array.
- Default UI copy uses Chinese role wording: the right-side communication panel shows "Smart Control / Communication" and "Command Channel", and the Company Floor shows "OPC Smart Company Command Cockpit" and "Local Employee Formation"; mixed Chinese/English labels such as `AI Control`, `Agent Formation`, `COMMAND LINK`, `Codex CTO` do not enter the default visible copy. Codex, Claude Code, Gemini, and model names remain as brand/configuration names.
- `model_reasoning_effort`, `--skip-git-repo-check`, environment variable names, full prompt arguments, local session-log file names, and full tool paths must not appear in default terminal logs; full paths or old commands already present in old logs are compressed into tool names or hidden summaries at the display layer.
- Full commands may still be kept in the CLI job archive for operations review, but the Boss/CTO default UI only sees Chinese summaries.
- The report is written to `VerificationRecord("CLI Job Ghost Audit")` and the event stream; no Boss chat, no employee collaboration messages, no new job archives, no model tasks.
- The visible report uses short labels like "Job 1 / Job 2", never exposing internal on-disk job IDs or status field names; real job IDs remain in the job archive files.

Abnormal-occupancy session recovery:

- The CTO/operations backend adds a "Recover Abnormally Occupied Employee Session" button (in `LocalMaintenanceCenter`), calling `CompanyStore.recoverStaleRuntimeSessionsForSelectedProduct(staleAfter:)`.
- Default threshold 180 seconds (minimum 60). Only employee runtime sessions meeting all three conditions are handled:
  1. still in `runningAgentIDs`;
  2. the matching `AgentRuntimeSession.state == .busy`;
  3. `lastUsedAt` older than the threshold.
- Normal busy tasks (recent `lastUsedAt`) are never interrupted.
- On recovery, the session is removed from `runningAgentIDs`, the runtime session is set to `.timedOut`, the failure count is incremented, the employee terminal log is written, `appendEvent(.risk)` fires, and a `VerificationRecord("Abnormal Occupancy Session Recovery")` plus CTO report are written.
- No model tasks are triggered, no `agentMessages` bus writes, no `.opc/jobs/` archives; the next task must still start from the OPC run entry to preserve the preflight, job archive, and acceptance chain.

Real terminal workspace:

- The CTO backend can start a real terminal workspace for the current product; the underlying session name is generated stably per product, but the visible report shows only a Chinese summary.
- Each executable employee gets an independent terminal seat, with the current directory set to the real execution directory computed by OPC; code/test employees preferentially enter the isolated source execution area.
- Starting a terminal seat only writes the employee identity, role, and execution-directory hint; it never auto-executes model tasks.
- Tasks are still launched from the OPC run entry, preserving run preflight, `.opc/jobs` job archives, the message bus, delivery evidence, and Acceptance Gates.
- After startup, the app writes the terminal seat status and terminal snippets back to the employee terminal log and generates a CTO report and verification record.
- The backend "Refresh Real Terminal Logs" re-captures each employee terminal seat's content, appends it to the matching employee terminal log, and writes a CTO report and verification record; if the workspace does not exist, it only reports the gap and does not start employee tasks.
- The visible preview does not show underlying tmux paths, session names, window names, or pane identifiers — only whether the terminal tool is ready, the number of connected seats, and each employee's execution-location summary.
- The Terminal Hall maintenance area provides a "Persistent Terminal Availability Audit": read-only checks of whether the terminal tool is ready, whether real terminal sessions exist, whether the control window is connected, and whether all employee seats are present; the report goes to the CTO message, events, and verification records, without starting model tasks, creating job archives, or changing employee status.

Persistent CLI session protocol:

- Codex / Claude Code / Gemini first enter a unified "interaction protocol profile" layer: each profile records protocol shape, session mode, recognizable session-ID fields, configurable ID format, ready signal, round-end signal, busy signal, auth-anomaly signal, transient-anomaly signal, and suggested timeout.
- Protocol shape is currently used for classification and future branching preparation; the status observer still classifies output by the unified priority. The suggested timeout is wired into employee task runs, so long-lived protocols like Codex / Claude / Gemini get a longer wait window by default.
- The round-end signal can come from the CLI's own output or from the task-boundary marker OPC writes; when calling the status observer, pass this round's newly added output where possible, so historical terminal scrollback does not skew the judgment.
- Preflight shows only Chinese summaries, e.g. "supports per-product resume, recognizes session-ID keywords, monitors ready/busy/auth-anomaly/transient-anomaly"; underlying prompts, arguments, internal field names, and error snippets never enter the Boss view.
- The first-version status observer is in place: it classifies output by profile into continue-interaction, awaiting-reply, round-ended, busy, auth-anomaly, or transient-anomaly, and carries the recognized session ID. It serves as a testable state-machine foundation layer; the real long-running input loop connects later.
- The status observer must distinguish protocol state signals from anomaly diagnostic signals: protocol signals such as ready and round-ended are recognized by profile text; auth anomalies, busy, and transient anomalies are only recognized in diagnostic-context lines such as error prefixes, auth failures, quota/busy, and network/timeout. Single-word anomaly signals must match whole words and skip tokens containing path or identifier characters, so `timeout`, `network`, `429`, `busy` inside paths, file names, prompt echoes, or ordinary prose are not treated as real anomalies.
- After an employee task ends, OPC observes this round's raw output and writes the result into the runtime session archive, and appends a Chinese "OPC Interaction Status" summary to the employee terminal log on state changes. The summary does not expose the underlying session ID, writes no acceptance record, does not change the command exit code, does not auto-retry, and does not bypass human review. Whether a task is complete still rests on the exit code and job boundary; the status observer is primarily for diagnosing auth, busy, and transient anomalies.
- Real-terminal seat polling uses the same status observer, but observations are diagnostic input only: when a session ID, ready hint, busy hint, or auth-anomaly hint is captured, the system keeps the latest state for timeout summaries and later archives; only a captured OPC exit marker plus exit code counts as this round's task being complete.
- To keep long output from washing out the job boundary, persistent-terminal execution reads a larger terminal history window; regression tests cover capturing `__OPC_JOB_EXIT_<id>__` after more than a thousand lines of output.
- Status-observation results currently drive exactly one conservative behavior: when this round's output shows an auth anomaly or the tool still busy, OPC blocks automatic reopening after failure, avoiding repeated wasted CLI restarts while the user is not logged in or the previous round has not finished. This gate only applies to the system's automatic anomaly-recovery path and does not stop the Boss or CTO from manually running employee tasks again; once the user completes the CLI login, the next manual task succeeding moves the state from auth-anomaly to continue-interaction.
- Recovery suggestions are saved to the runtime session archive as strongly typed actions plus Chinese titles and Chinese operation hints. Consumers use enums; the UI shows only Chinese titles/hints, never raw enum values, underlying session IDs, or internal field names. Current actions cover hinting, auto-reopen suppression, and showing/hiding the controlled manual-retry entry; they do not clear session IDs, write acceptance records, or directly start model tasks.
- Real-terminal-seat preflight and the readiness check before single-round REPL sends have been upgraded to "the most recent non-empty line fully matches the dedicated prompt" (`CLIInteractionProfile.endsWithReplReadyPrompt`). Stale `codex>` / `claude>` / `gemini>` prompts lingering in tmux scrollback no longer misclassify a seat still "processing..." as ready to continue; the old `containsREPLReadySignal` is only kept for the state machine observing incremental deltas, so a seat is not misjudged as not-ready when response lines follow the prompt. Each time a real-terminal auto loop starts, a Chinese "readiness check" entry is written synchronously to three places: the `[OPC Auto-Loop Readiness Audit]` block in the employee terminal log, the report `summaryText`, and a structured `VerificationRecord("Real Terminal Auto-Loop Readiness Audit")` (preflight passed → "Passed", preflight rejected → "Has Warnings"); the CTO maintenance view reads it directly via `selectedProductLatestTerminalAutoLoopReadinessAudit` / `selectedProductTerminalAutoLoopReadinessAuditSummary()`, and `multiAgentArchitectureAuditText()` ends with a one-line Chinese summary. The audit body contains no underlying parameters, `rawValue` / backend signatures / ANSI; the Boss Command Center and Delivery & Acceptance Center filter out this maintenance record; the rejection path consumes no loop turns, writes no Boss chat, no employee collaboration messages, and no job archives.
- The Boss Command Center, product-detail delivery area, Delivery & Acceptance Center, and the automated-acceptance drawer all read the same delivery-acceptance filter list; real terminal workspace, terminal log refresh, persistent-terminal audit, CLI-chain preflight, product isolation health check, runtime-session audit, anomaly recovery, history index/archive, and safety checkpoints stay as technical maintenance records in the CTO maintenance view, while real delivery evidence stays visible.
- Before judging, prompt recognition runs output through `CLIInteractionProfile.normalizedForPromptMatching(_:)`, which simulates a terminal by "line + cursor": strips ESC CSI (color, cursor control, and other sequences with no visible side effects) and OSC (terminal title / hyperlink) control sequences; recognizes `CSI K` / `ESC[0K` clearing cursor-to-end-of-line, `ESC[1K` replacing line-start-to-cursor with spaces, `ESC[2K` clearing the whole line; CR only resets the current line's cursor to column 0 **without erasing the tail** — subsequent visible characters overwrite position by position and uncovered tails stay visible; BS only moves the cursor left one position, and only the shell-standard erase `\b \b` overwrites with spaces; other C0 control bytes and DEL are dropped; Chinese, `\t`, and `\n` are preserved. Prompt lines wrapped in color or OSC titles are therefore recognized correctly; a bare `processing...\rcodex>` is rejected because the leftover `sing...` is still displayed; the prompt counts as ready only when an explicit line-clearing control such as `CSI K` / `ESC[2K` appears.
- The same normalization also feeds auth-anomaly / busy / transient-anomaly diagnostic-signal detection (`containsAuthenticationIssue` / `containsBusySignal` / `containsTransientIssue`): `error: not authenticated` wrapped in ANSI colors or OSC titles, or written after spinner-CR overwrites, `warning: rate limit`, `fatal: ... busy`, `error: 429`, and `error: network timeout` still hit diagnostics; but the `isDiagnosticLine` prefix list and the `lineContainsAnyDiagnosticSignal` word gate (tokens must match whole words and contain no `/\-_.` path/identifier marks) are unchanged, so a colored path `/var/log/timeout-429-busy.log`, a colored identifier `NetworkTimeout429BusyProbe`, and `timeout / network / 429 / busy` appearing inside OSC-wrapped Chinese prompt echoes are still not misjudged. This normalization is only for static prompt and diagnostic-signal recognition; it does not affect poll-phase incremental parsing, the `__OPC_JOB_EXIT_<id>__` exit protocol, or whole-word contextual matching of diagnostic signals.
- Chinese diagnostic phrase recognition: `diagnosticPrefixes` gains Chinese line-start prefixes ("Error:" / "Fatal:" / "Warning:" / "Anomaly:" / "Fatal error:" / "Unauthorized" / "Please log in", etc.); the codex / claude / gemini profiles each get their Chinese auth / busy / transient-anomaly phrases (e.g. "unauthorized" / "please log in again" / "auth failed" / "service busy" / "already busy" / "rate limited" / "please retry later" / "overloaded" / "request timeout" / "connection timeout" / "network anomaly" / "temporarily unavailable"). Chinese phrases hit via a two-stage "substring hit + neighboring characters must not be `/\-_.` path marks" check (`linePhraseHitAvoidingPathContext`): Chinese paths like `/var/log/transient-anomaly.log`, `/etc/codex/unauthorized.json`, `/opt/codex/service-busy-fixture.txt` are not misjudged, and ordinary Chinese user-prompt echoes (not starting with a diagnostic prefix) do not enter the diagnostic branch. Existing ASCII single/multi-word matching rules are unchanged, so English scenarios do not regress.
- Real-terminal auto-loop stop audit: when a loop ends under the real-terminal path with stopReason ∈ {auth anomaly / CLI still busy / transient anomaly / wait timeout}, a `VerificationRecord("Real Terminal Auto-Loop Stop Audit")` (status "Has Warnings") is written in sync, and a `[OPC Auto-Loop Stop Audit]` block is appended to the employee terminal log; the body uses the Chinese stopReason.title + operatorHint, never exposing `rawValue` / internal enums / backend signatures. The title is registered in `technicalMaintenanceVerificationTitles`, so the Boss Command Center, product-detail delivery area, and Delivery & Acceptance Center do not show it; the CTO maintenance view reads it via `selectedProductLatestTerminalAutoLoopStopAudit` and the maintenance audit center. The injection-closure path does not write stop audits, so unit tests / internal coordinators cannot pollute product-level records.
- The auto-input-loop safety gate, the closure-based executor core, the CTO internal coordinator, and the real-terminal seat entry are already in place: creating a loop requires explicit task context and a maximum turn count between 1 and 8; advancing a loop only accepts one line of OPC-generated next-step text. `CLIAutoInteractionLoopExecutor` reuses the gate's `rejectionReasonBeforeSending` check before calling the send closure: when the state is runnable, reaching the max turn count, a non-OPC-generated input source, or unsafe text (empty, contains newlines) returns a rejection directly and the closure is not called; when the state is already stopped, rejected, or completed, the closure is also not called. Only after passing the check is the single-line input handed to a real-terminal round or a test injection closure, whose return feeds `CLIInteractionObservation` plus a timeout flag to the gate's `advance` for accounting; observing an auth anomaly, busy, transient anomaly, or timeout stops immediately with a Chinese reason. `CompanyStore`'s internal coordinator only allows non-Boss employees in the current product team; missing CTO task context, selecting the Boss, or selecting an off-team employee is rejected directly in Chinese; the maintenance-area real entry has OPC generate the single-line next-step text from the task context and send it to the current employee's real terminal seat. Before sending on the real-terminal path, a read-only seat preflight runs: missing terminal workspace, missing employee seat, no dedicated ready prompt, or a non-long-lived-protocol employee is rejected directly in Chinese without consuming auto-loop turns; the ready path has been verified through fake REPL + tmux seat tests for real sends, completion-signal stops, and no Boss chat / no job archive side effects. Real-terminal auto-loop terminal logs use "OPC Auto Interaction Loop Turn"; manually triggered REPL turns keep using "OPC Manual Interaction Turn", so the CTO can audit the source. This entry creates no job archives, writes no Boss chat, and exposes no entry in the Boss Command Center.
- Resume failures are recorded in the current product's employee session archive; after consecutive failures on the same product reach the threshold, OPC clears the old session IDs and the next round starts from a new session, so expired or deleted sessions are not retried endlessly.
- OPC uses `__OPC_JOB_START_<id>__`, `__OPC_JOB_EXIT_<id>__`, and the exit code as lightweight protocol markers in real terminal seats, so every task has a traceable boundary.
- Before sending a new task to a seat, the most recent terminal snippets are read; if no exit marker follows the latest start marker, the seat still has unfinished work and the overwrite send is rejected.
- On rejection-overwrite, a Chinese failure summary is returned, suggesting refreshing the real terminal logs or recovering the abnormally occupied session first; this distinguishes normal busy tasks from abnormal occupancy.
- On timeout, a normal interrupt is sent to the seat first and OPC briefly waits for its exit marker; if still unclosed, a hard interrupt is sent and waited once more; if still unclosed, the unresponsive terminal seat is closed and the next run re-creates the seat through the real terminal workspace. The interruption facts are written to the job transcript, employee terminal log, verification records, and event stream.
- The current protocol already covers: "protocol profiles, status-observation result recording, persistent-terminal polling diagnostics, configurable session IDs, one task one boundary, long-output boundary protection, resume-failure cleanup, busy gating, timeout interruption escalation, transcript archiving, safe single-line input, per-profile manual interaction rounds for Codex / Claude Code / Gemini (with Chinese entries in the Terminal Hall / maintenance area), status-observation-driven Chinese recovery-advice panel, the controlled single-retry entry for transient anomalies, the auto-input-loop safety gate state machine, the injectable send-closure executor core for auto input loops, the CTO internal coordinator, and the CTO maintenance-area real-terminal controlled loop entry". Terminal Hall employee cards default to Chinese summaries of tool, model, reasoning effort, and execution mode only — never exposing full command arrays, `model_reasoning_effort`, `--skip-git-repo-check`, or other run parameters; detailed commands live only in operations details and `.opc/jobs/` job archives, and tests lock the default visible copy so it does not regress into mixed Chinese/English. Manual interaction rounds must first observe the tool's dedicated standalone-line ready prompt before sending, so input is never misfired into a plain terminal; after sending, only this round's new output is observed, and completion is judged by the profile's dedicated standalone-line ready prompt (Codex uses `codex>`, Claude Code uses `claude>`, Gemini uses `gemini>`) or the round-end signal; non-interactive backends, backends without a dedicated ready prompt, or seats that are not ready are rejected in Chinese, and wait timeouts only report status — they do not auto-interrupt terminal seats, create job archives, or start model tasks. The employee recovery-advice panel shows a Chinese summary and suggested actions from the latest status observation; auth anomalies and busy continue to block automatic reopening; only "transient anomaly" offers a clearly controlled "Manual Retry Once" button, triggered by an explicit CTO click, which performs exactly one session reopen and never enters an implicit loop. The real-terminal controlled loop entry appears only in the Terminal Hall / CTO maintenance area, is explicitly started by the CTO, and every round's input must be generated by OPC from the task context; the Boss Command Center does not show it.

Local history index and archive:

- The main snapshot remains the authoritative state; `company-history.sqlite3` is only a rebuildable query index.
- The local history index is generated via the maintenance audit or the explicit rebuild entry, covering messages, events, tasks, work items, approvals, artifacts, acceptance, memory, communication logs, and employee collaboration messages; normal saves do not do a synchronous full rebuild.
- The Terminal Hall maintenance area provides a "History Index Audit" for manual rebuild, indexing-content statistics, acceptance-record writes, and CTO reporting.
- The Terminal Hall maintenance area provides a "History Archive Migration" for copying old messages, old events, old communication logs, and old collaboration messages into archive tables; this round does not prune the main snapshot, delete local files, or start model tasks.
- Only when history scale, cross-product queries, or statistics/reporting needs exceed the main snapshot's capability is pruning archived old history from the main snapshot — or migrating more state to a formal database layer — considered.

Communication gateway:

- "Generate Phone Report" only generates and queues report content; "Send to Ready Channel" is what actually invokes the LOCAL or HTTP dispatcher.
- External channels only send when enabled, allowed to report, outbound-capable, and fully configured; error messages hide webhook paths, query parameters, and tokens.
- Inbound phone instructions must pass channel-enabled, instruction-permission, inbound-capability, and config-ready gates; external services should be verified with HMAC, timestamp, and nonce first.
- The external signed entry must additionally use a structured JSON action allowlist; currently only `query_status` and `submit_instruction` are accepted; the external approval action is reserved but rejected by default.
- Inbound instructions only create traceable tasks and communication logs; they never execute local commands directly and never skip Boss/CTO Approval Gates.

## Safety rules

- Scraping browser subscription sessions is forbidden.
- Destructive commands require Boss approval.
- Employees changing code must have an explicit file scope.
- Parallel implementation uses isolated source execution areas.
- The CTO receives summaries of all direct employee conversations.
