# OPC Company Product Specification

Last updated: 2026-05-07

Status: current product direction. OPC Company has reached the single-user local formal-use baseline on this Mac. This spec describes the product shape; `OPC_COMPANY.md` is the governing source for current architecture, role boundaries, and verified roadmap state.

## Product Vision

OPC Company is a local macOS application that turns a user's AI workflow into a 2D company scene. The user is the boss. A CTO agent coordinates specialist AI employees backed by subscription CLIs and API models. Employees are represented as configurable animated people seated in offices or an open work hall. The user can talk to the CTO or any employee, watch work status, inspect live terminals, review artifacts, and approve risky actions.

The app is designed for local-first daily work. It does not require Mac App Store distribution for the current user. For future use by other people or other Macs, re-evaluate Developer ID signing, notarization, a DMG installer, Sparkle updates, and hosted crash reporting.

## Core User Experience

The first screen is the company floor.

- The boss is a Chinese person in a suit, seated in a private office with desk, chair, and computer.
- The CTO is a white person in a suit, seated in a separate private office with desk, chair, and computer.
- Specialist employees sit in an open office hall. Each has a desk, chair, and computer.
- Employees can be customized by model provider, role, skin tone, ethnicity presentation, gender presentation, hair, clothing, desk style, and avatar animation style.
- Clicking any character opens a dialogue panel for direct conversation.
- Replies can appear as speech bubbles, dialogue panels, and logged transcript entries.
- The CTO sees summaries of all direct conversations and all task outcomes.
- The user can add new employees from subscription CLIs or API models.
- The same model can back multiple employees with different roles and permissions.

## Primary Modules

### 1. Company Scene

- 2D office floor rendered with SpriteKit inside SwiftUI.
- Private boss office and CTO office at the top.
- Employee hall with grid or seat map layout.
- Desks, chairs, computers, nameplates, and status lights.
- Smooth camera-free fixed composition suitable for laptop screens.
- Character state animations: idle, thinking, talking, typing, coding, reviewing, blocked, waiting approval, done, failed.

### 2. Boss Chat

- Primary dialogue between user and CTO.
- CTO translates user intent into project tasks.
- CTO can ask clarifying questions when needed.
- CTO can dispatch employees, pause work, request approval, and produce final reports.

### 3. Employee Dialogue

- User can speak directly to any employee.
- Direct dialogue is logged as company events.
- CTO receives a concise event summary.
- Employees can suggest follow-up tasks, but CTO owns scheduling unless the user grants direct execution.

### 4. Agent Management

- Add employee.
- Choose backend:
  - Subscription CLI: `codex`, `claude`, `gemini`.
  - API model: OpenAI-compatible, Anthropic, Gemini, DeepSeek, Qwen, Doubao, or custom.
- Assign role, title, avatar, permissions, prompt rules, working directory scope, and reporting line.
- Create multiple roles from one model backend.

### 5. CTO Orchestration

- Parse user request.
- Generate task plan and success criteria.
- Decide participating agents and execution order.
- Write task cards for employees.
- Watch employee status and outputs.
- Trigger review and repair loops.
- Summarize final outcome for the user.

### 6. Task Center

- Shows tasks, status, owner, dependencies, artifacts, and blockers.
- Task states: draft, planned, assigned, running, waiting, blocked, needs review, needs approval, done, failed, canceled.
- Each task has a local job directory under `.opc/jobs/<job-id>/`.

### 7. Live Terminals

- Each CLI-backed agent runs in a managed PTY or tmux pane.
- The app can show live output in a terminal panel.
- Users can focus an agent terminal, send follow-up messages, pause, resume, or stop.

### 8. Artifacts

- Plans, UI specs, code reports, diffs, review reports, test output, transcripts, and final delivery summaries.
- Artifacts are indexed in SQLite and stored as local files.

### 9. Permission Center

- Local command approval policy.
- Dangerous commands require user approval.
- Agents have explicit read/write scopes.
- Code-changing agents should work in git worktrees for isolation when parallel implementation is enabled.

### 10. Memory Center

- Persistent role rules.
- User preferences.
- Project-specific memory.
- Past task summaries.
- Employee performance notes.

## Technology Stack

### macOS App

- Swift 6+
- SwiftUI for app shell, panels, forms, and state-driven UI
- SpriteKit for the 2D office scene
- AppKit bridge where needed for PTY/terminal rendering

### Local Orchestrator

Initial implementation can live in Swift application services. The architecture must keep a clean boundary so a Go, Rust, Node, or Python daemon can be introduced later.

- Agent registry
- Task planner
- Event bus
- Job directory manager
- CLI process runner
- Transcript recorder
- Artifact indexer

### Local Storage

- SQLite for structured data
- macOS Keychain for API keys and tokens
- Local file tree under `.opc/` for job artifacts

### CLI Backends

- Codex CLI: CTO, product architect, reviewer
- Claude Code: code implementation, refactor, test repair
- Gemini CLI: UI design, visual review, multimodal analysis

### API Backends

- Used for batch, low-cost, or highly structured tasks.
- Can be routed through a future LiteLLM adapter, but API routing is not the core product dependency.

## Non-Goals

- Do not scrape or automate web subscriptions through cookies.
- Do not require Mac App Store distribution.
- Do not make every agent fully autonomous without CTO visibility.
- Do not let multiple agents modify the same files without isolation.
