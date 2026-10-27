"""CLI routing and process-query checks, without a Windows or WoW session."""
import contextlib
import io
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

import lab


class CommandTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.client = self.root / "_retail_"
        self.client.mkdir()
        (self.client / "Wow.exe").write_bytes(b"fixture")
        self.output = io.StringIO()

    def test_status_neither_starts_the_bridge_nor_queries_processes(self):
        with patch.object(lab, "HERE", self.root), \
                patch.object(lab, "wow_running", side_effect=AssertionError("Must stay read-only")), \
                patch.object(lab, "ThreadingHTTPServer", side_effect=AssertionError("Must not start a server")), \
                contextlib.redirect_stdout(self.output):
            self.assertEqual(lab.main(["--status", "--wow-path", str(self.client)]), 0)
        self.assertIn("No test installation found", self.output.getvalue())
        self.assertFalse((self.root / "state").exists())
        self.assertFalse((self.client / "WTF").exists())

    def test_restore_selects_the_requested_deployment_and_exits_without_a_browser(self):
        result = {"state": "restored", "errors": [], "deployment_id": "a" * 32}
        with patch.object(lab, "os", SimpleNamespace(name="nt")), \
                patch.object(lab, "HERE", self.root), \
                patch.object(lab, "restore_addons", return_value=result) as restore, \
                patch.object(lab, "ThreadingHTTPServer", side_effect=AssertionError("Must not start a server")), \
                patch.object(lab.webbrowser, "open", side_effect=AssertionError("Must not open a browser")), \
                contextlib.redirect_stdout(self.output):
            self.assertEqual(lab.main(["--restore", "--wow-path", str(self.client),
                                       "--deployment", "a" * 32]), 0)
        restore.assert_called_once_with(self.client, self.root / "state", "a" * 32)
        self.assertIn("Original addon folders restored", self.output.getvalue())

    def test_historical_restore_does_not_claim_current_file_integrity(self):
        with contextlib.redirect_stdout(self.output):
            lab.print_deployment_status({"state": "restored", "already_restored": True, "errors": []})
        self.assertIn("already restored", self.output.getvalue())
        self.assertIn("left as they are", self.output.getvalue())
        self.assertNotIn("Original addon folders restored.", self.output.getvalue())

    def test_process_list_includes_minimized_retail_and_ptr_clients(self):
        for name in ("Wow.exe", "WowT.exe", "WOW.EXE"):
            with self.subTest(name=name), patch.object(lab.subprocess, "run", return_value=
                    SimpleNamespace(stdout=f'"System","4","Services","0","100 K"\n"{name}","42","Console","1","200 K"\n')):
                self.assertTrue(lab.wow_running())
        with patch.object(lab.subprocess, "run", return_value=SimpleNamespace(stdout='"System","4","Services","0","100 K"\n')):
            self.assertFalse(lab.wow_running())

    def test_empty_or_malformed_process_output_is_not_treated_as_a_closed_game(self):
        for output in ("", "unexpected output", '"Wow.exe","not a pid"'):
            with self.subTest(output=output), patch.object(lab.subprocess, "run", return_value=SimpleNamespace(stdout=output)):
                with self.assertRaises(RuntimeError):
                    lab.wow_running()
        with patch.object(lab.subprocess, "run", side_effect=OSError("unavailable")):
            with self.assertRaises(RuntimeError):
                lab.wow_running()
