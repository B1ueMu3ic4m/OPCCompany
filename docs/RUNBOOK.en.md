<!-- Translated from RUNBOOK.md; the Chinese original remains authoritative for internal history. -->

# OPC Company Runbook

Last updated: 2026-05-07

Current baseline: OPC Company is ready for single-user local formal use on this Mac. Latest verified bundle is `dist/OPCCompany.app` with bundle version `20260507033423`; full test baseline is `swift test --no-parallel` 555/555.

## Build

```bash
cd ~/Desktop/OPCCompany
swift build
```

## Run

```bash
cd ~/Desktop/OPCCompany
swift run OPCCompany
```

This launches the native macOS SwiftUI application from Swift Package Manager.

## Build Local App Bundle

```bash
cd ~/Desktop/OPCCompany
scripts/build_app_bundle.sh
open dist/OPCCompany.app
```

This creates a local ad-hoc signed app bundle suitable for personal use on this Mac. Developer ID signing, notarization, DMG packaging, and an updater are only needed if the app is later distributed to other Macs or other users.

Verify the current local bundle:

```bash
codesign --verify --deep --strict dist/OPCCompany.app
plutil -p dist/OPCCompany.app/Contents/Info.plist | rg "CFBundleVersion|CFBundleShortVersionString"
```

## Safe Project Cleanup

Safe cleanup before formal local use:

```bash
cd ~/Desktop/OPCCompany
rm -rf .build
```

Keep these unless the user explicitly requests a deeper reset:

- `Tests/OPCCompanyTests/**`: regression suite, not disposable test data.
- `dist/OPCCompany.app`: latest usable local app bundle.
- `docs/**`: product documentation; local-only internal files (`OPC_COMPANY.md`, `CLAUDE.md`, `AGENTS.md`) stay outside the public repo.
- `.claude/`: project-level goal/settings state.
- `.ccb/`: collaboration logs and handoff trace; can be large, but keep while audit traceability matters.
- `~/Library/Application Support/OPCCompany/**`: real local product state, history index, checkpoints, and employee workspaces.

## Single-User Local Formal-Use Boundary

This project's current formal-use target is "long-term single-user local use on the same Mac", not Mac App Store release or external distribution.

- **Not blockers for formal use**: Communication Gateway mobile linkage, public/LAN inbound services, Developer ID signing, notarization, DMG distribution packages, Sparkle auto-updates, and external crash-reporting services.
- **Keep for formal use**: the local ad-hoc signed app bundle build script, full `swift test --no-parallel`, MacBook built-in-display Computer Use verification, and recoverable local state backups/checkpoints.
- **Must be stable before formal use**: the default visible UI exposes no backend paths / command arguments / raw model transcripts; the Codex / Claude Code / Gemini subscription CLI chains run and fail with clear messages; main state is never polluted by tests; CLI job archives and maintenance audits can be used to trace problems.
- **Re-evaluate later against real usage**: if multi-Mac sync, use by others, or remote control is needed, re-evaluate Developer ID signing, notarization, auto-update, external crash reporting, Communication Gateway mobile linkage, and external inbound services.

## Local Diagnostics and Logging Policy

Sentry, Crashlytics, or other external crash/log reporting are not integrated. Troubleshooting materials stay on this machine only:

- Main state snapshot: `~/Library/Application Support/OPCCompany/company-state.json`
- History index: `~/Library/Application Support/OPCCompany/company-history.sqlite3`
- Safety checkpoints: `~/Library/Application Support/OPCCompany/checkpoints/`
- CLI job archives: `.opc/jobs/` under the current product root
- macOS crash reports: `~/Library/Logs/DiagnosticReports/OPCCompany_*.crash`

The "Local Diagnostics and Logging Policy" in the CTO maintenance area displays these locations. The Boss default UI does not show diagnostic paths or logging implementation details.

**Command-line job tail-output capture contract**: `AgentProcessRunner.runStreaming` must, after `process.waitUntilExit()` returns, first set the stdout / stderr `readabilityHandler` to `nil`, then use `readDataToEndOfFile()` to synchronously drain the residual tail data into `ProcessOutputBuffer`. In scenarios where the child process prints and exits immediately, `readabilityHandler` may not have dispatched the final data chunk; without this manual drain, the job archive ends up with investigation nightmares like "the child process exited but the last few lines of output are missing" or "the final receipt before [command exit code] is missing". The guard test `runStreamingCapturesTailOutputAfterExit` prevents this regression.

## CCB Agent Health Checks

When `ccb ps` shows an agent as `healthy`, `restored`, or `busy`, do not assume the agent is actually working. First inspect the real terminal pane.

For the current OPC project:

```bash
cd ~/Desktop/OPCCompany
ccb ps
tmux -S .ccb/ccbd/tmux.sock capture-pane -p -t %4 -S -120
```

Common cases:

- `busy` + normal model output: the agent is executing.
- `busy` + `Not logged in · Run /login`: the queue is blocked by Claude Code authentication, not by code execution.
- `healthy/restored` + empty prompt: the runtime exists but may be idle.
- `queued` jobs behind a stuck job: inspect the first job with `ccb pend <job_id> 1`.

Resolution order:

1. Confirm the agent workspace path belongs to this project.
2. Capture the provider terminal pane.
3. Fix login/auth or waiting prompt before sending more work.
4. Only after the provider is actually ready, send the engineering task.

## Product Status

Implemented:

