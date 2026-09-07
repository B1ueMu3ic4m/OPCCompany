# Security Policy

## Design stance

OPC Company is a **local-first** macOS app. It has no accounts, no telemetry,
and no backend service of its own. Everything runs on your machine.

## What is protected, and how

| Surface | Handling |
|---|---|
| API keys (API-model employees) | Stored in the macOS **Keychain**, never in the persisted state snapshot; passed to the CLI/API runner as environment variables only |
| Terminal logs | Backend command lines with secrets/flags are hidden from visible logs (see `docs/COMMUNICATION_GATEWAY_SECURITY.md`); full raw archives stay local |
| Product paths | Displayed tilde-abbreviated (`~/Library/...`) in UI — screenshots never leak usernames |
| Inbound commands (communication gateway) | Verified with nonces and configured channels; unverified inbound requests are rejected |
| Employee permissions | Per-agent gates: Read Files / Edit Files / Run Tests / Run Commands / Use Network — default-deny, boss approval required for risky actions |
| Real model invocations | Only happen when you press Run; Preflight is a local audit with no quota cost |

## Reporting a vulnerability

Please report security issues **privately** via
[GitHub Security Advisories](https://github.com/B1ueMu3ic4m/OPCCompany/security/advisories/new)
— do not open a public issue.

We aim to acknowledge within 7 days and ship a fix within 30 days for
confirmed issues.

## Scope

This policy covers the app and its documented behaviors. Running arbitrary
AI agents that can edit files or run commands carries inherent risk — the
permission gates and approval flow exist to bound it, but you remain in
control of what each employee is allowed to do.
