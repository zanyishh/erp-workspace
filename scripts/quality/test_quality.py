"""Runner safety checks. Authored during preparation; not executed yet."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("quality", Path(__file__).with_name("quality.py"))
quality = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quality)


class PreparationSafetyTests(unittest.TestCase):
    def test_environment_ignores_caller_targets_and_cloud_tokens(self):
        inherited = {"ERP_URL": "https://customer.example", "FRAPPE_SITE": "customer",
                     "HTTPS_PROXY": "http://proxy.example", "SEMGREP_APP_TOKEN": "test-token",
                     "BC_API_KEY": "test-token"}
        with patch.dict(quality.os.environ, inherited):
            env = quality.environment()
        self.assertFalse(set(inherited) & set(env))
        self.assertEqual(env["NATIVE_TEST_SITE"], "native-test.localhost")
        self.assertEqual(env["NO_PROXY"], "*")

    def test_storage_guard_checks_backing_drive_space(self):
        mount = Path("/tmp/quality-image").resolve()
        storage = {"mountpoint": str(mount), "volume_uuid": "test-volume",
                   "disk_image": "/Volumes/infact/example.sparsebundle"}
        with patch.object(quality, "STORAGE", storage), \
                patch.object(quality, "TOOL_HOME", mount / "tools"), \
                patch.object(quality.os.path, "ismount", return_value=True), \
                patch.object(quality.subprocess, "check_output", return_value=quality.plistlib.dumps({"VolumeUUID": "test-volume"})), \
                patch.object(quality.shutil, "disk_usage", side_effect=[SimpleNamespace(free=8 * 1024**3), SimpleNamespace(free=1024**3)]):
            with self.assertRaisesRegex(RuntimeError, "external drive"):
                quality.require_space(2)

    def test_snapshot_never_replaces_an_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)
            (report / "source").mkdir()
            existing = report / "source/keep.txt"
            existing.write_text("user data")
            with self.assertRaises(FileExistsError):
                quality.source_snapshot(report)
            self.assertEqual(existing.read_text(), "user data")

    def test_run_requires_explicit_execution(self):
        with patch.object(subprocess, "run", side_effect=AssertionError("must not execute")):
            self.assertEqual(quality.main(["run", "unit"]), 0)

    def test_checkov_install_builds_reviewed_wheel_and_syncs_its_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(quality, "TOOL_HOME", home), \
                    patch.object(quality, "require_space"), \
                    patch.object(quality, "run_command", return_value=0) as execute:
                self.assertEqual(quality.install("checkov"), 0)
            commands = [call.args[0] for call in execute.call_args_list]
        build = next((i for i, cmd in enumerate(commands)
                      if any(str(item).endswith("patch_checkov.py") for item in cmd)), None)
        self.assertIsNotNone(build, "The security derivative must be built before dependency resolution")
        sync = next(i for i, cmd in enumerate(commands) if "pip" in cmd)
        self.assertLess(build, sync)
        self.assertIn("sync", commands[sync])
        self.assertNotIn("-r", commands[sync], "uv pip sync takes the lockfile as a positional argument")
        self.assertIn("--find-links", commands[sync])
        self.assertIn(str(home / "wheels"), commands[sync])
        self.assertIn(str(quality.CONFIG / "requirements-checkov.lock.txt"), commands[sync])
        self.assertIn(str(quality.ROOT / "scripts/quality/check_checkov_patch.py"), commands[-1])

    def test_unknown_group_is_rejected(self):
        with self.assertRaises(SystemExit):
            quality.main(["run", "customer"])

    def test_no_customer_or_baseline_target_in_dynamic_commands(self):
        for group in ("backend", "web", "api", "load"):
            commands = quality.commands(group, Path("/tmp/quality-report"))
            rendered = repr(commands)
            self.assertNotIn("8080", rendered)
            self.assertNotIn("8082", rendered)
            self.assertNotIn("customer-migration", rendered)
        self.assertIn("native-test.localhost", repr(quality.commands("backend", Path("/tmp/q"))))

    def test_default_flutter_tests_exclude_pilots(self):
        report = Path("/tmp/q")
        jobs = quality.commands("flutter", report)
        rendered = repr(jobs)
        self.assertIn("test/", rendered)
        self.assertNotIn("pilot_", rendered)
        self.assertIn("--coverage-path", jobs[2][0])
        self.assertIn(str(report / "lcov.info"), jobs[2][0])

    def test_flutter_resolves_locked_dependencies_before_using_the_selected_sdk(self):
        jobs = quality.commands("flutter", Path("/tmp/q"))
        self.assertEqual(jobs[0][0][2:],
                         ["--suppress-analytics", "pub", "get", "--enforce-lockfile"])
        self.assertIn("analyze", jobs[1][0])
        self.assertIn("test", jobs[2][0])

    def test_failed_flutter_resolution_blocks_dependent_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(quality, "TOOL_HOME", home), \
                    patch.object(quality, "require_space"), \
                    patch.object(quality, "run_command", return_value=1) as execute:
                self.assertEqual(quality.main(["run", "flutter", "--execute"]), 1)
            self.assertEqual(execute.call_count, 1)
            results = json.loads(next((home / "reports").glob("*/results.json")).read_text())
            self.assertEqual([item["status"] for item in results],
                             ["failed", "blocked", "blocked"])

    def test_flutter_jobs_require_the_project_toolchain_selector(self):
        for command, _ in quality.commands("flutter", Path("/tmp/q")):
            self.assertEqual(command[:2], [quality.sys.executable,
                str(quality.ROOT / "scripts/flutter_toolchain.py")])

    def test_mobile_install_uses_the_pinned_bundled_dart(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(quality, "TOOL_HOME", Path(directory)), \
                    patch.object(quality, "require_space"), \
                    patch.object(quality, "run_command", return_value=0) as execute:
                self.assertEqual(quality.install("mobile"), 0)
            for call in execute.call_args_list:
                self.assertEqual(call.args[0][:3], [quality.sys.executable,
                    str(quality.ROOT / "scripts/flutter_toolchain.py"), "--dart"])

    def test_unit_group_includes_android_release_security_policy(self):
        commands = quality.commands("unit", Path("/tmp/q"))
        self.assertTrue(any(str(quality.ROOT / "apps/erp_client/android/test_security_config.py") in command
                            for command, _ in commands))
        self.assertTrue(any('infrastructure/erpnext/security' in command for command, _ in commands))

    def test_license_inventory_is_scoped_and_has_no_update_check(self):
        report = Path("/tmp/example-quality-report")
        command, _ = quality.commands("licenses", report)[0]
        self.assertIn("--no-check-version", command)
        self.assertEqual(command[-1], str(report / "source"))
        self.assertNotIn("--package-in-compiled", command)

    def test_independent_jobs_continue_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(quality, "TOOL_HOME", home), \
                    patch.object(quality, "require_space"), \
                    patch.object(quality, "run_command", side_effect=[1, 0, 0, 0, 0]) as execute:
                self.assertEqual(quality.main(["run", "unit", "--execute"]), 1)
            self.assertEqual(execute.call_count, 5)
            results = json.loads(next((home / "reports").glob("*/results.json")).read_text())
            self.assertEqual([item["status"] for item in results], ["failed", "passed", "passed", "passed", "passed"])

    def test_browser_uses_current_sources_and_unique_report_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / "node").mkdir()
            (home / "node/web.spec.cjs").write_text("stale content")
            with patch.object(quality, "TOOL_HOME", home), \
                    patch.object(quality, "require_space"), \
                    patch.object(quality, "run_command", return_value=0) as execute:
                self.assertEqual(quality.main(["run", "web", "--execute"]), 0)
            self.assertEqual((home / "node/web.spec.cjs").read_text(),
                             (quality.CONFIG / "web.spec.cjs").read_text())
            report = Path(execute.call_args.args[3]["ERP_QUALITY_REPORT_DIR"])
            self.assertEqual(report.parent, home / "reports")


if __name__ == "__main__":
    unittest.main()
