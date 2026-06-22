"""Black-box driver shared by every exporter implementation.

The only things that change between the Bash script and the PowerShell
version are two environment variables:

    EXPORTER_FILES  space-separated files to copy into the temp run dir
                    (default: the Bash script)
    EXPORTER_CMD    command to run inside that dir
                    (default: ./unimus-backup-exporter.sh)

Everything else -- the mock server, the dataset, the expected trees, the temp
.env, the tree comparison -- is reused unchanged. To test the PowerShell version:

    EXPORTER_FILES="unimus-backup-exporter.ps1" \
    EXPORTER_CMD="pwsh ./unimus-backup-exporter.ps1" \
    python3 -m unittest discover -s tests
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import dataset

REPO_ROOT = Path(__file__).resolve().parent.parent
EXPECTED = Path(__file__).resolve().parent / "expected"

ENV_NAME = "unimus-backup-exporter.env"  # the script sources this literal name

DEFAULT_FILES = "unimus-backup-exporter.sh"
DEFAULT_CMD = "./unimus-backup-exporter.sh"


def _env_file(server_url, backup_type, api_key, export_type="fs", extra=None):
    lines = [
        f'unimus_server_address="{server_url}"',
        f'unimus_api_key="{api_key}"',
        f'backup_type="{backup_type}"',
        f'export_type="{export_type}"',
    ]
    for key, value in (extra or {}).items():
        lines.append(f'{key}="{value}"')
    return "\n".join(lines) + "\n"


def run_exporter(workdir, server_url, backup_type, api_key=None,
                 export_type="fs", config_extra=None, env_extra=None):
    """Copy the implementation into `workdir`, run it against `server_url`,
    return (CompletedProcess, Path-to-produced-backups-dir).

    TZ=UTC makes the timestamped filenames deterministic and matches the expected
    trees built by build_expected.py. `config_extra` adds keys to the generated
    .env (e.g. the git_* vars); `env_extra` overrides subprocess environment
    variables (e.g. PATH/HOME for the fake-git harness).
    """
    workdir = Path(workdir)
    for rel in shlex.split(os.environ.get("EXPORTER_FILES", DEFAULT_FILES)):
        src = REPO_ROOT / rel
        shutil.copy(src, workdir / Path(rel).name)
        (workdir / Path(rel).name).chmod(0o755)

    if api_key is None:
        api_key = dataset.API_KEY
    (workdir / ENV_NAME).write_text(
        _env_file(server_url, backup_type, api_key, export_type, config_extra))

    cmd = shlex.split(os.environ.get("EXPORTER_CMD", DEFAULT_CMD))
    env = dict(os.environ, TZ="UTC")
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run(
        cmd, cwd=workdir, env=env,
        capture_output=True, text=True, timeout=120,
    )
    return proc, workdir / "backups"


def diff_tree(produced, expected):
    """Return a list of human-readable differences; empty list == identical."""
    produced, expected = Path(produced), Path(expected)

    def rel_files(root):
        if not root.exists():
            return {}
        return {
            str(p.relative_to(root)): p.read_bytes()
            for p in root.rglob("*") if p.is_file()
        }

    want, got = rel_files(expected), rel_files(produced)
    problems = []
    for rel in sorted(set(want) - set(got)):
        problems.append(f"MISSING:   {rel}")
    for rel in sorted(set(got) - set(want)):
        problems.append(f"UNEXPECTED:{rel}")
    for rel in sorted(set(want) & set(got)):
        if want[rel] != got[rel]:
            problems.append(f"DIFFERS:   {rel}")
    return problems
