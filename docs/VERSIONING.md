# Versioning

v3.0.0 reset the ladder the fast-minor v2.x era wore out and locked the
semantics. This page is the policy of record; the
[CHANGELOG](../CHANGELOG.md) stays the entry-by-entry history, and the
[Releases page](https://github.com/B1ueMu3ic4m/OPCCompany/releases)
stays exactly as shipped — releases are immutable.

## The semantics

| bump | means | cap |
|---|---|---|
| **major** | a disruptive change: the version policy itself, a contract break, an architecture rewrite | — |
| **minor** | a LARGE change: a new door, a new gate, a surface milestone | **never above 9** |
| **patch** | routine fixes and docs | never above 9 (then minor) |

When minor would reach 10, the change is by definition major — that is
the rule that keeps the numbers meaningful.

## The eras (re-classified)

| era | range | what it was |
|---|---|---|
| **Founding arc** | v0.1 – v0.18 | the GUI takes shape; the five boss doors (standup / team / stalls / catch-up / weight), the live office, seat steering, notifications, `--json` everywhere |
| **Door ladder** | v1.1 – v1.19 | the CLI door ladder: goals, risks, messages, task_show, search, ack, message_ack_all, product ledger — every door pure-read, `--json` byte-identical with the bridge |
| **Fast-minor era** | v2.0 – v2.45 | the Windows office opens, write receipts (goal/decide/checkpoint), the contract ladder v1.18 → **v1.32** (35 verbs), every door on every front end, the seven release gates, doors-under-load, the shell signs itself — one minor per release, five weeks, 45 minors. Retired by this policy; the work stands. |

## The cadence now

- A **patch** (v3.0.x) is docs, test hardening, or a small fix — it
  rides the next natural release rather than shipping alone.
- A **minor** (v3.1, v3.2 …) only when something LARGE lands: a new
  door, a new gate, a new surface.
- A **major** only for the disruptive. The bar is deliberately high.

## Enforcement

- `VERSION` is the single source; the CLI banner, `opc version`, the
  shell's `kShellVersion` and pubspec.yaml pin it at release time.
- `scripts/verify-release.sh` gates **seven checks** on every release,
  including "cask version == tag" and "shell pubspec version == tag" —
  a version that lies about itself cannot ship.
- A consistency test keeps CLI + plist + VERSION in lockstep.
