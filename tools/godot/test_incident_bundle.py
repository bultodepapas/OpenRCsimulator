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

from research.performance.native_summary import (
    DEFAULT_POLICY, _hydrate_stream_report, summarize_run, validate_native_report,
)
from research.performance.test_native_summary import valid_report, write_stream_fixture, write_stream_run
from perfetto_export import BudgetError, build_trace, read_sources


class IncidentBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc incident bundle ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()  # macOS /var is a symlink to /private/var.
        self.runs = self.root / "runs"
        self.runs.mkdir()

    def make_run(self, code: str = "print('checked run')", *, script: str | None = None) -> tuple[Path, dict]:
        command = [sys.executable, "-c", code]
        if script is not None:
            command += ["--script", script]
        checked = run_checked(command, self.runs, timeout=5)
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

    def test_required_coverage_receipt_is_checked_without_rejecting_old_reports(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        run = self.read_receipt(run_dir)
        resource = json.loads((run_dir / "resources.json").read_text(encoding="utf-8"))
        self.assertEqual(incident_bundle._validate_resource_receipt(resource, run, run["resources"]), [])
        resource["required_coverage"] = "complete"
        run["resources"]["required_coverage"] = "partial"
        errors = incident_bundle._validate_resource_receipt(resource, run, run["resources"])
        self.assertTrue(any("required_coverage does not match" in error for error in errors))
        run["resources"]["required_coverage"] = "complete"
        self.assertEqual(incident_bundle._validate_resource_receipt(resource, run, run["resources"]), [])

    def test_required_coverage_is_verified_against_samples_before_manifest_claim(self):
        run_dir, _checked = self.make_run()
        self.add_resource_report(run_dir)
        run = self.read_receipt(run_dir)
        resource_path = run_dir / "resources.json"
        resource = json.loads(resource_path.read_text(encoding="utf-8"))
        fields = ("rss_bytes", "cpu_user_seconds", "cpu_system_seconds", "virtual_memory_available_bytes")
        sample = {field: 1 for field in fields}
        sample["field_status"] = {field: "ok" for field in fields}
        resource.update(samples=[sample], required_coverage="complete",
                        required_field_counts={field: 1 for field in fields},
                        capped=False, stop_reason="caller_finished",
                        summary={"counter_resets": []})
        content = json.dumps(resource).encode()
        resource_path.write_bytes(content)
        run["resources"].update(bytes=len(content), sha256=hashlib.sha256(content).hexdigest(),
                                required_coverage="complete")
        self.write_receipt(run_dir, run)
        manifest = create_bundle(run_dir, self.root / "required-valid.zip")
        entry = next(item for item in manifest["attachments"] if item["role"] == "resource_report")
        self.assertTrue(entry["required_coverage_validated"])
        self.assertTrue(manifest["bundle_complete"])
        resource["required_field_counts"]["rss_bytes"] = 0
        content = json.dumps(resource).encode()
        resource_path.write_bytes(content)
        run["resources"].update(bytes=len(content), sha256=hashlib.sha256(content).hexdigest())
        self.write_receipt(run_dir, run)
        manifest = create_bundle(run_dir, self.root / "required-invalid.zip")
        entry = next(item for item in manifest["attachments"] if item["role"] == "resource_report")
        self.assertFalse(entry["required_coverage_validated"])
        self.assertFalse(manifest["bundle_complete"])
        self.assertTrue(any("required_field_counts" in issue["message"] for issue in manifest["issues"]))

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
        self.assertEqual(manifest["run"]["status"], "passed")
        self.assertEqual(manifest["run"]["capture_identity"], "verified")
        self.assertEqual(manifest["source_metadata"]["note"], "repro on startup")
        by_role = {attachment["role"]: attachment for attachment in manifest["attachments"]}
        self.assertEqual(by_role["frame_report"]["validation"], "valid")
        self.assertEqual(by_role["flight_log"]["validation"], "caller_supplied_unverified")
        self.assertEqual(by_role["flight_log"]["sha256"], hashlib.sha256(flight_log.read_bytes()).hexdigest())
        self.assertFalse(manifest["claims"]["orfl_replay_validated"])

    def test_long_v3_pairs_round_trip_and_selected_timelines_declare_scope(self):
        run_dir, _checked = self.make_run()
        run = self.read_receipt(run_dir)
        run["capture_id"] = "fixture"
        self.write_receipt(run_dir, run)
        for hz, count, interval, step in ((60, 108_001, 16_667, 4), (120, 216_001, 8_334, 2)):
            with self.subTest(hz=hz):
                ticks = [240 + step * index for index in range(count)]
                source = valid_report(interval_usec=interval, ticks=ticks,
                                      sample_s=(count - 1) * interval / 1_000_000.0)
                for name in ("physics_step_usec", "draw_calls", "primitives", "object_count", "node_count",
                             "render_cpu_ms", "frame_setup_cpu_ms", "memory_static_bytes", "observer_poll_usec"):
                    source["raw_metrics"][name] = [1.0] * count
                frames, _records = write_stream_run(self.root, f"flight-{hz}", source)
                sidecar = frames.with_name(frames.name + ".frames.jsonl")
                output = self.root / f"long-{hz}.zip"
                manifest = create_bundle(run_dir, output, frames_path=frames)
                self.assertTrue(manifest["bundle_complete"], manifest["issues"])
                with zipfile.ZipFile(output) as archive:
                    frame_name = "frames/" + frames.name
                    sidecar_name = frame_name + ".frames.jsonl"
                    self.assertEqual(hashlib.sha256(archive.read(sidecar_name)).hexdigest(),
                                     hashlib.sha256(sidecar.read_bytes()).hexdigest())
                    archive.extract(frame_name, self.root / f"extract-{hz}")
                    archive.extract(sidecar_name, self.root / f"extract-{hz}")
                    log = archive.read("engine.log")
                extracted = self.root / f"extract-{hz}" / frame_name
                extracted.with_suffix(".log").write_bytes(log)
                report = json.loads(extracted.read_text(encoding="utf-8"))
                hydrated, receipt = _hydrate_stream_report(report, extracted)
                errors, _derived = validate_native_report(hydrated)
                self.assertEqual(errors, [])
                self.assertEqual(receipt["frames"], count)
                reduced = summarize_run(extracted, DEFAULT_POLICY)
                self.assertTrue(reduced["collection_valid"], reduced["collection_reasons"])
                self.assertEqual(reduced["stream"]["sha256"], receipt["sha256"])
                loaded, _resources = read_sources(frames_path=extracted)
                with self.assertRaisesRegex(BudgetError, "select a frame window or metrics"):
                    build_trace(frames=loaded, max_events=1_000_000)
                events, partial = build_trace(frames=loaded, frame_source=str(extracted),
                                              start_frame=count - 5, end_frame=count,
                                              selected_frame_metrics=["draw_calls"])
                self.assertFalse(partial)
                metadata = next(event["args"] for event in events if event.get("name") == "capture_metadata")
                self.assertFalse(metadata["full_session_timeline"])
                self.assertFalse(metadata["complete"])
                self.assertTrue(metadata["selected_scope_complete"])
                selected = metadata["sources"]["frames"]["selection"]
                self.assertEqual((selected["start_frame_inclusive"], selected["end_frame_exclusive"]),
                                 (count - 5, count))
                self.assertEqual(selected["metric_names"], ["draw_calls"])
                self.assertEqual(metadata["sources"]["frames"]["stream"]["sha256"], receipt["sha256"])
                self.assertEqual([event["args"]["frame_index"] for event in events if event.get("ph") == "X"],
                                 list(range(count - 5, count)))

    def test_orphan_and_damaged_v3_streams_are_retained_as_incomplete(self):
        run_dir, _checked = self.make_run()
        run = self.read_receipt(run_dir)
        run["capture_id"] = "fixture"
        self.write_receipt(run_dir, run)
        frames, records = write_stream_run(self.root, "damaged", valid_report())
        report = json.loads(frames.read_text(encoding="utf-8"))
        sidecar = frames.with_name(report["stream"]["file"])
        report["stream"]["sha256"] = "0" * 64
        frames.write_text(json.dumps(report), encoding="utf-8")
        manifest = create_bundle(run_dir, self.root / "bad-hash.zip", frames_path=frames)
        self.assertFalse(manifest["bundle_complete"])
        self.assertEqual(manifest["run"]["capture_identity"], "unverified_evidence_invalid")
        entries = {entry["role"]: entry for entry in manifest["attachments"]}
        self.assertTrue(entries["frame_stream"]["included"])
        self.assertEqual(entries["frame_stream"]["validation"], "invalid_stream_pair")
        self.assertIsNone(entries["frame_stream"]["source_complete"])
        with zipfile.ZipFile(self.root / "bad-hash.zip") as archive:
            self.assertEqual(archive.read(entries["frame_stream"]["archive_path"]), sidecar.read_bytes())
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            read_sources(frames_path=frames)

        # A cleanly written prefix has a valid file hash but no completion trailer.
        write_stream_fixture(frames, report, records[:-1])
        manifest = create_bundle(run_dir, self.root / "no-trailer.zip", frames_path=frames)
        self.assertFalse(manifest["bundle_complete"])
        self.assertTrue(any("completion trailer" in issue["message"] for issue in manifest["issues"]))
        self.assertTrue(next(entry for entry in manifest["attachments"] if entry["role"] == "frame_stream")["included"])
        with self.assertRaisesRegex(ValueError, "completion trailer"):
            read_sources(frames_path=frames)

        frames.unlink()
        manifest = create_bundle(run_dir, self.root / "orphan.zip", frame_stream_path=sidecar)
        self.assertFalse(manifest["bundle_complete"])
        stream = next(entry for entry in manifest["attachments"] if entry["role"] == "frame_stream")
        self.assertEqual(stream["validation"], "opaque_unverified")
        self.assertIsNone(stream["source_complete"])
        self.assertIsNone(stream["verified_frame_range"])
        with zipfile.ZipFile(self.root / "orphan.zip") as archive:
            self.assertEqual(archive.read(stream["archive_path"]), sidecar.read_bytes())
        manifest = create_bundle(run_dir, self.root / "missing-report-and-orphan.zip",
                                 frames_path=frames, frame_stream_path=sidecar)
        self.assertFalse(manifest["bundle_complete"])
        roles = {entry["role"]: entry for entry in manifest["attachments"]}
        self.assertEqual(roles["frame_report"]["status"], "missing")
        self.assertTrue(roles["frame_stream"]["included"])
        self.assertEqual(roles["frame_stream"]["validation"], "opaque_unverified")

    def test_v3_completion_and_run_association_are_independent(self):
        run_dir, _checked = self.make_run()
        frames, _records = write_stream_run(self.root, "other-capture", valid_report())
        manifest = create_bundle(run_dir, self.root / "other-capture.zip", frames_path=frames)
        entries = {entry["role"]: entry for entry in manifest["attachments"]}
        self.assertFalse(manifest["bundle_complete"])
        self.assertEqual(manifest["run"]["capture_identity"], "mismatch_or_unverified")
        self.assertEqual(entries["frame_report"]["validation"], "invalid")
        self.assertTrue(entries["frame_report"]["source_complete"])
        self.assertEqual(entries["frame_stream"]["validation"], "valid_stream_pair")
        self.assertTrue(entries["frame_stream"]["source_complete"])

    def test_v3_unsafe_paths_missing_sidecar_and_input_budget_fail_explicitly(self):
        run_dir, _checked = self.make_run()
        frames, _records = write_stream_run(
            self.root, "unsafe", valid_report(ticks=[240 + 3 * index for index in range(600)]))
        report = json.loads(frames.read_text(encoding="utf-8"))
        sidecar = frames.with_name(report["stream"]["file"])
        outside = self.root / "outside.jsonl"
        outside.write_text("private", encoding="utf-8")
        report["stream"]["file"] = "../outside.jsonl"
        frames.write_text(json.dumps(report), encoding="utf-8")
        manifest = create_bundle(run_dir, self.root / "unsafe.zip", frames_path=frames)
        self.assertFalse(manifest["bundle_complete"])
        self.assertFalse(any(entry["role"] == "frame_stream" for entry in manifest["attachments"]))
        with zipfile.ZipFile(self.root / "unsafe.zip") as archive:
            self.assertNotIn("outside.jsonl", archive.namelist())
        with self.assertRaisesRegex(ValueError, "same-directory sibling"):
            read_sources(frames_path=frames)
        report["stream"]["file"] = sidecar.name
        frames.write_text(json.dumps(report), encoding="utf-8")
        manifest = create_bundle(run_dir, self.root / "budget.zip", frames_path=frames,
                                 max_input_bytes=frames.stat().st_size, max_total_bytes=10_000_000)
        self.assertFalse(manifest["bundle_complete"])
        self.assertTrue(any(issue["code"] == "file_size_limit" for issue in manifest["issues"]))
        sidecar.unlink()
        manifest = create_bundle(run_dir, self.root / "missing.zip", frames_path=frames)
        self.assertFalse(manifest["bundle_complete"])
        self.assertEqual(next(entry for entry in manifest["attachments"] if entry["role"] == "frame_stream")["status"],
                         "missing")

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
        self.assertEqual(manifest["run"]["status"], "failed_or_invalid")

    def test_lighting_skip_is_valid_evidence_but_not_a_pass(self):
        message = "Lighting segment pixels SKIPPED: native rendering required at 1920x1080."
        run_dir, checked = self.make_run(f"print({message!r})",
                                         script="res://tests/test_lighting_segment_filter.gd")
        self.assertTrue(checked["ok"])
        output = self.root / "skip.zip"
        code, stdout, stderr = self.invoke(run_dir, output)
        self.assertEqual(code, 0, stderr)
        self.assertIn("incident bundle: complete; run skipped (unqualified)", stdout)
        self.assertNotIn("run passed", stdout)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn(message, archive.read("engine.log").decode())
        self.assertTrue(manifest["bundle_complete"])
        self.assertTrue(manifest["run"]["evidence_valid"])
        self.assertFalse(manifest["run_ok"])
        self.assertFalse(manifest["run"]["ok"])
        self.assertEqual(manifest["run"]["reason"], "skipped")
        self.assertEqual(manifest["run"]["status"], "skipped")
        self.assertEqual(manifest["run"]["declared_reason"], "passed")

    def test_lighting_success_without_completion_evidence_is_invalid(self):
        run_dir, checked = self.make_run("print('startup only')",
                                         script="res://tests/test_lighting_skin_patterns.gd")
        self.assertTrue(checked["ok"])
        output = self.root / "missing-completion.zip"
        code, stdout, stderr = self.invoke(run_dir, output)
        self.assertEqual(code, 1, stderr)
        self.assertIn("run failed or invalid", stdout)
        manifest, archive = self.unzip_manifest(output)
        with archive:
            self.assertIn("startup only", archive.read("engine.log").decode())
        self.assertFalse(manifest["bundle_complete"])
        self.assertFalse(manifest["run_ok"])
        self.assertFalse(manifest["run"]["evidence_valid"])
        self.assertEqual(manifest["run"]["reason"], "invalid_report")
        self.assertEqual(manifest["run"]["status"], "failed_or_invalid")

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
