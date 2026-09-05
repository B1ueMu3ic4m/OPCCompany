# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-09-03

### Fixed
- **Language switching (root cause, 4 structural bugs)**
  - Switch-time data refresh moved into `L10nEnvironment.didSet` — the previous
    view-level `.onChange` never fired because `.id(resolved)` rebuilt the view
    tree first (PR #3)
  - 40 `static let` localized constants converted to computed properties; they
    previously froze the language of their first access (PR #3)
  - 9 persisted-data matching collections (maintenance/delivery classification,
    CLI diagnostic prefixes, interaction-profile signal arrays) converted to
    bilingual unions, so data created in either language always matches (PR #3)
  - Builtin agent display names and job titles now follow the session language
    in both directions, including legacy debris forms such as
    `Chief 技术负责人` → `Chief CTO` (PR #2, PR #3)
  - Warmup terminal logs re-render symmetrically (zh ↔ en) regardless of the
    language they were generated in (PR #1)
  - System welcome notices in the chat bubble re-map to the current language (PR #1)
  - Window title, seat/people labels, and prefixed/interpolated `.L()` keys
    that could never hit the translation table
- **Privacy**
  - Product root paths are displayed tilde-abbreviated (`~/Library/...`) in the
    Command Center header — no usernames leak into screenshots
  - Demo capture script rewritten to window-only capture (never records the desktop)
- **Performance**
  - SpriteKit office scene is cached across SwiftUI body evaluations; it was
    previously rebuilt on every store mutation (visible stutter during terminal
    streaming)

### Added
- CI workflow (`.github/workflows/ci.yml`): build + full test suite on every
  push and pull request
- This changelog
- Language menu now shows what "Follow System / Auto" resolves to, and the
  currently effective language
- Test suite grown to 576 tests, including language-switch regression guards

## [0.1.0] - 2026-08-31

### Added
- Initial public release
- 2D pixel-art "company" visualization of AI coding agents (Claude Code, Codex,
  Gemini CLI, API models, local placeholders)
- Boss → CTO → employee task orchestration with approval gates and delivery
  acceptance
- Terminal Hall with per-employee persistent sessions and auto-interaction loops
- Full bilingual UI (Simplified Chinese / English) with in-app language switcher
- English translations of all core documentation
- Homebrew tap installation (`brew install B1ueMu3ic4m/tap/opc-company`)
- 568 tests, MIT license, issue templates, contributing guide

[0.1.1]: https://github.com/B1ueMu3ic4m/OPCCompany/releases/tag/v0.1.0
[0.1.0]: https://github.com/B1ueMu3ic4m/OPCCompany/releases/tag/v0.1.0
