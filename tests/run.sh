#!/usr/bin/env bash
# Run the whole test suite locally. Mirrors CI (see tests/ci.yml).
# Runs every stage even if an earlier one fails, then reports a summary.
#
# Usage:  tests/run.sh
# Override the implementation under test (e.g. the future PowerShell port):
#   EXPORTER_FILES="unimus-backup-exporter.ps1" \
#   EXPORTER_CMD="pwsh ./unimus-backup-exporter.ps1" tests/run.sh

set -uo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$tests_dir/.." && pwd)"
rc=0

stage() { printf '\n=== %s ===\n' "$1"; }

stage "shellcheck"
if command -v shellcheck >/dev/null; then
  shellcheck "$repo_root/unimus-backup-exporter.sh" || rc=1
else
  echo "shellcheck not installed - SKIPPED"
fi

stage "e2e (python3 unittest)"
if command -v python3 >/dev/null; then
  ( cd "$tests_dir" && python3 -m unittest discover -s . -p 'test_*.py' -v ) || rc=1
else
  echo "python3 not installed - SKIPPED"
fi

stage "bash unit tests (bats)"
if command -v bats >/dev/null; then
  bats "$tests_dir/unit/bash/" || rc=1
else
  echo "bats not installed - SKIPPED (https://github.com/bats-core/bats-core)"
fi

stage "summary"
[ "$rc" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES (exit $rc)"
exit "$rc"
