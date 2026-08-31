# GitHub Research: Similar OPC Company Products

Research date: 2026-04-28

Status as of 2026-05-07: archived research note. Use this file for product positioning references only; current implementation status, architecture rules, and formal-use boundary live in `OPC_COMPANY.md`, `docs/RUNBOOK.md`, and `docs/MULTI_AGENT_ARCHITECTURE.md`.

## Summary

I did not find a single product that fully matches OPC Company: a native macOS 2D company scene where the user is the boss, a CTO agent coordinates Codex/Claude/Gemini subscription CLIs, and animated employee agents work in visible terminals.

The closest public projects each solve one slice:

- 2D AI office metaphor
- Multi-agent task orchestration
- CLI agent terminal management
- git worktree isolation
- desktop UI wrappers for coding agents
- human-in-the-loop supervision

The product opportunity remains differentiated if OPC Company combines these into one local-first macOS app.

## Closest References

### 1. AgentOffice

Repository: https://github.com/harishkotra/agent-office

What it is:

- Browser-based 2D pixel office where AI agents work together.
- Uses React frontend, Phaser.js 2D scene, Colyseus server, SQLite, Prisma, and Ollama/local LLM.
- Agents have roles such as planner, designer, and executor.
- Includes task delegation, memory, and a multiplayer office concept.

What to learn:

- The office metaphor is viable.
- Phaser-style 2D scenes map well to agent status and collaboration.
- Agent roles can be represented spatially.

Why OPC should differ:

- OPC should be native macOS, not browser-first.
- OPC should integrate real subscription CLIs: Codex, Claude Code, Gemini CLI.
- OPC should use CTO-centered orchestration and local terminal/process control.
- OPC should support custom employees backed by the same model with different roles.

### 2. agtx

Repository: https://github.com/xhiroga/agtx

What it is:

- Terminal UI for managing multiple AI coding agents.
- Uses Kanban-style workflow.
- Supports parallel agents, tmux, git worktrees, and MCP integration.

What to learn:

- Task cards are the right coordination unit.
- tmux + git worktree is a practical backend for visible parallel AI work.
- The user needs orchestration, not just chat.

Why OPC should differ:

- OPC should present an animated company metaphor instead of a terminal-only Kanban.
- OPC should centralize authority in a CTO agent.
- OPC should support direct conversations with employees while keeping CTO awareness.

### 3. claude-squad

Repository: https://github.com/smtg-ai/claude-squad

What it is:

- Terminal app for managing multiple AI agents such as Claude Code, Codex, Gemini, Aider, and Amp.
- Uses separate workspaces and lets the user review changes.

What to learn:

- Multi-agent CLI management is already a known pattern.
- The important primitives are session isolation, diff review, and easy switching.

Why OPC should differ:

- OPC should be a productized local macOS app, not just a TUI.
- OPC should add animated roles, company memory, CTO dispatch, and richer artifact management.

### 4. Commander

Repository: https://github.com/lukaszraczylo/commander

What it is:

- Native Tauri desktop app for orchestrating multiple AI coding agents.
- Includes chat, streaming output, git worktree management, and real-time task handling.

What to learn:

- A desktop shell around CLI agents is feasible.
- Live streaming, worktree isolation, and task management belong in the core product.

Why OPC should differ:

- OPC should use a native macOS SwiftUI/SpriteKit interface.
- OPC should use 2D company characters and office spaces as the primary navigation model.

### 5. Open Cowork

Repository: https://github.com/Piebald-AI/open-cowork

What it is:

- Desktop application for managing coding agents such as Claude Code and Gemini CLI.
- Focuses on local app workflow, agent sessions, skills, sandboxing, and integrations.

What to learn:

- Desktop management of subscription CLI agents is the right category.
- Skills, rules, sandboxing, and session management should be first-class.

Why OPC should differ:

- OPC should own a stronger CTO orchestration layer.
- OPC should provide a more visual 2D company experience, not only a productivity console.

### 6. Codexia

Repository: https://github.com/lejarib/codexia

What it is:

- Tauri desktop app for managing AI coding agents like Codex and Claude.
- Includes task scheduling, git worktree management, editor/terminal integration, and multi-agent workflows.

What to learn:

- Task scheduler + terminal + editor + worktree is a proven product stack.
- Agent outputs should be reviewable as artifacts.

Why OPC should differ:

- OPC should focus on role-based employees, animation states, and CTO visibility.

### 7. AgentOS

Repository: https://github.com/ktmouk/agentos

What it is:

- Web UI to manage multiple coding agent tasks.
- Uses Claude Code-style workflows, git worktrees, and live terminal streaming.

What to learn:

- Browser UI can show multiple terminals and task statuses.
- Live output streaming is useful.

Why OPC should differ:

- The user prefers a local Mac app, not a browser dashboard.
- OPC should avoid web fragility and use native local process control.

### 8. CLI Agent Orchestrator

Repository: https://github.com/awslabs/cli-agent-orchestrator

What it is:

- Hierarchical orchestration framework for multiple AI agents.
- Uses terminal multiplexer sessions, MCP, and explicit orchestration patterns.

What to learn:

- Hierarchical orchestration matches the CTO-to-employees structure.
- Shared context and task routing are more important than open-ended group chat.

Why OPC should differ:

- OPC should wrap this orchestration in a consumer-grade macOS interface.

## Design Decisions For OPC Company

### Keep

- Native macOS app as the product surface.
- SwiftUI for panels and state-driven UI.
- SpriteKit for 2D office scene.
- CTO-centered hierarchy.
- tmux/PTY-backed live terminal execution.
- git worktree isolation for code-changing agents.
- job directories for artifacts and transcripts.
- employee role configuration independent of model backend.

### Add From References

- Kanban/task-board discipline from agtx.
- Multi-agent session management from claude-squad.
- Desktop terminal streaming from Commander/Codexia/Open Cowork.
- Hierarchical orchestrator design from CLI Agent Orchestrator.
- 2D office metaphor validation from AgentOffice.

### Avoid

- Browser-only dashboard as the primary product.
- Free-form group chat between all agents.
- Web-cookie automation of subscription products.
- Multiple agents editing the same workspace without worktrees.
- Making the visual office decorative only; it must map to real agent state.

## Updated Product Thesis

OPC Company should not compete as another coding-agent terminal manager. It should become a local AI company operating system:

- The boss talks to people, not model endpoints.
- CTO owns orchestration and context.
- Employees are visible, stateful, configurable, and backed by real subscription or API models.
- Work is observable through terminal output, artifacts, diffs, and animated status.
- The 2D office scene is not decoration; it is the primary command surface.
