# Tests

Two layers:

- **Shared black-box e2e** (`test_e2e.py`, Python stdlib only) - runs the
  exporter against a mock Unimus server and diffs the produced `backups/` tree
  against a checked-in **expected** tree. This layer is **implementation-agnostic**:
  the same fixtures, mock server, and expected trees test the Bash script today and
  the PowerShell port later. This is the reusable part.
- **Bash unit tests** (`unit/bash/*.bats`, [bats]) - exercise individual shell
  functions. Per-language, not reusable; the PowerShell port gets its own Pester
  unit tests next to these.

```
tests/
  dataset.py        # SINGLE SOURCE OF TRUTH: devices, backups, file-naming contract
  mock_server.py    # mock Unimus REST API v2, driven by dataset.py
  build_expected.py   # renders expected/ from dataset.py
  expected/           # expected output trees (the cross-port contract)
  e2e_support.py    # copies impl into a temp dir, runs it, diffs the tree
  test_e2e.py       # shared e2e tests (filesystem export)
  git_support.py    # git-mode driver: fake git on PATH + trace parsing
  test_git_e2e.py   # shared git-path tests (assert the git command trace)
  fakebin/          # fake git + ssh-keyscan (log argv; shared, language-agnostic)
  unit/bash/        # bats unit tests (Bash-only) + test_helper.bash
  unit/pwsh/        # Pester unit tests (PowerShell-only)
  run.sh            # run everything locally
```

CI (`.github/workflows/ci.yml`) runs the same three stages - shellcheck, the
Python e2e suite, and bats - on every push and pull request.

## Running

```bash
tests/run.sh                                   # shellcheck + e2e + bats, with a summary
python3 -m unittest discover -s tests -v       # just the e2e layer (no extra deps)
bats tests/unit/bash/                          # just the Bash unit tests
python3 tests/build_expected.py                  # regenerate expected/ after editing dataset.py
```

Requirements: `bash`, `curl`, `jq`, `base64`, `python3` (3.8+, stdlib only).
`bats` is needed for the unit layer only; `run.sh`/CI skip it if absent.

## Testing the PowerShell port

The PowerShell port (`unimus-backup-exporter.ps1`) is verified by the **same**
shared suite - the black-box driver swaps the implementation via two env vars
(see `e2e_support.py`); nothing else changes:

```bash
EXPORTER_FILES="unimus-backup-exporter.ps1" \
EXPORTER_CMD="pwsh ./unimus-backup-exporter.ps1" \
python3 -m unittest discover -s tests -v
```

This runs every e2e and git-path test against the port and confirms it produces
**byte-identical** output (the `expected/` trees) and **identical** git command
traces. `EXPORTER_FILES` is copied into a temp run dir; `EXPORTER_CMD` is run
there with `cwd` = that dir and `TZ=UTC`. The config is written as
`unimus-backup-exporter.env` (the name both scripts read) and output is expected
under `./backups/`. The contract the port must meet:

1. read config from `unimus-backup-exporter.env` in its own directory,
2. write to `./backups/`,
3. produce the **exact** paths in `expected/` - see the file-naming contract in
   `dataset.py` (`date_str` / `rel_path`),
4. shell out to `git`/`ssh-keyscan` so the fake-git harness intercepts them.

The port's per-language unit tests are Pester, in `unit/pwsh/`:

```bash
pwsh -c 'Invoke-Pester -Path tests/unit/pwsh -CI'   # needs Pester 5
```

`tests/run.sh` runs both of the above automatically when `pwsh` is on PATH.

You can also drive the PowerShell port manually against the mock:

```bash
python3 tests/mock_server.py --port 8085      # prints the api key to use
# point the .env at http://127.0.0.1:8085, then run the port and diff ./backups vs tests/expected
```

## Adding a scenario

Edit `dataset.py` (devices / backups), then `python3 tests/build_expected.py` to
regenerate expected, and add a case in `test_e2e.py`. Because the mock server and
the expected builder both read `dataset.py`, fixtures and expectations cannot drift.

## Git-path tests

`test_git_e2e.py` runs the exporter in `export_type=git` mode with the fake
`git`/`ssh-keyscan` from `fakebin/` on PATH (wired up by `git_support.py`). Each
git invocation is recorded to a trace file and asserted - the remote URL per
protocol, that `ssh-keyscan` gets the configured address, the git identity, and
the first-run vs subsequent-run branch. No real repo or remote is touched.

Because the fakes intercept the `git` CLI, this harness is shared with the
PowerShell port - on one condition: **the port must shell out to `git`** (not a
native git library), or the PATH shim won't intercept it. The fakes are bash
scripts, so they cover the Bash exporter and `pwsh` on Linux; testing the port on
Windows would need a `.cmd`/`.ps1` shim, but the driver and assertions stay shared.

## Caveats

- **`TZ=UTC` is mandatory.** Backup filenames embed `date "+%F-%T-%Z"`; the tests
  pin `TZ=UTC` so they are deterministic. Both ports must format identically.
- **Filenames contain `:` (from `%T`).** Fine on Linux; **illegal on Windows.**
  If the PowerShell port targets Windows it will need a different time format,
  and the expected trees become OS-specific. Decide this when the port lands.
- **`devices/{id}/backups` shape verified against the Unimus API v2 wiki.** The
  endpoint returns each backup inline with a base64 `bytes` field (alongside
  `id`, `validSince`, `validUntil`, `type`), so `all` mode is correct - review
  finding #7 is resolved. Results are wrapped in a `paginator` object, which the
  script ignores; it terminates on an empty `data` array.
- **Version check hits GitHub.** `checkLatestVersion` makes a real network call
  during e2e; it is non-fatal (warn-only), so tests pass offline with some
  stderr noise. A future seam to inject/disable it would make e2e fully hermetic.
- **Expected reds on current `HEAD`.** After the upstream pull, bats is green and
  only the e2e `latest`/`all` tests fail - both for one reason: the page-break bug
  (#1) silently drops every backup past the first page. They go green when #1 is
  fixed.
```
