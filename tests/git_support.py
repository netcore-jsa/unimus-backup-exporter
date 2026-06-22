"""Driver for the shared git-path tests.

Runs the exporter in `export_type=git` mode with the fake `git`/`ssh-keyscan`
from tests/fakebin on PATH, so every git interaction is recorded to a trace file
instead of touching a real repo or remote. Reuses run_exporter() from
e2e_support, so the same EXPORTER_FILES/EXPORTER_CMD knob applies -- this harness
is shared across implementations (the Bash script and the PowerShell version,
provided each shells out to the `git` CLI).
"""

import os
from pathlib import Path

from e2e_support import run_exporter

FAKEBIN = Path(__file__).resolve().parent / "fakebin"

# Baseline git config written into the .env. Tests override per case.
GIT_CONFIG = {
    "git_username": "alice",
    "git_password": "s3cret",
    "git_email": "alice@example.org",
    "git_server_protocol": "https",
    "git_server_address": "192.168.4.5",
    "git_port": "2222",
    "git_repo_name": "alice/backups",
    "git_branch": "main",
}


def run_git_export(workdir, server_url, backup_type="latest", *, protocol="https",
                   in_worktree=False, config_overrides=None):
    """Run the exporter in git mode against the fake git.

    Returns (CompletedProcess, backups_dir, trace) where trace is a list of
    records, each a list of argv tokens, e.g. ["git", "remote", "add", "origin",
    "https://..."].
    """
    workdir = Path(workdir)
    home = workdir / "home"
    (home / ".ssh").mkdir(parents=True)          # ssh-keyscan >> ~/.ssh/known_hosts
    trace = workdir / "git-trace.tsv"

    cfg = dict(GIT_CONFIG, git_server_protocol=protocol)
    if config_overrides:
        cfg.update(config_overrides)

    env_extra = {
        "PATH": f"{FAKEBIN}{os.pathsep}{os.environ['PATH']}",
        "HOME": str(home),
        "FAKEGIT_TRACE": str(trace),
    }
    if in_worktree:
        env_extra["FAKEGIT_WORKTREE"] = "1"

    proc, backups = run_exporter(
        workdir, server_url, backup_type,
        export_type="git", config_extra=cfg, env_extra=env_extra,
    )
    return proc, backups, parse_trace(trace)


def parse_trace(path):
    path = Path(path)
    if not path.exists():
        return []
    return [line.split("\t") for line in path.read_text().splitlines() if line]


def find(records, *prefix):
    """Records whose leading tokens equal `prefix`."""
    n = len(prefix)
    return [r for r in records if r[:n] == list(prefix)]
