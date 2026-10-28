"""Real temporary-file lifecycle checks; these do not test the WoW client."""

import hashlib
import json
from pathlib import Path
import shutil
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import lab


class RestoreTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.client = self.root / "_retail_"
        self.client.mkdir()
        (self.client / "Wow.exe").write_bytes(b"not an executable")
        self.addons = self.client / "Interface" / "AddOns"
        self.addons.mkdir(parents=True)
        self.main, self.probe = (self.root / "source" / name for name in (lab.MAIN, lab.PROBE))
        for source in (self.main, self.probe):
            source.mkdir(parents=True)
            (source / (source.name + ".toc")).write_bytes(b"## Interface: 120105\r\n")
        (self.main / "Core.lua").write_bytes(b"-- new addon\n")
        (self.probe / "ClientTest.lua").write_bytes(b"-- new companion\n")
        (self.main / (lab.MAIN + ".toc")).write_bytes(b"## Interface: 120105\r\nCore.lua\r\n")
        (self.probe / (lab.PROBE + ".toc")).write_bytes(b"## Interface: 120105\r\nClientTest.lua\r\n")
        self.state = self.root / "state"
        self.settings = self.client / "WTF" / "Account" / "OWNER" / "Realm" / "Character" / "SavedVariables"
        self.settings.mkdir(parents=True)
        (self.settings / (lab.MAIN + ".lua")).write_bytes(b"OriginalSettings = {value='\xc3\xa6\xc3\xb8\xc3\xa5'}\r\n")
        (self.settings / (lab.PROBE + ".lua")).write_bytes(b"PreviousClientReport = true\n")
        closed = patch.object(lab, "wow_running", return_value=False)
        self.running = closed.start()
        self.addCleanup(closed.stop)

    def snapshot(self, folder):
        """Include unknown extensions, empty directories and link targets."""
        result = {}
        if not folder.exists():
            return result
        for path in sorted(folder.rglob("*")):
            relative = path.relative_to(folder).as_posix()
            if path.is_symlink():
                result[relative] = ("link", str(path.readlink()))
            elif path.is_dir():
                result[relative] = ("directory",)
            else:
                result[relative] = ("file", path.read_bytes())
        return result

    def originals(self, names=(lab.MAIN, lab.PROBE)):
        for name in names:
            folder = self.addons / name
            (folder / "nested" / "empty").mkdir(parents=True)
            (folder / "original.lua").write_bytes((name + "\r\n").encode())
            (folder / "nested" / "opaque.bin").write_bytes(b"\x00\xff\x01\r\n")
        return self.snapshot(self.addons)

    def install(self, state=None):
        return lab.install_addons(self.client, state or self.state, self.main, self.probe)

    def restore(self, state=None, deployment_id=None):
        return lab.restore_addons(self.client, state or self.state, deployment_id)

    def status(self, state=None, deployment_id=None):
        return lab.deployment_status(self.client, state or self.state, deployment_id)

    def store(self, manifest):
        return self.client / "WTF" / "TORClientLabBackups" / manifest["deployment_id"]

    def refused_without_writes(self, operation=None):
        before = self.snapshot(self.root)
        with self.assertRaises((OSError, ValueError, RuntimeError)):
            (operation or self.restore)()
        self.assertEqual(self.snapshot(self.root), before)

    def test_restore_preserves_original_bytes_empty_directories_and_saved_variables(self):
        original = self.originals()
        settings = self.snapshot(self.settings)
        manifest = self.install()
        installed = {name: self.snapshot(self.addons / name) for name in (lab.MAIN, lab.PROBE)}
        result = self.restore()
        self.assertEqual(result["state"], "restored")
        self.assertEqual(self.snapshot(self.addons), original)
        self.assertEqual(self.snapshot(self.settings), settings)
        for name in (lab.MAIN, lab.PROBE):
            self.assertEqual(self.snapshot(self.store(manifest) / "installed" / name), installed[name])

    def test_originally_absent_addons_are_removed_from_addons_but_retained_in_archive(self):
        unrelated = self.addons / "AnotherAddon"
        unrelated.mkdir()
        (unrelated / "Keep.me").write_bytes(b"unrelated")
        original = self.snapshot(self.addons)
        manifest = self.install()
        self.restore()
        self.assertEqual(self.snapshot(self.addons), original)
        for name in (lab.MAIN, lab.PROBE):
            self.assertTrue((self.store(manifest) / "installed" / name / (name + ".toc")).is_file())

    def test_only_the_preexisting_addon_is_restored(self):
        original = self.originals((lab.MAIN,))
        self.install()
        self.restore()
        self.assertEqual(self.snapshot(self.addons), original)

    def test_preexisting_empty_addon_folders_remain_present_after_restore(self):
        for name in (lab.MAIN, lab.PROBE):
            (self.addons / name).mkdir()
        original = self.snapshot(self.addons)
        self.install()
        self.restore()
        self.assertEqual(self.snapshot(self.addons), original)

    def test_original_bytes_matching_the_test_build_are_not_mistaken_for_a_completed_restore(self):
        self.originals((lab.PROBE,))
        shutil.copytree(self.main, self.addons / lab.MAIN)
        original = self.snapshot(self.addons)
        manifest = self.install()
        self.assertEqual(self.status()["state"], "installed")
        self.restore()
        self.assertEqual(self.snapshot(self.addons), original)
        self.assertTrue((self.store(manifest) / "installed" / lab.MAIN).is_dir())

    def test_status_is_read_only_even_when_wow_is_running_or_its_state_is_unknown(self):
        self.originals()
        self.install()
        before = self.snapshot(self.root)
        self.running.side_effect = RuntimeError("process query unavailable")
        with patch.object(Path, "write_text", side_effect=AssertionError("Status wrote a file")), \
                patch.object(Path, "write_bytes", side_effect=AssertionError("Status wrote a file")), \
                patch.object(Path, "mkdir", side_effect=AssertionError("Status created a directory")), \
                patch.object(Path, "rename", side_effect=AssertionError("Status moved a file")), \
                patch.object(Path, "replace", side_effect=AssertionError("Status replaced a file")):
            result = self.status()
        self.assertEqual(result["state"], "installed")
        self.assertEqual(self.snapshot(self.root), before)

    def test_status_without_installation_creates_no_directories(self):
        before = self.snapshot(self.root)
        self.assertEqual(self.status()["state"], "not_installed")
        self.assertEqual(self.snapshot(self.root), before)

    def test_running_wow_blocks_install_and_restore_before_writes(self):
        self.originals()
        self.running.return_value = True
        self.refused_without_writes(self.install)
        self.running.return_value = False
        self.install()
        self.running.return_value = True
        self.refused_without_writes()

    def test_unknown_process_state_blocks_install_and_restore_before_writes(self):
        self.originals()
        self.running.side_effect = RuntimeError("process query unavailable")
        self.refused_without_writes(self.install)
        self.running.side_effect = None
        self.install()
        self.running.side_effect = RuntimeError("process query unavailable")
        self.refused_without_writes()

    def test_missing_backup_blocks_both_addons_before_any_restore_move(self):
        self.originals()
        manifest = self.install()
        (self.store(manifest) / lab.PROBE).rename(self.root / "missing-backup")
        self.refused_without_writes()
        self.assertEqual(self.status()["state"], "blocked")

    def test_modified_original_backup_blocks_restore(self):
        self.originals()
        manifest = self.install()
        (self.store(manifest) / lab.MAIN / "original.lua").write_bytes(b"edited backup")
        self.refused_without_writes()

    def test_modified_installed_file_blocks_restore(self):
        self.originals()
        self.install()
        (self.addons / lab.PROBE / "ClientTest.lua").write_bytes(b"edited companion")
        self.refused_without_writes()

    def test_unknown_installed_file_is_not_deleted_or_overwritten(self):
        self.originals()
        self.install()
        (self.addons / lab.PROBE / "MyPersonalNotes.data").write_bytes(b"keep this")
        self.refused_without_writes()

    def test_unknown_empty_directory_is_not_discarded(self):
        self.originals()
        self.install()
        (self.addons / lab.MAIN / "personal-empty-folder").mkdir()
        self.refused_without_writes()

    def test_missing_installed_file_is_not_mistaken_for_an_original_absent_addon(self):
        self.install()
        (self.addons / lab.MAIN / "Core.lua").unlink()
        self.refused_without_writes()

    def test_unknown_archive_contents_are_not_overwritten(self):
        self.originals()
        manifest = self.install()
        destination = self.store(manifest) / "installed" / lab.MAIN
        destination.mkdir(parents=True)
        (destination / "personal.data").write_bytes(b"must survive")
        self.refused_without_writes()

    def test_linked_backup_is_not_followed(self):
        self.originals()
        manifest = self.install()
        backup = self.store(manifest) / lab.MAIN
        outside = self.root / "outside"
        backup.rename(outside)
        try:
            backup.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("This host cannot create test symlinks")
        self.refused_without_writes()

    def test_linked_file_in_installed_addon_is_not_followed(self):
        self.install()
        file = self.addons / lab.MAIN / "Core.lua"
        file.unlink()
        try:
            file.symlink_to(self.main / "Core.lua")
        except OSError:
            self.skipTest("This host cannot create test symlinks")
        self.refused_without_writes()

    def test_windows_reparse_metadata_is_rejected_even_without_is_junction(self):
        self.originals()
        manifest = self.install()
        backup = self.store(manifest) / lab.MAIN
        original_lstat = Path.lstat

        def reparse_lstat(path, *args, **kwargs):
            result = original_lstat(path, *args, **kwargs)
            if path == backup:
                fields = {name: getattr(result, name) for name in dir(result) if name.startswith("st_")}
                fields["st_file_attributes"] = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
                return SimpleNamespace(**fields)
            return result

        before = self.snapshot(self.root)
        with patch.object(Path, "lstat", reparse_lstat):
            with self.assertRaises((OSError, ValueError, RuntimeError)):
                self.restore()
        self.assertEqual(self.snapshot(self.root), before)

    def test_manifest_for_another_client_is_refused(self):
        self.originals()
        manifest = self.install()
        record = self.store(manifest) / "deployment.json"
        data = json.loads(record.read_text())
        data["client"] = str(self.root / "another-retail-client")
        record.write_text(json.dumps(data))
        self.refused_without_writes()

    def test_malformed_manifest_is_refused_without_falling_back_to_a_pointer_copy(self):
        self.originals()
        manifest = self.install()
        (self.store(manifest) / "deployment.json").write_text("{not valid json")
        self.refused_without_writes()

    def test_nonobject_local_manifest_is_reported_as_blocked(self):
        self.originals()
        self.install()
        (self.state / "deployment.json").write_text("[]")
        self.assertEqual(self.status()["state"], "blocked")
        self.refused_without_writes()

    def test_deployment_selection_cannot_escape_the_clients_record_directory(self):
        self.originals()
        self.install()
        for value in ("../outside", "a" * 31, "/absolute", "a" * 32 + "/other"):
            with self.subTest(deployment=value):
                self.refused_without_writes(lambda: self.restore(deployment_id=value))

    def test_repeated_install_reuses_the_same_original_backup(self):
        self.originals()
        first = self.install()
        backup = {name: self.snapshot(self.store(first) / name) for name in (lab.MAIN, lab.PROBE)}
        record = (self.store(first) / "deployment.json").read_bytes()
        second = self.install()
        self.assertEqual(first["deployment_id"], second["deployment_id"])
        self.assertEqual((self.store(first) / "deployment.json").read_bytes(), record)
        for name in (lab.MAIN, lab.PROBE):
            self.assertEqual(self.snapshot(self.store(first) / name), backup[name])

    def test_changed_source_requires_restoring_the_previous_deployment(self):
        self.originals()
        self.install()
        (self.main / "Core.lua").write_bytes(b"-- different source\n")
        self.refused_without_writes(self.install)

    def test_failed_staging_write_keeps_originals_and_retains_partial_test_files(self):
        original = self.originals()
        settings = self.snapshot(self.settings)
        write_bytes = Path.write_bytes

        def interrupted_write(path, data):
            if "staged" in path.parts and path.name == "Core.lua":
                write_bytes(path, b"partial test source")
                raise OSError("injected write failure")
            return write_bytes(path, data)

        with patch.object(Path, "write_bytes", interrupted_write):
            with self.assertRaises((OSError, ValueError, RuntimeError)):
                self.install()
        self.assertEqual(self.snapshot(self.addons), original)
        self.assertEqual(self.snapshot(self.settings), settings)
        retained = list((self.client / "WTF" / "TORClientLabBackups").glob("*/staged/*/Core.lua"))
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].read_bytes(), b"partial test source")
        # A fully rolled-back installation must not strand the next install.
        self.install()
        self.restore()
        self.assertEqual(self.snapshot(self.addons), original)

    def test_newly_extracted_lab_finds_the_existing_client_deployment(self):
        original = self.originals()
        first = self.install()
        fresh_state = self.root / "another-extraction" / "state"
        self.assertEqual(self.status(fresh_state)["deployment_id"], first["deployment_id"])
        second = self.install(fresh_state)
        self.assertEqual(second["deployment_id"], first["deployment_id"])
        self.assertEqual(self.restore(fresh_state)["state"], "restored")
        self.assertEqual(self.snapshot(self.addons), original)

    def test_later_install_keeps_old_manifest_and_cannot_be_restored_by_old_id(self):
        original = self.originals()
        first = self.install()
        old_record = (self.store(first) / "deployment.json").read_bytes()
        self.restore()
        (self.main / "Core.lua").write_bytes(b"-- next source\n")
        second = self.install()
        self.assertNotEqual(first["deployment_id"], second["deployment_id"])
        self.assertEqual((self.store(first) / "deployment.json").read_bytes(), old_record)
        self.refused_without_writes(lambda: self.restore(deployment_id=first["deployment_id"]))
        self.restore(deployment_id=second["deployment_id"])
        self.assertEqual(self.snapshot(self.addons), original)

    def test_legacy_manifest_never_invents_integrity_for_an_unhashed_backup(self):
        self.originals()
        self.state.mkdir()
        deployment_id = "a" * 32
        backup = self.client / "WTF" / "TORClientLabBackups" / deployment_id
        backup.mkdir(parents=True)
        for source in (self.main, self.probe):
            target = self.addons / source.name
            target.rename(backup / source.name)
            shutil.copytree(source, target)
        files = {path.relative_to(self.addons).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in self.addons.rglob("*") if path.is_file()}
        legacy = {"schema": 1, "deployment_id": deployment_id, "client": str(self.client),
                  "source_sha256": "b" * 64, "backup": str(backup), "files": files}
        (self.state / "deployment.json").write_text(json.dumps(legacy))
        self.assertEqual(self.status()["state"], "legacy")
        self.refused_without_writes()

    def test_restore_resumes_before_and_after_each_folder_rename(self):
        original = self.originals()
        settings = self.snapshot(self.settings)
        original_rename = Path.rename
        for when in ("before", "after"):
            for stop_at in range(1, 5):
                with self.subTest(when=when, move=stop_at):
                    self.install()
                    calls = 0

                    def interrupted(path, destination):
                        nonlocal calls
                        calls += 1
                        if calls == stop_at and when == "before":
                            raise SystemExit("simulated process interruption")
                        result = original_rename(path, destination)
                        if calls == stop_at and when == "after":
                            raise SystemExit("simulated process interruption")
                        return result

                    with patch.object(Path, "rename", interrupted):
                        with self.assertRaises(SystemExit):
                            self.restore()
                    self.assertEqual(self.restore()["state"], "restored")
                    self.assertEqual(self.snapshot(self.addons), original)
                    self.assertEqual(self.snapshot(self.settings), settings)

    def test_changed_files_after_an_interruption_block_resume_without_losing_originals(self):
        self.originals()
        manifest = self.install()
        original_rename = Path.rename

        def interrupted(path, destination):
            result = original_rename(path, destination)
            raise SystemExit("simulated process interruption")

        with patch.object(Path, "rename", interrupted):
            with self.assertRaises(SystemExit):
                self.restore()
        archived = self.store(manifest) / "installed" / lab.MAIN
        (archived / "added-later.txt").write_text("keep this")
        self.refused_without_writes()
        self.assertTrue((self.store(manifest) / lab.MAIN / "original.lua").is_file())

    def test_interrupted_restore_without_original_addons_resumes_to_their_absence(self):
        original = self.snapshot(self.addons)
        manifest = self.install()
        original_rename = Path.rename

        def interrupted(path, destination):
            original_rename(path, destination)
            raise SystemExit("simulated process interruption")

        with patch.object(Path, "rename", interrupted):
            with self.assertRaises(SystemExit):
                self.restore()
        self.assertEqual(self.restore()["state"], "restored")
        self.assertEqual(self.snapshot(self.addons), original)
        for name in (lab.MAIN, lab.PROBE):
            self.assertTrue((self.store(manifest) / "installed" / name).is_dir())

    def test_repeat_restore_is_a_noop_and_never_replaces_later_user_edits(self):
        self.originals()
        self.install()
        self.restore()
        before = self.snapshot(self.root)
        result = self.restore()
        self.assertEqual(result["state"], "restored")
        self.assertTrue(result["already_restored"])
        self.assertEqual(self.snapshot(self.root), before)
        (self.addons / lab.MAIN / "original.lua").write_bytes(b"user edits after restoration")
        before = self.snapshot(self.root)
        result = self.restore()
        self.assertTrue(result["already_restored"])
        self.assertEqual(self.snapshot(self.root), before)


if __name__ == "__main__":
    unittest.main()
