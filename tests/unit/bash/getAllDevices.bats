#!/usr/bin/env bats
# Unit tests for getAllDevices() naming (issue #11): folders are named by a
# configurable device field, defaulting to the address.

load test_helper

setup() {
  load_exporter
  TMP="$(mktemp -d)"
  log="$TMP/exporter.log"
}

teardown() {
  rm -rf "$TMP"
}

# Stub unimusGet: page 0 returns two devices, any later page is empty.
# Device 2 has an empty description to exercise the address fallback.
_stub_unimus() {
  unimusGet() {
    case "$1" in
      *page=0)
        echo '{"data":[{"id":1,"address":"10.0.0.1","description":"router1"},{"id":2,"address":"10.0.0.2","description":""}]}' ;;
      *)
        echo '{"data":[]}' ;;
    esac
  }
}

@test "defaults to naming by address" {
  _stub_unimus
  unset device_name_field
  declare -gA devices=()
  getAllDevices >/dev/null
  [ "${devices[1]}" = "10.0.0.1" ]
  [ "${devices[2]}" = "10.0.0.2" ]
}

@test "names by a custom field, falling back to address when empty (issue #11)" {
  _stub_unimus
  device_name_field='description'
  declare -gA devices=()
  getAllDevices >/dev/null
  [ "${devices[1]}" = "router1" ]     # description used
  [ "${devices[2]}" = "10.0.0.2" ]    # empty description -> address fallback
}
