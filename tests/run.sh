#!/usr/bin/env bash
# Run the whole test suite locally. Mirrors CI (see tests/ci.yml).
# Runs every stage even if an earlier one fails, then reports a summary.
#
# Usage:  tests/run.sh
# Override the implementation under test (e.g. the PowerShell version):
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

stage "powershell e2e (same suite, against the .ps1 version)"
if command -v pwsh >/dev/null; then
  ( cd "$tests_dir" && EXPORTER_FILES="unimus-backup-exporter.ps1" \
      EXPORTER_CMD="pwsh ./unimus-backup-exporter.ps1" \
      python3 -m unittest discover -s . -p 'test_*.py' -v ) || rc=1
else
  echo "pwsh not installed - SKIPPED"
fi

stage "powershell unit tests (Pester)"
if command -v pwsh >/dev/null; then
  # -PassThru + FailedCount as the exit code (avoids -CI's testResults.xml artifact).
  pwsh -NoProfile -Command "exit (Invoke-Pester -Path '$tests_dir/unit/pwsh' -PassThru).FailedCount" || rc=1
else
  echo "pwsh not installed - SKIPPED (needs pwsh + Pester 5)"
fi

stage "summary"
[ "$rc" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES (exit $rc)"
exit "$rc"
