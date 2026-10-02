#!/usr/bin/env bash
# release-notes.sh — extract ONE version section from CHANGELOG.md for
# `gh release create --notes-file`. Usage: scripts/release-notes.sh 2.5.0
# Prints the section body (everything between its header and the next
# `## [`), so the Release page and the changelog can never drift.
set -euo pipefail
VERSION="${1:?usage: release-notes.sh <x.y.z>}"
cd "$(dirname "$0")/.."
python3 - "$VERSION" <<'PY'
import sys
version = sys.argv[1]
lines = open('CHANGELOG.md', encoding='utf-8').read().split('\n')
start = None
for i, line in enumerate(lines):
    if line.startswith(f'## [{version}]'):
        start = i + 1
        break
if start is None:
    sys.exit(f'no section for {version} in CHANGELOG.md')
out = []
for line in lines[start:]:
    if line.startswith('## ['):
        break
    out.append(line)
body = '\n'.join(out).strip()
if not body:
    sys.exit(f'section [{version}] is empty')
print(body)
PY
