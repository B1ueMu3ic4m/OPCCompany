# OPC Company Agent Instructions

Last updated: 2026-05-07

This repository is governed by `OPC_COMPANY.md`.

Current status: OPC Company has reached the single-user local formal-use baseline. Treat new work as maintenance, targeted enhancement, or user-requested product changes; do not reopen broad optimization loops without a concrete blocker.

Before making product, architecture, UI, agent, workflow, or behavior changes:

1. Read `OPC_COMPANY.md`.
2. Keep the boss/CTO/employee responsibility boundaries intact.
3. Do not expose backend complexity in boss-facing UI unless it is a decision, risk, approval, progress, or deliverable.
4. Do not hard-code fake employee personalities. Employee chat should call the configured backend or show a clear local fallback.
5. Keep model configuration stable per employee. Do not silently downgrade chat to a different model than the employee profile.
6. Preserve the company metaphor: product teams, CTO coordination, employee roles, task graph, artifacts, approvals, and visible work state.
7. Update `OPC_COMPANY.md` when changing product direction, architecture, role rules, UI information architecture, permission rules, or major roadmap status.

Implementation defaults:

- Use SwiftUI for panels and state-driven UI.
- Use SpriteKit for the 2D company scene and character animation.
- Keep edits scoped to `Sources/OPCCompany/**`, `Tests/OPCCompanyTests/**`, `docs/**`, and root documentation unless the task explicitly requires more.
- Run `swift test --no-parallel` after non-trivial code changes unless a narrower target test is explicitly enough for an intermediate step.
- Build the desktop app bundle with `scripts/build_app_bundle.sh` when the user needs to try the app.
- Safe cleanup: `.build/` is disposable build cache; keep `Tests/`, `dist/OPCCompany.app`, root documentation, `.claude/`, `.ccb/`, and real OPC local support data unless the user explicitly asks otherwise.
