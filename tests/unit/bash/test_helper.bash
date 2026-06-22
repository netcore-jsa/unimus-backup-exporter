# Shared bats helpers for the Bash unit layer.

# Absolute path to the repo root, from this file's location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Source the exporter's functions WITHOUT running main().
#
# The script ends with a bare `main` call, so we strip that one line before
# sourcing. Once the script gains an `if [[ "${BASH_SOURCE[0]}" == "${0}" ]];
# then main; fi` guard, replace this with a plain `source`.
load_exporter() {
  source <(sed '/^main$/d' "$REPO_ROOT/unimus-backup-exporter.sh")
}
