"""Materialize the expected output trees from `dataset.py`.

The expected trees are the cross-implementation contract: an `fs` export against
the mock server must produce exactly these files. There are two parallel trees
because the implementations format the filename timestamp differently:

    expected/        Bash version       (local time, ':' in the time -> 00:00:00)
    expected_pwsh/   PowerShell version (UTC, ':'-free for Windows -> 00-00-00)

Each holds the same scenario subdirs (latest_fs/, all_fs/). Regenerate after
editing the dataset:

    python3 tests/build_expected.py
"""

import shutil
from pathlib import Path

import dataset

ROOT = Path(__file__).resolve().parent


def _write(root, pairs, date_fmt):
    if root.exists():
        shutil.rmtree(root)
    for device_id, backup in pairs:
        folder, name = dataset.rel_path(device_id, backup, date_fmt)
        d = root / folder
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_bytes(backup["content"])


def main():
    for sub, date_fmt in (("expected", dataset.date_str),
                          ("expected_pwsh", dataset.date_str_pwsh)):
        _write(ROOT / sub / "latest_fs", dataset.latest_per_device(), date_fmt)
        _write(ROOT / sub / "all_fs", dataset.all_backups(), date_fmt)
        print(f"wrote {sub}/ trees under {ROOT / sub}")


if __name__ == "__main__":
    main()
