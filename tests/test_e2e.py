"""End-to-end black-box tests: run the exporter against the mock Unimus server
and assert the produced backups/ tree matches the expected tree.

Shared across implementations -- see e2e_support.py for the EXPORTER_CMD knob.

Run:  python3 -m unittest discover -s tests
"""

import tempfile
import unittest
from pathlib import Path

import dataset
from mock_server import make_server
from e2e_support import run_exporter, diff_tree, EXPECTED
import threading


class ExporterE2E(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd, port = make_server(0)
        cls.url = f"http://127.0.0.1:{port}"
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def _run(self, backup_type, expected_name):
        with tempfile.TemporaryDirectory() as tmp:
            proc, produced = run_exporter(tmp, self.url, backup_type)
            self.assertEqual(
                proc.returncode, 0,
                msg=f"exporter exited {proc.returncode}\nSTDERR:\n{proc.stderr}",
            )
            problems = diff_tree(produced, EXPECTED / expected_name)
            self.assertEqual(
                problems, [],
                msg="output tree != expected:\n  " + "\n  ".join(problems)
                    + f"\n\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}",
            )

    def test_latest_fs(self):
        """`backup_type=latest` exports the newest backup of every device,
        across multiple pages of the latest-backups endpoint."""
        self._run("latest", "latest_fs")

    def test_all_fs(self):
        """`backup_type=all` exports every backup of every device, including a
        device whose history spans multiple pages and a BINARY backup."""
        self._run("all", "all_fs")

    def test_bad_api_key_writes_nothing(self):
        """A wrong API key must not produce backup files (the mock returns 401,
        so the status check never reports OK)."""
        with tempfile.TemporaryDirectory() as tmp:
            proc, produced = run_exporter(tmp, self.url, "latest", api_key=dataset.API_KEY + "-wrong")
            files = [p for p in Path(produced).rglob("*") if p.is_file()] if Path(produced).exists() else []
            self.assertEqual(files, [], msg=f"unexpected files written: {files}\nSTDERR:\n{proc.stderr}")


if __name__ == "__main__":
    unittest.main()
