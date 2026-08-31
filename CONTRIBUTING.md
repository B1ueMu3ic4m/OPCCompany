# Contributing to OPC Company

Thanks for helping build the AI company! This document covers the basics; architecture details live in [docs/MULTI_AGENT_ARCHITECTURE.en.md](docs/MULTI_AGENT_ARCHITECTURE.en.md).

## Ways to Contribute

- 🐛 **Bug reports** — open an issue with steps to reproduce, expected vs actual behavior, and your macOS/Swift version.
- 🌐 **Translations** — the UI is bilingual via a generated string table. Add/edit entries in `Resources/l10n/en.json` (zh → en map), then run `python3 scripts/generate_l10n.py` and commit both the JSON and regenerated artifacts.
- 🎨 **SpriteKit scene work** — company floor, character states, animations.
- 🔌 **Backend adapters** — new subscription CLIs or API providers behind the `BackendType` model.
- 📝 **Docs** — especially non-English docs and diagrams.

## Ground Rules

1. **Run the tests.** `swift test --no-parallel` must pass (currently 568 tests). Tests encode security boundaries (permission gates, secret handling) — do not weaken them to make code pass.
2. **Respect the company metaphor.** The boss decides; the CTO dispatches; employees execute. Don't add UI that lets employees bypass approval gates.
3. **No secrets in code.** API keys live in Keychain or xcconfig. Never hard-code endpoints, tokens, or personal paths. CI and maintainers run secret scanning (gitleaks).
4. **Keep the i18n invariant.** New user-facing Chinese strings must get an English counterpart in `Resources/l10n/en.json`. Tests assert string-table integrity.
5. **Swift 6 concurrency** — respect `Sendable` boundaries; UI updates on `@MainActor`.

## Dev Workflow

```bash
git clone https://github.com/B1ueMu3ic4m/OPCCompany.git
cd OPCCompany
swift build                # compile
swift test --no-parallel   # full suite
scripts/build_app_bundle.sh && open dist/OPCCompany.app   # try it
```

## Commit Style

Short imperative subject, e.g. `fix: prevent reviewer approving its own delivery`. Body explains *why* when non-obvious.

## Review

Maintainers aim to review within 48 hours. Changes touching permission boundaries, secret handling, or the approval flow require extra scrutiny and may ask for targeted tests.
