<!-- Translated from TERMINAL_HALL_DESIGN.md; the Chinese original remains authoritative for internal history. -->

# Terminal Hall Design

Last updated: 2026-05-07

Current status: The Terminal Hall has reached the single-user local formal-use baseline. The default UI uses a summary workbench plus employee terminal cards, and no longer piles full backend commands, paths, raw transcripts, or collapsible explanations onto the first screen.

## Goals

The Terminal Hall lets the Boss see all AI employees working at once, instead of watching only one employee's logs. It is the second core work surface alongside the 2D Company Floor.

## Interface structure

```text
┌─────────────────────────────────────────────────────────┐
│ Terminal Hall                     [Local Maint] [Run All] │
├────────────────────┬────────────────────┬────────────────┤
│ Codex CTO          │ Gemini UI Designer │ Claude Code     │
│ Status: thinking   │ Status: designing  │ Status: coding  │
│ Preflight summary  │ Preflight summary  │ Preflight summary│
│ Task summary/state │ Task summary/state │ Task summary/state│
├────────────────────┼────────────────────┼────────────────┤
│ Codex Reviewer     │ Test Engineer      │ System Log      │
│ Status: reviewing  │ Status: standby    │ Events/Errors/  │
│                    │                    │ Approvals       │
└────────────────────┴────────────────────┴────────────────┘
```

## Operations

- One terminal card per employee.
- Cards show status, source summary, session-resume summary, run preflight, task summary, exit code, and interaction state.
- The Boss can click a card to enlarge it.
- Tasks can be run for individual employees, preflight audits can be written, and visible logs can be cleared.
- Local maintenance details provide a real terminal workspace, manual interaction rounds, automatic interaction loops, history indexing, archive migration, and maintenance audits.
- "Run All" is retained, but when it would hit multiple runnable employees with the default reporting prompt, confirmation is required first, so multiple employees' quota is not accidentally consumed by one misclick.

## Technical roadmap

### Phase A: In-app multi-terminal log wall (implemented)

- Keep using `Process`.
- Each employee has its own `terminalLogs[agentID]`.
- Add TerminalHallView.
- Support multiple employees running non-interactive CLIs simultaneously.
- Stream stdout/stderr via Pipe, appended to the corresponding employee terminal.

The current app already supports:

- The main UI switches between "Company Floor" and "Terminal Hall".
- Each non-Boss employee has its own terminal card.
- Run individually, run all, select an employee, clear a single employee's logs.
- Codex / Claude / Gemini command previews and output records.
- While a CLI runs, stdout/stderr keep appending to the employee terminal card.
- Each employee has independent run state, and the CTO is synced automatically on completion.

### Phase B: Controlled interactive sessions

Status: basic capability implemented.

- Each AgentSession records:
  - process
  - stdin pipe
  - stdout buffer
  - stderr buffer
  - status
  - startedAt
  - exitCode

### Phase C: tmux real workspace

Status: implemented and wired into the local maintenance area.

- Create an `opc-company` tmux session.
- One pane/window per employee.
- The App dispatches tasks via `tmux send-keys`.
- The App captures for display via `tmux capture-pane`.
- The Boss can click "Open Real Terminal" to enter tmux.

Additional notes on the current real-terminal implementation:

- Full tasks are sent via one-shot runner scripts; the real pane only receives short commands, avoiding long prompts triggering shell/file-name races.
- Single-line manual input goes through a literal-paste path that writes nothing to the job archive and does not affect full-task markers.
- Automatic interaction loops only start explicitly from the CTO maintenance area, bound to task context and a maximum turn count.

## Safety rules

- Code-related employees require workspace permission by default.
- Dangerous commands require Boss approval.
- Parallel code changes must use git worktree.
- The CTO can view all terminal summaries.
- Default visible cards do not show absolute paths, underlying CLI arguments, or full model transcripts; full materials stay in the job archive and maintenance logs.
