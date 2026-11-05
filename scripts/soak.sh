#!/usr/bin/env bash
# The overnight soak, one command: the full Swift suite (4 test suites)
# and the full Flutter shell suite, each counted, failures aggregated.
# Usage: bash scripts/soak.sh [rounds]   (default 1; the nightly loop
# runs several between releases). Exit 0 only if EVERY round of BOTH
# suites is green.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUNDS="${1:-1}"
cd "$ROOT_DIR"

fail=0
for i in $(seq 1 "$ROUNDS"); do
  echo "── soak round $i/$ROUNDS ──"

  if out=$(swift test 2>&1); then
    echo "swift: $(echo "$out" | grep -oE 'Test run with [0-9]+ tests in [0-9]+ suites passed[^.]*' | tail -1)"
  else
    echo "swift: FAILED"
    echo "$out" | grep -E '✘|error:' | head -10
    fail=1
  fi

  if out=$( (cd flutter_shell && flutter test 2>&1) ); then
    echo "dart:  $(echo "$out" | grep -oE '\+[0-9]+( -[0-9]+)?: All tests passed!' | tail -1)"
  else
    echo "dart:  FAILED"
    echo "$out" | grep -E 'FAILED|EXCEPTION' | head -10
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "soak: $ROUNDS round(s) clean"
else
  echo "soak: FAILURES above"
fi
exit "$fail"