- Native SwiftUI app shell.
- SpriteKit 2D office floor.
- Boss office, CTO office, employee hall.
- Boss, CTO, Gemini UI Designer, Claude Code Engineer, and Codex Reviewer roles.
- Desks, chairs implied by desk modules, computers, nameplates, status indicators.
- Clickable characters.
- Dedicated boss command center panel with company status, CTO quick commands, running employee overview, recent tasks, and recent events.
- Dialogue panel for each agent.
- Direct employee conversations summarized to CTO.
- Task board.
- Event log.
- Agent profile panel.
- Add employee sheet with role, backend, appearance, and permission settings.
- CLI command preview for Codex, Claude, Gemini, API, and custom backends.
- Terminal panel with a real process runner entry for selected CLI-backed employees.
- Terminal hall workspace with per-employee terminal cards, streaming stdout/stderr, per-agent run state, log clearing, selection, and run-all execution.
- Local JSON persistence in `~/Library/Application Support/OPCCompany/company-state.json`.
- Product spec, role rules, GitHub research, and orchestration design docs.
- Multi-product workspace design for running several products under one OPC company.

Next product-hardening work:

- Tune technical maintenance thresholds after real local usage: main snapshot size, `.opc/jobs/` archive count/size, and history archive volume.
- Continue SQLite history archive migration only when local state size or query latency crosses the documented maintenance threshold; JSON snapshot remains the authority.
- Add git worktree manager.
- Replace vector placeholder characters with Rive/Spine asset packs.
- If the app is later used on other Macs or by other people, re-evaluate Developer ID signing, notarization, DMG packaging, Sparkle updates, and hosted crash reporting.

## Persistence Failure Visibility

`CompanyPersistence.save(_:)` returns `Result<Void, Error>`:

- `.success(())`: the snapshot has been written to `~/Library/Application Support/OPCCompany/company-state.json`.
- `.failure(error)`: any of createDirectory / encode / write failed. `CompanyStore.saveSnapshot()` inserts a `.risk` "Persistence Failure" event at the head of `events`, visible in the Boss-side event stream; consecutive identical failures are deduplicated adjacently so the event stream is not flooded by disk-full / unwritable-sandbox scenarios.

Notes:

- Failure events are **memory-only** (saved to the events array) and **never persisted** — because the persistence channel just failed, saving again would also fail. The notice disappears after restart, but if the root cause (e.g. disk full) persists, the next write triggers it again.
- `recordPersistenceFailure` never calls `saveSnapshot()`, avoiding recursion. If operations sees repeated "Persistence Failure" events on the Boss side, check the writability / free disk space of `~/Library/Application Support/OPCCompany/`.
- Test stubs inject an explicit URL through the internal `CompanyPersistence.save(_:to:)` overload to verify the persistence layer's `.failure`; then inject a failure result through the `CompanyStore.persistSnapshot` test closure to verify `saveSnapshot()` appends an in-memory "Persistence Failure" risk event with adjacent dedup.

## Keychain Write Failure Visibility

`OPCKeychainStore.saveAPIKey(_:agentID:)` returns `OSStatus`:

- `errSecSuccess`: the API Key was written to the macOS Keychain (via a `SecItemUpdate` hit or a new `SecItemAdd`).
- `errSecParam`: the passed value is empty or cannot be UTF-8 encoded — treated as "nothing to write"; callers may ignore as appropriate.
- Other `OSStatus` values (e.g. `errSecAuthFailed`, `errSecInteractionNotAllowed`, `errSecMissingEntitlement`): real returns from the underlying SecItem API; callers must convert them into visible notices.

`CompanyStore` consumes the return value on two paths and, on non-success, uses `recordKeychainSaveFailure` to insert a `.risk` "API Key Write to Keychain Failed" event at the head of `events`, visible in the Boss-side event stream; adjacent failures with the same employee and same OSStatus are deduplicated so a persistently locked Keychain does not flood the stream:

- `hydrateAPIKeysFromKeychain`: after startup / snapshot restore, writes the in-memory apiKey back to the Keychain.
- `agentsForSnapshot`: before every `saveSnapshot()`, archives the in-memory apiKey to the Keychain, then clears the snapshot copy to keep the existing constraint that "the snapshot never carries plaintext apiKeys".

Notes:

- Failure events are **memory-only** (saved to the events array) and **never persisted** — because when a Keychain write fails, saveSnapshot can often still succeed, but the event itself does not trigger another saveSnapshot (avoiding recursion + re-running the pre-snapshot Keychain write in a failed state). The notice disappears after restart, but if the root cause (Keychain locked / missing sandbox permission) persists, the next write triggers it again.
- Even when the Keychain write fails, `agentsForSnapshot` still clears the apiKey in the snapshot copy (the persistence layer is unchanged). The apiKey in the in-memory `agents[]` main array is kept, so API employees remain callable this session, but **after an app restart that employee's API Key is lost**. The event detail explicitly tells the Boss that "the key must be re-entered and the Keychain checked for lock or permission restrictions".
- Test stubs inject explicit OSStatus values through the `CompanyStore.keychainSaveAPIKey` closure, verifying failure-event appending / adjacent dedup / no event-stream pollution on the success path, without ever touching the real Keychain.

## Test Run Boundaries (Persistence Isolation)

`swift test` must use an isolated persistence directory and never pollute real app state. `CompanyPersistence.supportDirectory` automatically redirects to `<TemporaryDirectory>/OPCCompanyTests-<pid>` under test processes, and everything — `company-state.json` / `company-history.sqlite3` / `agents/` / safety checkpoints — follows along.

Effective in priority order:

1. Environment variable `OPC_COMPANY_SUPPORT_DIR=/your/sandbox/path` (explicit override for CI / debugging).
2. Detected XCTest / swift-testing / SwiftPM `swift test` process → `<TemporaryDirectory>/OPCCompanyTests-<pid>`.
3. Real app run → `~/Library/Application Support/OPCCompany`.

