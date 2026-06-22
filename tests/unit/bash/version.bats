#!/usr/bin/env bats
# Unit tests for checkLatestVersion()'s comparison logic.
# `curl` is stubbed on PATH so no GitHub network call happens.

load test_helper

setup() {
  load_exporter
  TMP="$(mktemp -d)"
  log="$TMP/exporter.log"
  # Stub curl to return a fixed release tag, regardless of arguments.
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"tag_name":"v99.1.0"}'
EOF
  chmod +x "$TMP/bin/curl"
  PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "warns when the remote release is newer" {
  SCRIPT_VERSION="1.1.0"
  run checkLatestVersion
  [[ "$output" == *"older version"* ]]
}

@test "stays quiet when the local version matches the remote" {
  SCRIPT_VERSION="99.1.0"
  run checkLatestVersion
  [[ "$output" != *"older version"* ]]
}
