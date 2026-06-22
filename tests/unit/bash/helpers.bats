#!/usr/bin/env bats
# Unit tests for the small helper functions: errorCheck, checkVars, echo*.

load test_helper

setup() {
  load_exporter
  TMP="$(mktemp -d)"
  log="$TMP/exporter.log"
}

teardown() {
  rm -rf "$TMP"
}

@test "errorCheck exits with the captured status on failure" {
  run errorCheck 3 "boom"
  [ "$status" -eq 3 ]
  [[ "$output" == *"boom"* ]]
}

@test "errorCheck is a no-op on success" {
  run errorCheck 0 "should not abort"
  [ "$status" -eq 0 ]
}

@test "checkVars aborts (exit 2) on an empty value" {
  run checkVars "" "unimus_api_key"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unimus_api_key is not set"* ]]
}

@test "checkVars passes a non-empty value" {
  run checkVars "something" "unimus_api_key"
  [ "$status" -eq 0 ]
}

@test "echoYellow prefixes WARNING and writes a timestamped log line" {
  echoYellow "heads up" >/dev/null
  grep -Eq "WARNING: [0-9]{4}-[0-9]{2}-[0-9]{2} .* heads up" "$log"
}

@test "echoRed prefixes ERROR in the log" {
  echoRed "kaboom" >/dev/null
  grep -q "ERROR:.*kaboom" "$log"
}
