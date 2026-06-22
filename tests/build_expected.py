"""Materialize the expected output trees from `dataset.py`.

The expected trees are the cross-implementation contract: whatever the exporter
is (Bash now, PowerShell later), an `fs` export against the mock server must
produce exactly these files (same paths, same bytes). Regenerate after editing
the dataset:

    python3 tests/build_expected.py

Output:
    tests/expected/latest_fs/<address> - <id>/Backup ...   (newest backup per device)
    tests/expected/all_fs/<address> - <id>/Backup ...       (every backup)
"""

import shutil
from pathlib import Path

import dataset

EXPECTED = Path(__file__).resolve().parent / "expected"


def _write(root, pairs):
    if root.exists():
        shutil.rmtree(root)
    for device_id, backup in pairs:
        folder, name = dataset.rel_path(device_id, backup)
        d = root / folder
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_bytes(backup["content"])


def main():
    _write(EXPECTED / "latest_fs", dataset.latest_per_device())
    _write(EXPECTED / "all_fs", dataset.all_backups())
    print(f"wrote expected trees under {EXPECTED}")


if __name__ == "__main__":
    main()
