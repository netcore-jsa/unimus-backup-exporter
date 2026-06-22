"""Shared git-path tests.

Run the exporter in `export_type=git` mode against the mock Unimus server, with a
fake `git`/`ssh-keyscan` on PATH that records every invocation. Assertions are
made on that command trace, so no real repo or remote is needed -- and because
the fakes intercept the `git` CLI, the same harness will test the PowerShell port
(which must shell out to `git`).

Run:  python3 -m unittest discover -s tests
"""

import tempfile
import threading
import unittest

from mock_server import make_server
from e2e_support import diff_tree, EXPECTED
from git_support import run_git_export, find


class GitPathE2E(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd, port = make_server(0)
        cls.url = f"http://127.0.0.1:{port}"
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    # --- regression / branch coverage (expected green) ---

    def test_git_mode_still_writes_the_backup_tree(self):
        """git mode performs the fs export before pushing."""
        with tempfile.TemporaryDirectory() as tmp:
            proc, backups, _ = run_git_export(tmp, self.url, "latest", protocol="https")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(diff_tree(backups, EXPECTED / "latest_fs"), [])

    def test_https_remote_url_includes_port(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="https")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn(
                ["git", "remote", "add", "origin",
                 "https://alice:s3cret@192.168.4.5:2222/alice/backups"], tr)

    def test_ssh_remote_url_with_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="ssh")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn(
                ["git", "remote", "add", "origin",
                 "ssh://alice:s3cret@192.168.4.5/alice/backups"], tr)

    def test_ssh_remote_url_without_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="ssh",
                                         config_overrides={"git_password": ""})
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn(
                ["git", "remote", "add", "origin",
                 "ssh://alice@192.168.4.5/alice/backups"], tr)

    def test_invalid_protocol_aborts(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="ftp")
            self.assertEqual(proc.returncode, 2)
            self.assertEqual(find(tr, "git", "remote", "add"), [])

    def test_subsequent_run_uses_add_all_not_init(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="https", in_worktree=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn(["git", "add", "--all"], tr)
            self.assertEqual(find(tr, "git", "init"), [])
            self.assertEqual(find(tr, "git", "remote", "add"), [])

    # --- open review bugs (RED until fixed) ---

    def test_ssh_keyscan_scans_configured_address(self):  # bug #4
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="ssh")
            self.assertIn(["ssh-keyscan", "-H", "192.168.4.5"], tr,
                          msg=f"ssh-keyscan scanned the wrong host; trace={tr}")

    def test_git_identity_is_configured(self):  # bug #5
        with tempfile.TemporaryDirectory() as tmp:
            proc, _, tr = run_git_export(tmp, self.url, protocol="https")
            self.assertIn(["git", "config", "user.email", "alice@example.org"], tr,
                          msg=f"git identity (git_email) never applied; trace={tr}")


if __name__ == "__main__":
    unittest.main()
