#!/usr/bin/env bats
# Unit tests for saveBackup() -- the single file-writing sink.
# Bash-specific (the PowerShell version has its own Pester unit tests). The
# shared contract lives in the e2e + expected layer.

load test_helper

setup() {
  load_exporter
  TMP="$(mktemp -d)"
  backup_dir="$TMP"
  log="$TMP/exporter.log"
  declare -gA devices=([1]="10.0.0.1" [2]="switch01.lab")
}

teardown() {
  rm -rf "$TMP"
}

@test "TEXT backup: .txt extension, decoded content, correct path" {
  run saveBackup 1 "2021-01-01-00:00:00-UTC" "$(printf 'hello world\n' | base64)" TEXT
  [ "$status" -eq 0 ]
  local f="$backup_dir/10.0.0.1 - 1/Backup 10.0.0.1 2021-01-01-00:00:00-UTC 1.txt"
  [ -f "$f" ]
  [ "$(cat "$f")" = "hello world" ]
}

# Catches review bug #3 (`local type ='bin'`). RED until that line is fixed.
@test "BINARY backup: .bin extension" {
  run saveBackup 2 "2021-04-01-00:00:00-UTC" "$(printf 'AAECAwQF' )" BINARY
  local f="$backup_dir/switch01.lab - 2/Backup switch01.lab 2021-04-01-00:00:00-UTC 2.bin"
  [ -f "$f" ]
}

@test "idempotent: re-running does not overwrite an existing backup" {
  local f="$backup_dir/10.0.0.1 - 1/Backup 10.0.0.1 2021-01-01-00:00:00-UTC 1.txt"
  saveBackup 1 "2021-01-01-00:00:00-UTC" "$(printf 'first\n' | base64)" TEXT
  saveBackup 1 "2021-01-01-00:00:00-UTC" "$(printf 'second\n' | base64)" TEXT
  [ "$(cat "$f")" = "first" ]
}

@test "honors a custom separator (issue #8)" {
  separator='_'
  run saveBackup 1 "2021-01-01-00:00:00-UTC" "$(printf 'x\n' | base64)" TEXT
  [ "$status" -eq 0 ]
  [ -f "$backup_dir/10.0.0.1_-_1/Backup_10.0.0.1_2021-01-01-00:00:00-UTC_1.txt" ]
}

@test "defaults to a space separator when unset" {
  unset separator
  run saveBackup 1 "2021-01-01-00:00:00-UTC" "$(printf 'x\n' | base64)" TEXT
  [ -f "$backup_dir/10.0.0.1 - 1/Backup 10.0.0.1 2021-01-01-00:00:00-UTC 1.txt" ]
}
