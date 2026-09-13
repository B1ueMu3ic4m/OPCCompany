#!/usr/bin/env bash
# scan-secrets.sh — local secret sweep for OPCCompany.
#
# Why a script and not a CI action: the audit policy (see .gitleaks.toml)
# allowlists vendored SQLite test corpora + the DPAPI probe sentinel. Running
# that as CI would mean pulling a third-party container image (gitleaks) —
# widening the very supply chain we just hardened to `permissions: contents:
# read`. So this is run by hand (and by whoever opts into a runner with the
# gitleaks image pre-vetted), not wired into every push.
#
# Usage:  scripts/scan-secrets.sh [--work]   (default: full history)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "gitleaks not found. Install: brew install gitleaks" >&2
    exit 127
fi

args=(detect --source=. --no-banner --redact --config="$ROOT/.gitleaks.toml" --exit-code=1)
[[ "${1:-}" == "--work" ]] && args+=(--no-git)   # working tree only

if gitleaks "${args[@]}"; then
    echo "OK: no secrets (policy: .gitleaks.toml)"
else
    rc=$?
    echo "FAIL: gitleaks reported findings (exit $rc)" >&2
    exit "$rc"
fi
