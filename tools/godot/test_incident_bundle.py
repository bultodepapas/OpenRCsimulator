from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
from unittest import mock

import incident_bundle
from incident_bundle import SnapshotFailure, create_bundle, main
from run_checked import run_checked

from research.performance.test_native_summary import valid_report


class IncidentBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc incident bundle ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runs = self.root / "runs"
        self.runs.mkdir()

    def make_run(self, code: str = "print('checked run')") -> tuple[Path, dict]:
        checked = run_checked([sys.executable, "-c", code], self.runs, timeout=5)
        return Path(checked["report"]).parent, checked

    @staticmethod
    def read_receipt(run_dir: Path) -> dict:
        return json.loads((run_dir / "report.json").read_text(encoding="utf-8"))

    @staticmethod
    def write_receipt(run_dir: Path, report: dict) -> None:
        (run_dir / "report.json").write_text(json.dumps(report, ensure_ascii=True) + "\n", encoding="utf-8")

    def add_resource_report(self, run_dir: Path, *, changed_invocation: bool = False) -> bytes:
        report = self.read_receipt(run_dir)
        capture_id = report["capture_id"]
        invocation = {
            "capture_id": capture_id,
            "command": report["command"],
            "cwd": report["cwd"] + ("-different" if changed_invocation else ""),
            "started_utc": report["started_utc"],
            "log_sha256": report["log_sha256"],
        }
        resource = {
            "format": "openrc-resource-samples v1",
            "capture_id": capture_id,
            "invocation": invocation,
            "coverage": "sampled",
            "measurement_status": "ok",
            "sample_count": 1,
            "samples": [{"rss_bytes": 1234}],
        }
        content = (json.dumps(resource, ensure_ascii=True) + "\n").encode("utf-8")
        (run_dir / "resources.json").write_bytes(content)
        report["resources"] = {
            "file": "resources.json",
            "published": True,
            "coverage": "sampled",
            "bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
            "sample_count": 1,
            "measurement_status": "ok",
        }
        self.write_receipt(run_dir, report)
        return content

    def make_frames(self, path: Path, capture_id: str) -> Path:
        report = valid_report()
        report["capture_id"] = capture_id
        path.write_text(json.dumps(report, ensure_ascii=True) + "\n", encoding="utf-8")
        return path

    @staticmethod
    def unzip_manifest(path: Path) -> tuple[dict, zipfile.ZipFile]:
        archive = zipfile.ZipFile(path)
        return json.loads(archive.read("manifest.json")), archive

    def invoke(self, run_dir: Path, output: Path, *arguments: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main([str(run_dir), "--out", str(output), *arguments])
        return code, stdout.getvalue(), stderr.getvalue()

    def test_success_attaches_valid_receipts_frames_and_opaque_flight_log(self):
        run_dir, checked = self.make_run()
        resource_bytes = self.add_resource_report(run_dir)
        frames = self.make_frames(self.root / "frames.json", checked["capture_id"])
        flight_log = self.root / "recording.orfl"
        flight_log.write_bytes(b"ORFL opaque fixture\x00\xff")
        output = self.root / "incident.zip"

        code, stdout, stderr = self.invoke(run_dir, output, "--frames", str(frames),
                                           "--flight-log", str(flight_log), "--note", "repro on startup")

        self.assertEqual(code, 0, stderr)
        self.assertIn("incident bundle: complete; run passed", stdout)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertEqual(archive.namelist(), ["manifest.json", "report.json", "engine.log",
                                                  "resources.json", "frames.json", "flight-log.orfl"])
            self.assertEqual(archive.read("resources.json"), resource_bytes)
            self.assertEqual(archive.read("flight-log.orfl"), flight_log.read_bytes())
        self.assertTrue(manifest["bundle_complete"])
        self.assertTrue(manifest["run_ok"])
        self.assertEqual(manifest["run"]["capture_identity"], "verified")
        self.assertEqual(manifest["source_metadata"]["note"], "repro on startup")
        by_role = {attachment["role"]: attachment for attachment in manifest["attachments"]}
        self.assertEqual(by_role["frame_report"]["validation"], "valid")
        self.assertEqual(by_role["flight_log"]["validation"], "caller_supplied_unverified")
        self.assertEqual(by_role["flight_log"]["sha256"], hashlib.sha256(flight_log.read_bytes()).hexdigest())
        self.assertFalse(manifest["claims"]["orfl_replay_validated"])

    def test_valid_failed_engine_capture_is_packaged_successfully_but_run_ok_false(self):
        run_dir, checked = self.make_run("print('SCRIPT ERROR: intentional fixture failure')")
        self.assertEqual(checked["reason"], "engine_error")
        output = self.root / "failed-run.zip"

        code, stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 0, stderr)
        self.assertIn("run failed or invalid", stdout)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("SCRIPT ERROR: intentional fixture failure", archive.read("engine.log").decode())
        self.assertTrue(manifest["bundle_complete"])
        self.assertFalse(manifest["run_ok"])
        self.assertTrue(manifest["run"]["evidence_valid"])
        self.assertEqual(manifest["run"]["reason"], "engine_error")

    def test_tampered_log_is_retained_and_marks_bundle_partial(self):
        run_dir, _checked = self.make_run()
        (run_dir / "engine.log").write_bytes(b"changed after capture\n")
        output = self.root / "tampered.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertEqual(archive.read("engine.log"), b"changed after capture\n")
        self.assertFalse(manifest["bundle_complete"])
        self.assertFalse(manifest["run_ok"])
        self.assertTrue(any(issue["code"] == "run_evidence_invalid" for issue in manifest["issues"]))

    def test_resource_hash_and_invocation_mismatch_are_reported(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        resource_path = run_dir / "resources.json"
        resource = json.loads(resource_path.read_text(encoding="utf-8"))
        resource["invocation"]["cwd"] = "/wrong/cwd"
        resource_path.write_text(json.dumps(resource) + "\n", encoding="utf-8")
        output = self.root / "bad-resource.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("resources.json", archive.namelist())
        codes = {issue["code"] for issue in manifest["issues"]}
        self.assertIn("resource_hash_mismatch", codes)
        self.assertIn("resource_receipt_mismatch", codes)

    def test_receipt_cannot_direct_packager_to_an_arbitrary_resource_path(self):
        run_dir, _checked = self.make_run()
        outside = self.root / "outside.json"
        outside.write_text("secret", encoding="utf-8")
        report = self.read_receipt(run_dir)
        report["resources"] = {"file": "../outside.json", "published": True, "bytes": 6,
                               "sha256": hashlib.sha256(b"secret").hexdigest()}
        self.write_receipt(run_dir, report)
        output = self.root / "unsafe-resource.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertNotIn("resources.json", archive.namelist())
            self.assertNotIn("outside.json", archive.namelist())
        self.assertEqual(next(item for item in manifest["attachments"]
                              if item["role"] == "resource_report")["status"], "unsafe_receipt_path")

    def test_missing_log_and_invalid_frames_are_explicit_partial_attachments(self):
        run_dir, checked = self.make_run()
        (run_dir / "engine.log").unlink()
        incomplete = valid_report()
        incomplete["capture_id"] = checked["capture_id"]
        incomplete["complete"] = False
        incomplete["failure"] = "stopped before sample boundary"
        frames = self.root / "incomplete.json"
        frames.write_text(json.dumps(incomplete), encoding="utf-8")
        output = self.root / "partial.zip"

        code, _stdout, stderr = self.invoke(run_dir, output, "--frames", str(frames))

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("frames.json", archive.namelist())
        by_role = {attachment["role"]: attachment for attachment in manifest["attachments"]}
        self.assertEqual(by_role["engine_log"]["status"], "missing")
        self.assertEqual(by_role["frame_report"]["validation"], "invalid")
        self.assertFalse(manifest["bundle_complete"])
        self.assertTrue(any("incomplete" in issue["message"] for issue in manifest["issues"]))

    def test_malformed_frame_json_is_retained_and_duplicate_keys_are_rejected(self):
        run_dir, _checked = self.make_run()
        frames = self.root / "duplicate.json"
        frames.write_text('{"format":"wrong","format":"openrc-frametimes v2"}', encoding="utf-8")
        output = self.root / "malformed-frames.zip"

        code, _stdout, stderr = self.invoke(run_dir, output, "--frames", str(frames))

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertEqual(archive.read("frames.json"), frames.read_bytes())
        self.assertTrue(any(issue["code"] == "frame_json_invalid"
                            and "duplicate JSON key" in issue["message"]
                            for issue in manifest["issues"]))

    def test_duplicate_run_report_key_cannot_become_a_pass(self):
        run_dir, _checked = self.make_run()
        report_path = run_dir / "report.json"
        content = report_path.read_text(encoding="utf-8")
        self.assertIn('"ok": true', content)
        report_path.write_text(content.replace('"ok": true', '"ok": true, "ok": true', 1), encoding="utf-8")
        output = self.root / "duplicate-report.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("report.json", archive.namelist())
        self.assertFalse(manifest["run_ok"])
        self.assertFalse(manifest["run"]["evidence_valid"])
        self.assertTrue(any(issue["code"] == "report_json_invalid"
                            and "duplicate JSON key" in issue["message"]
                            for issue in manifest["issues"]))

    def test_json_recursion_failure_is_returned_as_validation_error(self):
        _value, error = incident_bundle._parse_json_object(b"[" * 2000 + b"]" * 2000)
        self.assertIsNone(_value)
        self.assertIsNotNone(error)

    def test_different_frame_capture_id_makes_bundle_partial(self):
        run_dir, checked = self.make_run()
        frames = self.make_frames(self.root / "different.json", "different-capture")
        output = self.root / "identity.zip"

        code, _stdout, stderr = self.invoke(run_dir, output, "--frames", str(frames))

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("frames.json", archive.namelist())
        self.assertNotEqual(manifest["run"]["capture_id"], "different-capture")
        self.assertEqual(manifest["run"]["capture_identity"], "mismatch_or_unverified")

    def test_legacy_run_without_capture_id_is_marked_unverified(self):
        run_dir, _checked = self.make_run()
        report = self.read_receipt(run_dir)
        report.pop("capture_id", None)
        self.write_receipt(run_dir, report)
        output = self.root / "legacy.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 0, stderr)
        manifest, archive = self.unzip_manifest(output)
        archive.close()
        self.assertEqual(manifest["run"]["capture_identity"], "unverified_legacy")
        self.assertTrue(manifest["bundle_complete"])

    def test_legacy_direct_frame_capture_with_empty_id_is_unverified_not_invalid(self):
        run_dir, _checked = self.make_run()
        report = self.read_receipt(run_dir)
        report.pop("capture_id", None)
        self.write_receipt(run_dir, report)
        frame_report = valid_report()
        frame_report["capture_id"] = ""
        frames = self.root / "legacy-frames.json"
        frames.write_text(json.dumps(frame_report), encoding="utf-8")
        output = self.root / "legacy-frames.zip"

        code, _stdout, stderr = self.invoke(run_dir, output, "--frames", str(frames))

        self.assertEqual(code, 0, stderr)
        manifest, archive = self.unzip_manifest(output)
        archive.close()
        self.assertEqual(manifest["run"]["capture_identity"], "unverified_legacy")
        self.assertEqual(next(item for item in manifest["attachments"]
                              if item["role"] == "frame_report")["validation"], "valid")

    def test_partial_or_capped_resource_measurement_makes_bundle_partial(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        report = self.read_receipt(run_dir)
        resource_path = run_dir / "resources.json"
        resource = json.loads(resource_path.read_text(encoding="utf-8"))
        resource["coverage"] = "capped"
        resource["measurement_status"] = "ok"
        resource_bytes = (json.dumps(resource) + "\n").encode("utf-8")
        resource_path.write_bytes(resource_bytes)
        report["resources"].update(bytes=len(resource_bytes),
                                   sha256=hashlib.sha256(resource_bytes).hexdigest(), coverage="capped")
        self.write_receipt(run_dir, report)
        output = self.root / "capped-resource.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        archive.close()
        entry = next(item for item in manifest["attachments"] if item["role"] == "resource_report")
        self.assertEqual(entry["validation"], "receipt_and_invocation_integrity_only")
        self.assertFalse(entry["measurement_values_validated"])
        self.assertTrue(any(issue["code"] == "resource_measurement_incomplete"
                            for issue in manifest["issues"]))

    def test_malformed_resource_metadata_is_partial_not_a_cli_crash(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        report = self.read_receipt(run_dir)
        resource_path = run_dir / "resources.json"
        resource = json.loads(resource_path.read_text(encoding="utf-8"))
        resource["coverage"] = []
        resource["measurement_status"] = {"unexpected": "object"}
        resource_bytes = (json.dumps(resource) + "\n").encode("utf-8")
        resource_path.write_bytes(resource_bytes)
        report["resources"].update(bytes=len(resource_bytes),
                                   sha256=hashlib.sha256(resource_bytes).hexdigest())
        self.write_receipt(run_dir, report)
        output = self.root / "malformed-resource-metadata.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        self.assertNotIn("Traceback", stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("resources.json", archive.namelist())
        entry = next(item for item in manifest["attachments"] if item["role"] == "resource_report")
        self.assertEqual(entry["validation"], "invalid_receipt")
        self.assertTrue(any(issue["code"] == "resource_receipt_mismatch"
                            for issue in manifest["issues"]))

    def test_resource_receipt_requires_published_boolean(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        report = self.read_receipt(run_dir)
        report["resources"].pop("published")
        self.write_receipt(run_dir, report)
        output = self.root / "resource-receipt-without-published.zip"

        code, _stdout, stderr = self.invoke(run_dir, output)

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertNotIn("resources.json", archive.namelist())
        entry = next(item for item in manifest["attachments"] if item["role"] == "resource_report")
        self.assertEqual(entry["status"], "invalid_receipt")
        self.assertTrue(any(issue["code"] == "resource_receipt_invalid"
                            for issue in manifest["issues"]))

    def test_file_and_combined_budgets_create_partial_bundle(self):
        run_dir, _checked = self.make_run()
        report_size = (run_dir / "report.json").stat().st_size
        per_file_output = self.root / "per-file-budget.zip"

        code, _stdout, stderr = self.invoke(run_dir, per_file_output, "--max-input-bytes", str(report_size - 1),
                                            "--max-total-bytes", str(report_size * 2))

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(per_file_output)
        with archive:
            self.assertNotIn("report.json", archive.namelist())
        self.assertTrue(any(issue["code"] == "file_size_limit" for issue in manifest["issues"]))

        combined_output = self.root / "combined-budget.zip"
        code, _stdout, stderr = self.invoke(run_dir, combined_output, "--max-input-bytes", str(report_size),
                                            "--max-total-bytes", str(report_size))
        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(combined_output)
        with archive:
            self.assertIn("report.json", archive.namelist())
            self.assertNotIn("engine.log", archive.namelist())
        self.assertEqual(manifest["input_budget"]["bytes_read"], report_size)
        self.assertTrue(any(issue["code"] == "total_size_limit" for issue in manifest["issues"]))
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            invalid_code = main([str(run_dir), "--out", str(self.root / "invalid-limit.zip"),
                                 "--max-input-bytes", str(incident_bundle.MAX_INPUT_BYTES + 1)])
        self.assertEqual(invalid_code, 2)

    def test_linked_explicit_flight_log_is_not_followed(self):
        run_dir, _checked = self.make_run()
        external = self.root / "external.orfl"
        external.write_bytes(b"private external flight log")
        linked = self.root / "linked.orfl"
        try:
            linked.symlink_to(external)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        output = self.root / "linked.zip"

        code, _stdout, stderr = self.invoke(run_dir, output, "--flight-log", str(linked))

        self.assertEqual(code, 1, stderr)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertNotIn("flight-log.orfl", archive.namelist())
        self.assertTrue(any(issue["code"] == "linked_source" for issue in manifest["issues"]))
        self.assertEqual(external.read_bytes(), b"private external flight log")

    def test_snapshot_detects_source_mutation_during_read(self):
        source = self.root / "mutating.bin"
        source.write_bytes(b"source data")
        original_read = os.read
        changed = [False]

        def mutate_after_read(descriptor, count):
            result = original_read(descriptor, count)
            if result and not changed[0]:
                changed[0] = True
                with source.open("ab") as stream:
                    stream.write(b"changed")
            return result

        with mock.patch.object(incident_bundle.os, "read", side_effect=mutate_after_read):
            with self.assertRaises(SnapshotFailure) as caught:
                incident_bundle._snapshot_file(source, max_file_bytes=100, remaining_total_bytes=100)
        self.assertEqual(caught.exception.code, "source_changed")

    def test_output_never_overwrites_and_failed_zip_cleans_partial_output(self):
        run_dir, _checked = self.make_run()
        existing = self.root / "existing.zip"
        existing.write_bytes(b"preserve")
        code, _stdout, _stderr = self.invoke(run_dir, existing)
        self.assertEqual(code, 2)
        self.assertEqual(existing.read_bytes(), b"preserve")

        partial = self.root / "partial-write.zip"
        original_writestr = zipfile.ZipFile.writestr

        def fail_after_manifest(archive, name, data, *args, **kwargs):
            if name == "engine.log":
                raise OSError("injected disk full")
            return original_writestr(archive, name, data, *args, **kwargs)

        with mock.patch.object(zipfile.ZipFile, "writestr", autospec=True,
                               side_effect=fail_after_manifest):
            code, _stdout, stderr = self.invoke(run_dir, partial)
        self.assertEqual(code, 2)
        self.assertIn("injected disk full", stderr)
        self.assertFalse(partial.exists())

    def test_configuration_and_output_failures_do_not_leave_tracebacks(self):
        run_dir, _checked = self.make_run()
        output = self.root / "missing-parent" / "bad.txt"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main([str(run_dir), "--out", str(output)])
        self.assertEqual(code, 2)
        self.assertNotIn("Traceback", stderr.getvalue())

        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main([str(self.root / "missing-run"), "--out", str(self.root / "missing.zip")])
        self.assertEqual(code, 2)
        self.assertNotIn("Traceback", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