If an earlier `swift test` polluted the real `~/Library/Application Support/OPCCompany` before the upgrade, clean it up manually after user confirmation:

```bash
# Back up first, then clean (the user decides the timing; this repo's code never proactively deletes real state)
mv ~/Library/Application\ Support/OPCCompany ~/Desktop/OPCCompany-backup-$(date +%Y%m%d)
```

## Computer Use Verification Path

OPC UI verification (Computer Use or manual) must run on the **MacBook built-in display**; external monitors are **not a target screen**, because SwiftUI's accessibility tree and SF Symbol rendering density shift with external-display DPI and automation targeting drifts intermittently.

### Terminal Hall Maintenance Area Key Controls

The Terminal Hall maintenance area (`LocalMaintenanceCenter`, referenced by both `TerminalHallView` and `OperationsSuiteView`) has stable accessibility identifiers for Computer Use, locatable directly through the a11y tree. All identifiers are declared centrally in the `OPCUIAutomationIdentifier` enum in `Sources/OPCCompanyCore/DisplayFormatting.swift` — the single authoritative source for RUNBOOK; the `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` test locks in that every entry below is registered in the enum and every enum case maps to this document:

- `OPCTerminalAutoInteractionLoopPanel` (`.terminalAutoInteractionLoopPanel`): the title anchor of the real-terminal auto interaction loop panel; the parent container carries no identifier, so it cannot hijack the actionable nodes of the inputs and buttons below.
  - `OPCTerminalAutoLoopTaskContextField` (`.terminalAutoLoopTaskContextField`): the task-context input field (accessibilityLabel: CTO Task Context).
  - `OPCTerminalAutoLoopMaxTurnsStepper` (`.terminalAutoLoopMaxTurnsStepper`): the max-turns stepper (accessibilityValue is the current turn count).
  - `OPCTerminalAutoLoopStartButton` (`.terminalAutoLoopStartButton`): the start-controlled-loop button (accessibilityLabel switches to "Loop Running" while executing).
  - `OPCTerminalAutoLoopReportSummary` (`.terminalAutoLoopReportSummary`): the Chinese summary text block after rejection or completion (accessibilityLabel toggles between rejected/report states; accessibilityValue is this round's `report.summaryText`, used to read the stop reason and round result directly).
- `OPCTerminalHallHeaderPromptField` (`.terminalHallHeaderPromptField`): the "Prompt to send to employee terminals" input at the top of the Terminal Hall (accessibilityLabel: Prompt to Send to Employee Terminals; accessibilityHint explains it will be sent to the current product's executable employees by the "Run All" button).
- `OPCTerminalHallRunAllButton` (`.terminalHallRunAllButton`): the "Run All" button at the top of the Terminal Hall (accessibilityLabel: Run All Employee Terminals; accessibilityHint explains it sends the current prompt to all executable, not-yet-running employees of the current product, and is disabled when there are no executable employees or all are running).
- `OPCTerminalManualREPLInputField` (`.terminalManualREPLInputField`): the single-line input of "Manual Interaction Rounds" in local maintenance details (accessibilityLabel: Manual Interaction Single-Line Input; accessibilityHint explains it is sent to the currently selected employee's real terminal seat and cannot contain newlines).
- `OPCTerminalManualREPLSendButton` (`.terminalManualREPLSendButton`): the "Send one line of manual input" button in local maintenance details (accessibilityLabel toggles between idle/sending; accessibilityHint explains it sends the input field's single line to the currently selected employee's real terminal seat, disabled when input is empty or sending).
- `OPCMaintenanceAuditCenter` (`.maintenanceAuditCenter`): root node of the technical maintenance audit center block (accessibilityLabel: Technical Maintenance Audit Center).
  - `OPCMaintenanceAuditRow` (`.maintenanceAuditRow`): each maintenance record card (accessibilityLabel is "Title · Status").
- `OPCMaintenanceArtifactCenter` (`.maintenanceArtifactCenter`): root node of the maintenance artifact archive center block (accessibilityLabel: Maintenance Artifact Archive).
  - `OPCMaintenanceArtifactRow` (`.maintenanceArtifactRow`): each maintenance artifact card.
- `OPCCLIRecoveryAdvicePanel` (`.cliRecoveryAdvicePanel`): root node of the employee recovery advice panel (accessibilityLabel: Employee Recovery Advice Panel); the root uses `.accessibilityElement(children: .contain)` and mirrors the summary and each employee's manual-retry button through `accessibilityChildren`, so SwiftUI text merging can neither drop the summary ID nor override button reachability.
  - `OPCCLIRecoveryAdviceSummary` (`.cliRecoveryAdviceSummary`): the employee recovery advice summary text (accessibilityLabel: Employee Recovery Advice Summary; accessibilityValue is the current `cliRecoveryAdviceSummaryText()` body).
  - `OPCCLIRecoveryAdviceManualRetryButton` (`.cliRecoveryAdviceManualRetryButton`): each employee's "Manual Retry Once" button (accessibilityLabel is "Employee Name · Manual Retry Once"; accessibilityHint explains it is only available for transient anomalies — auth anomalies, busy, or not-yet-observed states never auto-reopen; the disabled state stays on the button itself).
- `OPCTerminalWorkspaceHealthPreview` (`.terminalWorkspaceHealthPreview`): the in-place preview card under the persistent terminal availability audit button (accessibilityLabel: Persistent Terminal Availability Preview; accessibilityValue is the current `terminalWorkspaceHealthAuditText()` body); the root collapses to a single locatable node with `.accessibilityElement(children: .combine)`.
- `OPCRunDataCleanupPreview` (`.runDataCleanupPreview`): the cleanup preview text block (accessibilityLabel: Cleanup Preview; accessibilityValue is the current `selectedProductRunDataSummary()` body).
- `OPCCLIToolchainPreflightPreview` (`.cliToolchainPreflightPreview`): the CLI-chain preflight text block (accessibilityLabel: CLI Chain Preflight; accessibilityValue is the current `cliToolchainPreflightText()` body).
- `OPCDefaultCompanyStatePreview` (`.defaultCompanyStatePreview`): the default-state preview text block (accessibilityLabel: Default State Preview; accessibilityValue is the current `defaultCompanyStatePreviewText()` body).
- `OPCProductIsolationAuditPreview` (`.productIsolationAuditPreview`): the isolation health check preview text block (accessibilityLabel: Isolation Health Check Preview; accessibilityValue is the current `productIsolationAuditText()` body).
- `OPCCLIRuntimeIsolationPreview` (`.cliRuntimeIsolationPreview`): the CLI and workspace isolation preview summary text block (accessibilityLabel: CLI and Workspace Isolation Preview; accessibilityValue is the current `cliRuntimeIsolationAuditText()` body).
  - `OPCCLIRuntimeIsolationDetailToggle` (`.cliRuntimeIsolationDetailToggle`): the full-detail toggle of the CLI and workspace isolation preview (accessibilityLabel: CLI and Workspace Isolation Preview Full Detail Toggle); expands/collapses the full operations detail of the same card.
  - `OPCCLIRuntimeIsolationDetailPreview` (`.cliRuntimeIsolationDetailPreview`): the full-detail text block after expanding the CLI and workspace isolation preview (accessibilityLabel: CLI and Workspace Isolation Preview Full Detail; accessibilityValue is the current `cliRuntimeIsolationAuditDetailText()` body).
- `OPCTerminalWorkspacePlanPreview` (`.terminalWorkspacePlanPreview`): the real terminal workspace preview summary text block (accessibilityLabel: Real Terminal Workspace Preview; accessibilityValue is the current `terminalWorkspacePlanText()` body).
  - `OPCTerminalWorkspacePlanDetailToggle` (`.terminalWorkspacePlanDetailToggle`): the full-detail toggle of the real terminal workspace preview (accessibilityLabel: Real Terminal Workspace Preview Full Detail Toggle); expands/collapses the full operations detail of the same card.
  - `OPCTerminalWorkspacePlanDetailPreview` (`.terminalWorkspacePlanDetailPreview`): the full-detail text block after expanding the real terminal workspace preview (accessibilityLabel: Real Terminal Workspace Preview Full Detail; accessibilityValue is the current `terminalWorkspacePlanDetailText()` body).
- `OPCSafetyCheckpointPreview` (`.safetyCheckpointPreview`): the safety checkpoint text block (accessibilityLabel: Safety Checkpoint; accessibilityValue is the current `safetyCheckpointListText()` body).
- `OPCLocalDiagnosticsPolicyPreview` (`.localDiagnosticsPolicyPreview`): the local diagnostics and logging policy text block (accessibilityLabel: Local Diagnostics and Logging Policy; accessibilityValue is the current `localDiagnosticsPolicyText()` body).
- `OPCEmployeeHandoffAuditPreview` (`.employeeHandoffAuditPreview`): the in-place preview card under the employee handover audit button (accessibilityLabel: Employee Handover Audit Preview; accessibilityValue is the current `employeeHandoffAuditText()` body).
- `OPCJobArchiveStaleAuditPreview` (`.jobArchiveStaleAuditPreview`): the in-place preview card under the CLI job ghost audit button (accessibilityLabel: CLI Job Ghost Audit Preview; accessibilityValue is the current `jobArchiveStaleAuditText()` body).
- `OPCEvidenceClassificationAuditButton` (`.evidenceClassificationAuditButton`): the run-evidence classification audit button.
  - `OPCEvidenceClassificationAuditPreview` (`.evidenceClassificationAuditPreview`): the run-evidence classification audit preview card (accessibilityLabel: Run Evidence Classification Audit Preview); like `OPCRuntimeSessionHealthAuditPreview`, the root collapses multiple Text views into **a single locatable a11y root node** with `.accessibilityElement(children: .combine)`, so exactly one same-named node appears in the AX tree for Computer Use to target.
- `OPCMaintenanceDataPressureAuditButton` (`.maintenanceDataPressureAuditButton`): the maintenance data growth audit button.
  - `OPCMaintenanceDataPressurePreview` (`.maintenanceDataPressurePreview`): the maintenance data growth preview card (accessibilityLabel: Maintenance Data Growth Preview); like `OPCRuntimeSessionHealthAuditPreview`, the root collapses multiple Text views into **a single locatable a11y root node** with `.accessibilityElement(children: .combine)`, so exactly one same-named node appears in the AX tree for Computer Use to target.
- `OPCHistoryIndexAuditPreview` (`.historyIndexAuditPreview`): the in-place preview card under the history index audit button (accessibilityLabel: History Index Preview; accessibilityValue is the current `historyIndexAuditText()` body).
- `OPCHistoryArchiveMigrationPreview` (`.historyArchiveMigrationPreview`): the in-place preview card under the history archive migration button (accessibilityLabel: History Archive Migration Preview; accessibilityValue is the current `historyArchiveMigrationText()` body).
- `OPCAutoCapturedSummaryDuplicatePreview` (`.autoCapturedSummaryDuplicatePreview`): the auto-captured summary dedup preview text block (accessibilityLabel: Auto Summary Dedup Preview; accessibilityValue is the current `autoCapturedSummaryDuplicatePreviewText()` body).
- `OPCLegacyTaskProductMigrationButton` (`.legacyTaskProductMigrationButton`): the legacy task ownership migration button.
  - The button hint states clearly: it is only enabled when the current product has unowned legacy tasks; the first click enters a confirm state, and only a second click migrates them into the current product.
  - `OPCLegacyTaskProductMigrationPreview` (`.legacyTaskProductMigrationPreview`): the legacy task ownership migration preview text block (accessibilityLabel: Legacy Task Ownership Migration Preview; accessibilityValue is the current `legacyTaskProductMigrationText()` body).
- `OPCRuntimeSessionHealthAuditPreview` (`.runtimeSessionHealthAuditPreview`): the in-place preview card under the runtime session health audit button (accessibilityLabel: Runtime Session Health Audit Preview); after the button fires, the card refreshes its "most recent audit" section in place, showing a Chinese empty state plus the live `runtimeSessionHealthAuditText()` fallback when it has never run.
- `OPCLinkedLocalFileRootAllowlistPreview` (`.linkedLocalFileRootAllowlistPreview`): the local file index root allowlist preview text block (accessibilityLabel: Local File Index Root Allowlist; accessibilityValue is the current `linkedLocalFileRootAllowlistText()` body).

The core action buttons inside the `LocalMaintenanceCenter` detail panel have stable Computer Use anchors in `Sources/OPCCompanyCore/OperationsSuiteView.swift`; all accessibilityLabels/Hints are short Chinese phrases, and accessibilityIdentifiers are centrally registered in `OPCUIAutomationIdentifier`. **Do not** hunt for these buttons via OCR screenshots — locate them directly on the a11y tree by anchor:

- `OPCCLIRuntimeIsolationAuditButton` (`.cliRuntimeIsolationAuditButton`): the "Run CLI and Workspace Isolation Health Check" button (accessibilityLabel: Run CLI and Workspace Isolation Health Check; accessibilityHint: runs the CLI and workspace isolation health check for the current product, writes the maintenance audit, and refreshes the preview, without modifying run data or employees).
- `OPCTerminalWorkspaceStartButton` (`.terminalWorkspaceStartButton`): the "Start Real Terminal Workspace" button (accessibilityLabel: Start Real Terminal Workspace; accessibilityHint: starts the real terminal workspace for the current product and routes employee tasks to real macOS terminal seats).
- `OPCTerminalWorkspaceRefreshLogsButton` (`.terminalWorkspaceRefreshLogsButton`): the "Refresh Real Terminal Logs" button (accessibilityLabel: Refresh Real Terminal Logs; accessibilityHint: refreshes the visible logs of the current product's real terminal workspace without affecting real task execution).
- `OPCTerminalWorkspaceHealthAuditButton` (`.terminalWorkspaceHealthAuditButton`): the "Run Persistent Terminal Availability Audit" button (accessibilityLabel: Run Persistent Terminal Availability Audit; accessibilityHint: audits the current product's persistent terminal workspace availability, writes the maintenance audit, and refreshes the availability preview card in place).
- `OPCRuntimeSessionHealthAuditButton` (`.runtimeSessionHealthAuditButton`): the "Run Session Health Audit" button (accessibilityLabel: Run Session Health Audit; accessibilityHint: audits the current product's employee session health, writes the maintenance audit, and refreshes the session health preview card in place).
- `OPCEmployeeHandoffAuditButton` (`.employeeHandoffAuditButton`): the "Run Employee Handover Audit" button (accessibilityLabel: Run Employee Handover Audit; accessibilityHint: audits the current product's employee handover evidence completeness, writes the maintenance audit, and refreshes the employee handover audit preview).
- `OPCJobArchiveStaleAuditButton` (`.jobArchiveStaleAuditButton`): the "Run CLI Job Ghost Audit" button (accessibilityLabel: Run CLI Job Ghost Audit; accessibilityHint: audits the current product's CLI job archives for ghost or stale jobs, writing only the maintenance audit and never deleting job artifacts).
- `OPCHistoryIndexAuditButton` (`.historyIndexAuditButton`): the "Run History Index Audit" button (accessibilityLabel: Run History Index Audit; accessibilityHint: audits the current product's history index completeness and consistency, writes the maintenance audit, and refreshes the history index preview).
- `OPCHistoryArchiveMigrationButton` (`.historyArchiveMigrationButton`): the "Run History Archive Migration" button (accessibilityLabel: Run History Archive Migration; accessibilityHint: migrates the current product's old history records into the history archive per archive rules, writes the maintenance audit, and refreshes the archive migration preview).
- `OPCStaleRuntimeSessionRecoveryButton` (`.staleRuntimeSessionRecoveryButton`): the "Recover Abnormally Occupied Employee Session" button (accessibilityLabel: Recover Abnormally Occupied Employee Session; accessibilityHint: recovers the current product's abnormally occupied employee runtime sessions, releasing seats without modifying employee configuration or project files).
- `OPCRunDataCleanupConfirmButton` (`.runDataCleanupConfirmButton`): the "Clean Current Product Run/Test Data" execute button; it sits in the resident confirmation area and only enables after typing "confirm" in the same area's input field; accessibilityLabel is fixed to "Clean Current Product Run/Test Data" and the accessibilityHint notes it does not delete employees or project files.
- `OPCDefaultCompanyStateConfirmButton` (`.defaultCompanyStateConfirmButton`): the "Restore Default Company State" execute button; it sits in the resident confirmation area and only enables after typing "confirm" in the same area's input field; accessibilityLabel is fixed to "Restore Default Company State".
- `OPCSafetyCheckpointRollbackConfirmButton` (`.safetyCheckpointRollbackConfirmButton`): the "Roll Back to Most Recent Safety Checkpoint" execute button; it sits in the resident confirmation area and only enables after typing "confirm" in the same area's input field; accessibilityLabel is fixed to "Roll Back to Most Recent Safety Checkpoint".
  - These three dangerous confirmation areas are resident at the top of the local maintenance details, no longer relying on "expand on click" or system alerts, so temporary confirmation UI inside sheets/scroll views cannot become invisible to accessibility clicks.
  - Computer Use verification should only confirm that the three execute buttons start disabled, the confirmation-phrase input is locatable, and clicking "Cancel" clears the phrase; do not click an enabled execute button unless a dangerous maintenance action is actually needed.
- `OPCLocalMaintenanceDangerousConfirmationPanel` (`.localMaintenanceDangerousConfirmationPanel`): ID prefix for the local-maintenance dangerous-action confirmation panels; actual nodes append `-cleanup`, `-reset`, or `-rollback` per action and show the matching dangerous-action title and impact description.
- `OPCLocalMaintenanceDangerousConfirmationPhraseField` (`.localMaintenanceDangerousConfirmationPhraseField`): ID prefix for the dangerous-action confirmation-phrase input; actual nodes append `-cleanup`, `-reset`, or `-rollback` per action, and the matching execute button only enables after typing "confirm".
- `OPCLocalMaintenanceDangerousConfirmationCancelButton` (`.localMaintenanceDangerousConfirmationCancelButton`): ID prefix for the "Cancel" button in the dangerous-action confirmation area; actual nodes append `-cleanup`, `-reset`, or `-rollback` per action; clicking only clears the confirmation phrase and never executes the maintenance action.
- `OPCLocalMaintenanceDangerousConfirmationExecuteButton` (`.localMaintenanceDangerousConfirmationExecuteButton`): kept as the category anchor for dangerous-action execute buttons; the current actual execute buttons use their business IDs (`OPCRunDataCleanupConfirmButton`, `OPCDefaultCompanyStateConfirmButton`, `OPCSafetyCheckpointRollbackConfirmButton`) so Computer Use can locate a specific action directly.

- `OPCTerminalHallDetailSheet` (`.terminalHallDetailSheet`): the root node of the Terminal Hall secondary detail sheet, confirming entry from the summary page into the detail panel.
- `OPCLocalMaintenanceCenterRoot` (`.localMaintenanceCenterRoot`): root node of the local stability maintenance center.
- `OPCTerminalHallOverviewSummary` (`.terminalHallOverviewSummary`): the default-visible runtime status overview card at the top of the Terminal Hall.
- `OPCTerminalHallLocalMaintenanceHeaderTrigger` (`.terminalHallLocalMaintenanceHeaderTrigger`): the direct "Local Maintenance" entry at the top of the Terminal Hall; clicking opens the local stability and CLI operations detail panel.
- The Terminal Hall's default-visible **single-employee terminal card** `TerminalAgentCard` has stable anchors for its 5 core action buttons, all through the `TerminalAgentCard` implementation in `Sources/OPCCompanyCore/TerminalHallView.swift`; each same-named button appears once per employee card, and the accessibilityLabel must carry the employee display name so Computer Use can tell target employees apart:
  - `OPCTerminalAgentCardRefreshPreflightButton` (`.terminalAgentCardRefreshPreflightButton`): the `arrow.clockwise` icon-only refresh button right of the "Preflight" title at the top of the employee card (accessibilityLabel: Refresh `{Employee Name}` Preflight; accessibilityHint explains it regenerates the preflight text from the current prompt and employee configuration).
  - `OPCTerminalAgentCardSelectButton` (`.terminalAgentCardSelectButton`): the `person.crop.circle` "Select Employee" button at the bottom of the employee card (accessibilityLabel: Select `{Employee Name}`; accessibilityHint explains it highlights the card and switches the right-side inspector to that employee).
  - `OPCTerminalAgentCardPreflightButton` (`.terminalAgentCardPreflightButton`): the "Preflight" button at the bottom of the employee card, triggering `recordCLIPreflight(agentID:prompt:)` to write a CLI preflight audit (accessibilityLabel: Write `{Employee Name}` CLI Preflight Audit; accessibilityHint notes it is disabled for the Boss role).
  - `OPCTerminalAgentCardRunButton` (`.terminalAgentCardRunButton`): the primary "Run / Running" button at the bottom of the employee card, calling `runAgent(agentID:prompt:)` (accessibilityLabel toggles between "Run `{Employee Name}` Terminal" / "`{Employee Name}` Running"; accessibilityHint explains it sends the current prompt to the employee's real terminal seat and is disabled while the employee runs or for the Boss role).
  - `OPCTerminalAgentCardClearLogButton` (`.terminalAgentCardClearLogButton`): the `trash` icon-only "Clear Log" button at the bottom of the employee card (accessibilityLabel: Clear `{Employee Name}` Terminal Log; accessibilityHint explains it only clears the visible output log without affecting running tasks or the employee's persistent session; disabled while the card shows "No terminal output yet.").
- `OPCAdvancedMaintenanceArchitectureSummaryCard` (`.advancedMaintenanceArchitectureSummaryCard`): the Terminal Hall's default-visible "Multi-Employee Architecture Health Check & Closure" **summary workbench card**, showing completion / closed · to-be-strengthened · unclosed · check items / latest closure summary plus primary action buttons.
  - `OPCAdvancedMaintenanceArchitectureAuditButton` (`.advancedMaintenanceArchitectureAuditButton`): the summary card's primary "Run Health Check" action (accessibilityLabel: Run Multi-Employee Architecture Health Check; accessibilityHint explains it runs the health check for the current product, writes the maintenance audit, and switches the selected employee to the CTO).
  - `OPCAdvancedMaintenanceArchitectureClosureDrillButton` (`.advancedMaintenanceArchitectureClosureDrillButton`): the summary card's primary "Closure Drill" action (accessibilityLabel: Run Multi-Employee Architecture Closure Drill; accessibilityHint explains it generates a closure trace and switches the selected employee to the CTO).
- `OPCAdvancedMaintenanceGatewaySummaryCard` (`.advancedMaintenanceGatewaySummaryCard`): the Terminal Hall's default-visible "Communication Gateway & Phone Commands" **summary workbench card**, showing channel total · enabled · inbound-capable · communication logs plus recent communication summary and primary action buttons.
- `OPCAdvancedMaintenanceLocalSummaryCard` (`.advancedMaintenanceLocalSummaryCard`): the Terminal Hall's default-visible "Local Stability & CLI Operations" **summary workbench card**, showing maintenance audit/artifact counts and threshold pressure plus recent maintenance summary and primary action buttons.
  - `OPCAdvancedMaintenanceLocalIsolationAuditButton` (`.advancedMaintenanceLocalIsolationAuditButton`): the summary card's primary "Run Isolation Health Check" action (accessibilityLabel: Run Local Isolation Health Check; accessibilityHint explains it runs the multi-product isolation health check for the current product, writes the maintenance audit, and refreshes the summary).
  - `OPCAdvancedMaintenanceLocalCLIPreflightButton` (`.advancedMaintenanceLocalCLIPreflightButton`): the summary card's primary "CLI Preflight" action (accessibilityLabel: Run CLI Chain Preflight; accessibilityHint explains this is a dry-run preflight that does not call real model tasks).
- `OPCAdvancedMaintenanceArchitectureDetailTrigger` (`.advancedMaintenanceArchitectureDetailTrigger`): the "View Details" button at the bottom right of the summary card; clicking opens the secondary sheet rendering the full `MultiAgentArchitectureAuditCenter` (including closure drill summary, rework summary, closure detail sheet, and check-item list).
- `OPCAdvancedMaintenanceGatewayDetailTrigger` (`.advancedMaintenanceGatewayDetailTrigger`): the "View Details" button at the bottom right of the summary card; clicking opens the secondary sheet rendering the full `CommunicationGatewayCommandCenter` (including channel configuration, phone-command simulation, full communication logs, and security primitives).
- `OPCAdvancedMaintenanceLocalDetailTrigger` (`.advancedMaintenanceLocalDetailTrigger`): the "View Details" button at the bottom right of the summary card; clicking opens the secondary sheet rendering the full `LocalMaintenanceCenter`, with deep controls such as the **maintenance audit center / maintenance artifact archive / run-evidence classification audit / maintenance data growth audit / real-terminal auto-loop panel** all embedded inside this secondary panel.

**Important**: the Terminal Hall is a summarized workbench by default. Besides the "Terminal Hall Runtime Status Overview" and employee terminal cards, the default page also shows **three default-visible summary workbench cards** (architecture / communication / local stability). **DisclosureGroup collapse-hiding is no longer used** — the path for Computer Use / manual verification of deep maintenance anchors (`OPCMaintenanceAuditCenter` / `OPCMaintenanceArtifactCenter` / `OPCEvidenceClassificationAudit*` / `OPCMaintenanceDataPressure*` / `OPCTerminalAutoInteractionLoopPanel` / `OPCTerminalAutoLoop*`) is: first click the matching "View Details" button (usually `OPCAdvancedMaintenanceLocalDetailTrigger`) to open the secondary sheet, then drill down to the specific control inside. The summary cards themselves show status/metrics/recent summary/primary actions, so routine audits can be triggered without opening the secondary panel.

**Named accessibility action fallback for detail entries**: besides their primary button closures, the 4 detail-entry buttons above (the header `OPCTerminalHallLocalMaintenanceHeaderTrigger` and the three summary cards' `OPCAdvancedMaintenance{Architecture,Gateway,Local}DetailTrigger`) each register an `.accessibilityAction(named:)` fallback with the same name as their `accessibilityLabel` — respectively "Open Local Maintenance Details", "View Multi-Employee Architecture Health Check Details", "View Communication Gateway & Phone Commands Details", and "View Local Stability & CLI Operations Details". They write the same `presentedDetail` case as the button's main closure, for Computer Use when AXPress only grabs focus without triggering the SwiftUI closure: the named action can be invoked directly via `NSAccessibilityElement.action(name:)` / `osascript ... AX action` to open the detail sheet. The `LocalMaintenanceSummaryCard` card itself also keeps the container-level action "View Local Maintenance Details", coexisting with the button's own "View Local Stability & CLI Operations Details".

The "Run Evidence Archive (CTO Only)" SectionHeader inside the secondary sheet still exists (in the lower half of the `LocalMaintenanceCenter` detail panel), so Computer Use can quickly locate the maintenance audit / maintenance artifact archive groups by SectionHeader text and then drill down to a specific a11y identifier.

**Single canonical location for history index / history archive migration previews**: inside the `LocalMaintenanceCenter` detail sheet, "History Index Preview" is rendered by `HistoryIndexAuditPreview()` (directly under the "Run History Index Audit" button, anchor: `OPCHistoryIndexAuditPreview`) and "History Archive Migration Preview" by `HistoryArchiveMigrationPreview()` (directly under the "Run History Archive Migration" button, anchor: `OPCHistoryArchiveMigrationPreview`); the detailed operations area below **no longer writes** duplicate `SectionHeader(title: "History Index Preview")` / `SectionHeader(title: "History Archive Migration Preview")` blocks. To locate history previews, Computer Use targets those two preview cards directly and reads the current body from accessibilityValue — no screenshot OCR. The detailed operations area below keeps only SectionHeader blocks without primary-button duplicates, such as "Local File Index Root Allowlist", "Auto Summary Dedup Preview", and "Legacy Task Ownership Migration Preview".

**Employee card CLI task log summary**: Terminal Hall employee cards call `visibleTerminalLog(for:)`; a completed `[OPC CLI Task] ... [Command exit code N] ... [OPC Interaction Status]` transcript is displayed on the default card as `[OPC CLI Task Summary]`, keeping only the execution location, run mode, task summary, exit code, and interaction status, with a note that the full output remains in the CLI job archive. Raw `terminalLogs`, job archives, and the right-side raw terminal audit sources are unchanged; ordinary model output without a full exit-code boundary is still kept per the existing rules.

**Employee card real terminal workspace log summary**: the `[OPC Real Terminal Workspace]` startup transcript is displayed on the default employee card as `[OPC Real Terminal Workspace Summary]`, keeping only the seat creation status, abstract execution location, and maintenance archive hint; raw shell commands, user prompts, `printf` text, and absolute paths stay only in the raw `terminalLogs` / maintenance archive troubleshooting sources and never enter the default card.

**Persistent-terminal full-task runner**: full employee task submission no longer pastes long prompts / multiline arguments directly into the real terminal pane. OPC writes a one-shot runner at `.opc/runtime/terminal-runners/<marker>.sh` under the current product root, and the real pane only receives the short `/bin/sh <runner>` command; the runner handles the start/end markers, execution-directory switching, command arguments, exit-code return, and self-cleanup on exit. The runner directory must stay `0700`, and stale `.sh` files older than 6 hours are cleaned before a new task starts; if Computer Use or manual troubleshooting sees many leftover scripts in that directory, first check whether the previous terminal task was force-killed outside the system.

**Employee prompt token budget boundary**: employee chat prompts truncate overlong segments of recent chat, long-term memory, current chat text, and chat-correction drafts, keeping the current product, identity, task, memory summary, and an "N more items" tracking hint; the profile block of employee execution prompts truncates mission, responsibilities, boundaries, reply rules, long-term memory, current-product employee memory, and skill summaries, with the full configuration still kept in the employee workspace files. Never truncate the current `userPrompt` task body of `agentExecutionPrompt`; that body is this round's real work instruction, and truncation would degrade execution capability.

**Employee task prompt budget boundary**: `workOrderPrompt` keeps only a small number of rules, tools, and project-file clues from the import report; long paths, long acceptance criteria, and long entries are truncated, with an "N more items saved in the import report" hint so full clues remain readable on demand; rework prompts from review/Boss rejections truncate long reasons and long success criteria. Never concatenate the imported project's full file list, overlong acceptance text, or large rework explanations directly into an employee CLI prompt.

**Employee collaboration message token budget boundary**: the structured collaboration message bus stores only short subjects and limited bodies, so review conclusions, acceptance criteria, report bodies, or handover notes never become a second unbounded context. When a full long report is needed, write it to artifacts, the employee workspace, or audit archives, and put a summary plus locating clues in the collaboration message.

**Long-lived CLI session token budget boundary**: the first run sends the employee operational profile and this round's task; session resumes for the same product, same employee, and same backend only send this round's task plus a one-line context hint, never re-sending the full mission, responsibilities, memory, and skills. Employee profile files also use content-diff judgment in sync; when content is unchanged, rule/memory files are not refreshed, reducing CLI context re-reads caused by file changes.

**Terminal Hall Run-All token budget boundary**: the top "Run All" is kept, but when the prompt is the default report and would be sent to multiple runnable employees at once, a Chinese confirmation must appear first. This keeps the workflow enabled while avoiding one misclick consuming the whole team's CLI quota.

### Maintenance Record Filtering Visual Verification

Real-terminal auto-loop preflight rejection scenario (easiest to reproduce: switch the employee source to interface mode, then click "Start Controlled Loop"):

1. The Boss Command Center "Recent Delivery & Acceptance" widget: the "Real Terminal Auto-Loop Readiness Audit" title must not appear.
2. Product-detail delivery area prefix(3) and the Delivery & Acceptance Center prefix(12): same.
3. Operations-suite acceptance drawer prefix(6): same.
4. The Terminal Hall maintenance area "Technical Maintenance Audit Center": this "Real Terminal Auto-Loop Readiness Audit · Has Warnings" record is visible.
5. Architecture health check text: ends with "Most recent real-terminal auto-loop readiness audit: Has Warnings · Readiness check: most recent dedicated ready prompt not confirmed".

Equivalent verification at the data-accessor level is guarded by the `realTerminalAutoLoopRejectionRoutesAuditToMaintenanceOnlyAndKeepsBossViewsEmpty` test; if a11y identifiers or view data sources are broken in the future, `swift test` catches it immediately.

## Distribution

For personal local use, run from source or build a local executable.

The current formal-use target is single-user local use on this Mac, so Developer ID signing, notarization, DMG packaging, Sparkle updates, and hosted crash reporting are not blockers. `scripts/build_app_bundle.sh` performs ad-hoc signing to keep the local app identity more stable for macOS privacy prompts.

For product distribution outside the Mac App Store:

- Enroll in Apple Developer Program.
- Sign with Developer ID.
- Notarize the app.
- Ship a DMG or ZIP.
- Use Sparkle for updates.
