# OPC Company Implementation Plan

Last updated: 2026-05-07

## Current Status

OPC Company has reached the current formal-use baseline for **single-user local use on this Mac**.

Latest verified baseline:

- Full test command: `swift test --no-parallel`
- Latest passing count: 555/555
- Local bundle command: `scripts/build_app_bundle.sh`
- Latest verified bundle: `dist/OPCCompany.app`, bundle version `20260507033423`
- Signature check: `codesign --verify --deep --strict dist/OPCCompany.app`
- Computer Use verification target: MacBook built-in display

This file is no longer the first-build task card. It is now the compact maintenance plan. The historical implementation task card remains below for context only.

## Formal-Use Scope

Included in current formal use:

- Local SwiftUI/SpriteKit macOS app.
- Product workspaces, boss/CTO/employee role boundaries, task graph, review, approvals, artifacts, verification records, and local memory.
- Codex / Claude Code / Gemini / API employee configuration.
- Terminal hall with per-employee cards, command previews, preflight summaries, persistent terminal support, CLI session resume, and token budget guards.
- Local JSON snapshot as authority, plus optional SQLite history index/archive sidecar.
- Local ad-hoc signed app bundle in `dist/`.

Not formal-use blockers for this single-user local target:

- Communication gateway mobile/public inbound linkage.
- Developer ID signing, notarization, DMG packaging, app updater, and hosted crash reporting.
- Multi-machine sync or external distribution.

## Maintenance Priorities

Only continue work when a concrete issue appears:

1. User-reported functional bug in daily local use.
2. Data-loss or unsafe-command risk.
3. Product cross-contamination between workspaces.
4. CLI busy/auth/retry problem that blocks real work.
5. Agent token budget regression.
6. MacBook main-screen UI regression verified through Computer Use.

Do not spend Codex or Claude Code quota on speculative rewrites, repeated polishing of already-passing flows, or broad "optimize everything" passes.

## Safe Cleanup Policy

- Safe to delete: `.build/` Swift cache.
- Keep by default: `dist/OPCCompany.app`, `Tests/`, `.claude/`, `.ccb/`, root docs, `docs/`, and real local app support data.
- `.ccb/` can be large because it stores collaboration logs; clean it only when the user no longer needs handoff traceability.

## Full Product Architecture

1. Native macOS app shell.
2. 2D SpriteKit company scene.
3. Character customization and status animation.
4. Dialogue panels for CTO and employees.
5. Agent registry supporting CLI and API employees.
6. CTO orchestration model.
7. Task board and artifact center.
8. Local event log.
9. CLI runner abstraction for Codex, Claude, and Gemini.
10. Permission and approval model.
11. Persistence using local JSON snapshot, local job directories, and SQLite history sidecar.
12. Future external distribution using Developer ID signing, notarization, and Sparkle only if the app is used outside this Mac.

## Historical Build Target

Historical first-build target, now completed:

- 2D office scene with boss office, CTO office, and employee hall.
- Clickable characters.
- Dialogue panel with message history and input field.
- Agent status board.
- Add employee panel with role/model/avatar options.
- In-memory event log.
- Real local state persistence and CLI runner paths for Codex, Claude Code, Gemini, API, and custom backends.

## Claude Code Task Card

Status: archived historical task card. Use `OPC_COMPANY.md`, `CLAUDE.md`, and `AGENTS.md` for current execution rules.

### Owner

Claude Code Engineer

### Scope

Implement the macOS SwiftUI/SpriteKit app foundation in this Swift package.

### Files May Change

- `Package.swift`
- `Sources/OPCCompany/**`
- `Tests/OPCCompanyTests/**`

### Required Features

- SwiftUI app entry point.
- Main window with:
  - Left agent roster/status board.
  - Center 2D company scene using SpriteKit.
  - Right dialogue/task/event panel.
- Characters:
  - Boss: Chinese, suit, private office.
  - CTO: white, suit, private office.
  - Employees: configurable sample agents seated in hall.
- Click character to select agent and open dialogue.
- Send a message to selected agent.
- CTO receives summarized awareness events for direct employee conversations.
- Add new employee from UI using simple in-memory form.
- Persist employee/dialogue/task/event state locally.
- Provide a terminal panel with command execution entry point.
- Agent model supports:
  - display name
  - role
  - backend type: subscription CLI or API
  - provider command/model
  - ethnicity presentation
  - gender presentation
  - clothing
  - status
  - permissions
- Include stub `CLIAgentRunner` protocol and sample command builders for `codex`, `claude`, and `gemini`.

### Verification

- `swift build`
- If Swift Package App entry causes packaging limits, implement compile-safe SwiftUI source and document run path.

### Design Direction

Refined 2D office simulator. Avoid generic dashboard style. Use a warm neutral office floor with strong status accents, readable panels, compact but premium controls, and character-centered interaction.
