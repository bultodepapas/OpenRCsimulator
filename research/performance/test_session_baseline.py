from __future__ import annotations

import copy
import hashlib
import tempfile
import unittest
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

try:
    from .session_baseline import (
        alternating_observer_order,
        _run_probe,
        _sha256_file,
        MAC_RECEIPT,
        inspect_godot,
        parse_probe_file,
        percentile_nearest_rank,
        reduce_backend_pair,
        reduce_pair,
        validate_probe_report,
        load_project_validator,
        mac_source_install_identity,
    )
except ImportError:  # Also support direct execution from this directory.
    from session_baseline import (
        alternating_observer_order,
        _run_probe,
        _sha256_file,
        MAC_RECEIPT,
        inspect_godot,
        parse_probe_file,
        percentile_nearest_rank,
        reduce_backend_pair,
        reduce_pair,
        validate_probe_report,
        load_project_validator,
        mac_source_install_identity,
    )

baseline = sys.modules[_run_probe.__module__]


def valid_report(observer: bool = True) -> dict:
    tick = [3, 4, 5, 6, 7]
    return {
        "format": "openrc-session-cost v1",
        "complete": True,
        "failure": "",
        "aircraft_id": "jensen-das-ugly-stik-60",
        "case_id": "trim",
        "observer": observer,
        "requested": {"warmup_ticks": 4, "sample_ticks": 5},
        "completed": {"warmup_ticks": 4, "sample_ticks": 5},
        "tick_usec": tick if observer else [],
        "input_usec": [1, 1, 2, 2, 3] if observer else [],
        "simulation_usec": [2, 3, 3, 4, 4] if observer else [],
        "measured_wall_usec": 500 if observer else 450,
        "fingerprint": "a" * 64,
        "final_tick": 9,
        "input_reads": 9,
        "setup_usec": {"data_load": 100, "aircraft_setup": 200},
        "machine": {
            "os": "Windows",
            "processor": "Example CPU",
            "logical_cpu_count": 8,
            "architecture": "x86_64",
            "godot": "4.7.2-stable (official)",
        },
        "world": {"identity": "field-sha256", "proxies": 128, "lake_identity": "lake-sha256", "field": "default"},
        "tick_hz": 240,
        "scope": "deterministic complete-session CPU probe",
    }


def valid_current_report(backend: str = "gdscript_reference", observer: bool = True) -> dict:
    report = valid_report(observer)
    actual = {"backend": backend}
    stats = {}
    if backend == "native":
        actual.update({"backend_version": "openrc-native-kernel-stage-v1", "abi_version": 1,
                       "binary_sha256": "b" * 64, "source_sha256": "c" * 64, "lock_sha256": "d" * 64})
        stats = {"context_calls": 9, "stage_calls": 36, "stage_ns": 0, "timing": False}
    report.update({"format": "openrc-session-cost v2", "backend": {"requested": backend, "actual": actual,
                   "native_stats": stats}, "fingerprint_boundaries": 10,
                   "solver_sha256": "e" * 64, "aircraft_sha256": "f" * 64})
    report["machine"]["godot"] = "4.8-beta2 (official)"
    return report


class ProbeReportValidationTests(unittest.TestCase):
    def test_v2_beta1_reports_remain_readable_but_live_runs_require_beta2(self):
        report = valid_current_report()
        report["machine"]["godot"] = "4.8-beta1 (official)"
        self.assertEqual(validate_probe_report(report), [])
        self.assertIn("machine.godot does not match requested run",
                      validate_probe_report(report, expected={"godot": "4.8-beta2 (official)"}))
        report["machine"]["godot"] = "4.8-beta3 (official)"
        self.assertIn("machine.godot must identify the pinned version for this report",
                      validate_probe_report(report))

    def test_complete_observer_on_and_off_reports_validate(self):
        for observer in (True, False):
            with self.subTest(observer=observer):
                self.assertEqual(validate_probe_report(valid_report(observer)), [])

    def test_incomplete_probe_is_retained_as_a_valid_failure_but_rejected_for_pairing(self):
        report = valid_report()
        report.update({
            "complete": False,
            "failure": "fixture paused on failed attempted tick",
            "requested": {"warmup_ticks": 1, "sample_ticks": 5},
            "completed": {"warmup_ticks": 1, "sample_ticks": 2},
            # The third timing is the failed attempted tick; completed excludes it.
            "tick_usec": [3, 4, 5],
            "input_usec": [1, 1, 2],
            "simulation_usec": [2, 3, 3],
            "final_tick": 4,
            "input_reads": 4,
        })

        self.assertEqual(validate_probe_report(report, allow_incomplete=True), [])
        errors = validate_probe_report(report)
        self.assertTrue(any("probe reported incomplete" in error for error in errors))

    def test_truncated_complete_samples_are_rejected(self):
        report = valid_report()
        for key in ("tick_usec", "input_usec", "simulation_usec"):
            report[key] = report[key][:-1]
        errors = validate_probe_report(report)
        self.assertTrue(any("must match requested sample ticks" in error for error in errors))

    def test_incomplete_report_cannot_omit_a_completed_timing_sample(self):
        report = valid_report()
        report.update({
            "complete": False,
            "failure": "stopped",
            "requested": {"warmup_ticks": 4, "sample_ticks": 5},
            "completed": {"warmup_ticks": 4, "sample_ticks": 3},
            "tick_usec": [3, 4],
            "input_usec": [1, 1],
            "simulation_usec": [2, 3],
            "final_tick": 7,
            "input_reads": 7,
        })
        errors = validate_probe_report(report, allow_incomplete=True)
        self.assertTrue(any("completed samples or one failed attempt" in error for error in errors))

    def test_boolean_values_are_not_accepted_as_integer_counts(self):
        mutations = (
            ("requested", "sample_ticks", True),
            ("completed", "warmup_ticks", False),
            ("machine", "logical_cpu_count", True),
        )
        for parent, key, value in mutations:
            report = valid_report()
            report[parent][key] = value
            with self.subTest(parent=parent, key=key):
                self.assertTrue(validate_probe_report(report))

    def test_observer_and_complete_must_be_real_booleans(self):
        for key, value in (("observer", 1), ("complete", 1)):
            report = valid_report()
            report[key] = value
            with self.subTest(key=key):
                self.assertTrue(any(key + " must be a boolean" in error for error in validate_probe_report(report)))

    def test_invalid_tick_decomposition_and_final_tick_are_rejected(self):
        report = valid_report()
        report["simulation_usec"][2] += 1
        report["final_tick"] = 10
        errors = validate_probe_report(report)
        self.assertTrue(any("tick_usec[2]" in error for error in errors))
        self.assertTrue(any("final_tick" in error for error in errors))

    def test_timing_samples_cannot_exceed_the_measured_outer_loop(self):
        report = valid_report()
        report["measured_wall_usec"] = 24
        errors = validate_probe_report(report)
        self.assertTrue(any("sum(tick_usec)" in error for error in errors))

    def test_empty_identity_on_complete_run_is_rejected(self):
        report = valid_report()
        report["world"]["identity"] = ""
        self.assertTrue(any("world.identity" in error for error in validate_probe_report(report)))

    def test_truncated_json_and_json_nan_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.json"
            path.write_text("{\"format\":", encoding="utf-8")
            report, error = parse_probe_file(path)
            self.assertIsNone(report)
            self.assertIn("malformed", error)

            path.write_text('{"format":"openrc-session-cost v1","value":NaN}', encoding="utf-8")
            report, error = parse_probe_file(path)
            self.assertIsNone(report)
            self.assertIn("non-finite", error)

    def test_nested_non_finite_value_is_rejected(self):
        report = valid_report()
        report["machine"]["temperature"] = float("inf")
        self.assertTrue(any("must be finite" in error for error in validate_probe_report(report)))


class ReducerTests(unittest.TestCase):
    def test_identical_pair_reports_variation_only_for_matching_complete_on_runs(self):
        a = valid_current_report("native")
        a.update(template_release=False, solver_identity_kind="source-tree-v1", probe_sha256="9" * 64)
        b = copy.deepcopy(a)
        b["input_usec"] = [item + 1 for item in b["input_usec"]]
        b["tick_usec"] = [item + 1 for item in b["tick_usec"]]
        result = baseline.reduce_identical_pair(a, b, "native")
        self.assertTrue(result["comparable"], result["reasons"])
        self.assertEqual(result["a_callback_mean_usec_per_tick"], 5)
        self.assertEqual(result["b_callback_mean_usec_per_tick"], 6)
        self.assertEqual(result["a_over_b_callback_mean_ratio"], 5 / 6)
        self.assertEqual(result["absolute_callback_mean_difference_usec_per_tick"], 1)
        self.assertAlmostEqual(result["absolute_ratio_deviation_percent"], 100 / 6)
        self.assertFalse(any("speedup" in key or "overhead" in key for key in result))
        for change in (lambda report: report.update(fingerprint="0" * 64),
                       lambda report: report.update(complete=False, failure="interrupted"),
                       lambda report: report.update(observer=False),
                       lambda report: report.update(fingerprint_boundaries=9),
                       lambda report: report.update(solver_sha256="0" * 64),
                       lambda report: report["backend"]["actual"].update(binary_sha256="0" * 64),
                       lambda report: report["backend"]["actual"].update(backend="gdscript_reference"),
                       lambda report: report["backend"]["native_stats"].update(stage_calls=0),
                       lambda report: report["backend"]["native_stats"].update(context_calls=0)):
            changed = copy.deepcopy(b)
            change(changed)
            reduced = baseline.reduce_identical_pair(a, changed, "native")
            self.assertFalse(reduced["comparable"])
            self.assertIsNone(reduced["a_over_b_callback_mean_ratio"])
            self.assertIsNone(reduced["absolute_callback_mean_difference_usec_per_tick"])
        zero = copy.deepcopy(a)
        for key in ("tick_usec", "input_usec", "simulation_usec"):
            zero[key] = [0] * 5
        self.assertFalse(baseline.reduce_identical_pair(a, zero, "native")["comparable"])
        self.assertFalse(baseline.reduce_identical_pair(valid_report(), valid_report(), "gdscript_reference")["comparable"])

    def test_current_and_historical_engine_reports_cannot_be_paired(self):
        on, off = valid_current_report(), valid_current_report(observer=False)
        on["machine"]["godot"] = off["machine"]["godot"] = "4.8-beta1 (official)"
        self.assertTrue(reduce_pair(on, off)["comparable"])
        off["machine"]["godot"] = "4.8-beta2 (official)"
        self.assertFalse(reduce_pair(on, off)["comparable"])

        reference, native = valid_current_report(), valid_current_report("native")
        reference["machine"]["godot"] = native["machine"]["godot"] = "4.8-beta1 (official)"
        self.assertTrue(reduce_backend_pair(reference, native)["comparable"])
        native["machine"]["godot"] = "4.8-beta2 (official)"
        self.assertFalse(reduce_backend_pair(reference, native)["comparable"])

    def test_current_backend_pair_requires_identity_and_complete_trajectory(self):
        reference, native = valid_current_report(), valid_current_report("native")
        self.assertEqual(validate_probe_report(reference), [])
        self.assertEqual(validate_probe_report(native), [])
        self.assertTrue(reduce_backend_pair(reference, native)["comparable"])
        for field, value in (("fingerprint", "1" * 64), ("solver_sha256", "2" * 64),
                             ("aircraft_sha256", "3" * 64), ("fingerprint_boundaries", 9),
                             ("solver_identity_kind", "packaged-executable-v1"),
                             ("template_release", True), ("probe_sha256", "4" * 64)):
            changed = valid_current_report("native")
            changed[field] = value
            with self.subTest(field=field):
                self.assertFalse(reduce_backend_pair(reference, changed)["comparable"])
                self.assertIsNone(reduce_backend_pair(reference, changed)["reference_over_native"])

    def test_native_fallback_or_uncovered_ticks_cannot_be_timed(self):
        reference = valid_current_report()
        native = valid_current_report("native")
        native["backend"]["actual"] = {"backend": "gdscript_reference"}
        self.assertFalse(reduce_backend_pair(reference, native)["comparable"])
        for counter in ("stage_calls", "context_calls"):
            native = valid_current_report("native")
            native["backend"]["native_stats"][counter] = 0
            self.assertFalse(reduce_backend_pair(reference, native)["comparable"])
        self.assertFalse(reduce_backend_pair(valid_report(), valid_report())["comparable"])

    def test_observer_pair_rejects_mixed_backend_or_sources(self):
        for mutation in ("backend", "solver_sha256", "aircraft_sha256", "fingerprint_boundaries"):
            on, off = valid_current_report(), valid_current_report(observer=False)
            if mutation == "backend":
                off = valid_current_report("native", observer=False)
            elif mutation == "fingerprint_boundaries":
                off[mutation] -= 1
            else:
                off[mutation] = "9" * 64
            with self.subTest(mutation=mutation):
                self.assertFalse(reduce_pair(on, off)["comparable"])

    def test_direct_reduction_rejects_equal_missing_or_malformed_identities(self):
        for field in ("fingerprint", "machine", "world", "format", "completed"):
            on_report, off_report = valid_report(True), valid_report(False)
            del on_report[field]
            del off_report[field]
            with self.subTest(field=field):
                result = reduce_pair(on_report, off_report)
                self.assertFalse(result["comparable"])
                self.assertIsNone(result["observer_overhead_usec_per_tick"])

    def test_nearest_rank_percentiles(self):
        values = [10, 1, 9, 3, 7, 6, 2, 8, 4, 5]
        self.assertEqual(percentile_nearest_rank(values, 50), 5)
        self.assertEqual(percentile_nearest_rank(values, 95), 10)
        self.assertEqual(percentile_nearest_rank(values, 99), 10)
        self.assertEqual(percentile_nearest_rank(values, 1), 1)

    def test_nearest_rank_rejects_empty_invalid_and_boolean_inputs(self):
        with self.assertRaises(ValueError):
            percentile_nearest_rank([], 50)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([1], 0)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([1], 101)
        with self.assertRaises(ValueError):
            percentile_nearest_rank([True], 50)

    def test_matching_fingerprints_allow_per_tick_observer_overhead(self):
        on_report = valid_report(observer=True)
        off_report = valid_report(observer=False)
        reduced = reduce_pair(on_report, off_report)
        self.assertTrue(reduced["fingerprints_equal"])
        self.assertTrue(reduced["comparable"])
        self.assertEqual(reduced["observer_on_wall_usec_per_tick"], 100)
        self.assertEqual(reduced["observer_off_wall_usec_per_tick"], 90)
        self.assertEqual(reduced["observer_overhead_usec_per_tick"], 10)

    def test_mismatched_fingerprints_never_produce_overhead(self):
        on_report = valid_report(observer=True)
        off_report = valid_report(observer=False)
        off_report["fingerprint"] = "b" * 64
        reduced = reduce_pair(on_report, off_report)
        self.assertFalse(reduced["fingerprints_equal"])
        self.assertFalse(reduced["comparable"])
        self.assertIsNone(reduced["observer_overhead_usec_per_tick"])
        self.assertIn("different fingerprints", reduced["reasons"][0])

    def test_observer_order_alternates(self):
        self.assertEqual(alternating_observer_order(1), ("on", "off"))
        self.assertEqual(alternating_observer_order(2), ("off", "on"))
        self.assertEqual(alternating_observer_order(3), ("on", "off"))
        with self.assertRaises(ValueError):
            alternating_observer_order(0)


class EngineInspectionTests(unittest.TestCase):
    def test_only_exact_current_official_build_can_run_a_new_campaign(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "godot"
            executable.write_bytes(b"engine fixture")
            for version, accepted in (("4.8.beta2.official.cafc17a19", True),
                                      ("4.8.beta1.official.4d10419ca", False),
                                      ("4.8.beta2.custom.cafc17a19", False),
                                      ("4.8.beta2.official.different", False)):
                with self.subTest(version=version), patch("subprocess.run", return_value=SimpleNamespace(
                        stdout=version + "\n", returncode=0)):
                    if accepted:
                        self.assertEqual(inspect_godot(executable, 30)["version"], version)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "expected Godot"):
                            inspect_godot(executable, 30)


class ReleaseProbeAdmissionTests(unittest.TestCase):
    def test_mac_release_probe_requires_bundle_architecture_probe_and_stability(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, probe = root / "release", root / "probe.gd"
            executable.write_bytes(b"release executable")
            probe.write_bytes(b"probe source")
            exe_hash, probe_hash = _sha256_file(executable), _sha256_file(probe)
            output, log = root / "report.json", root / "run.log"
            mac = {"identities": {"arm64": "1" * 64, "x86_64": "2" * 64}, "probe_sha256": probe_hash}
            report = valid_current_report()
            report["machine"].update({"os": "macOS", "architecture": "arm64"})
            report.update({"template_release": True, "solver_identity_kind": "macos-reference-bundle-v1",
                           "solver_sha256": "1" * 64, "probe_sha256": probe_hash})
            marker = "NATIVE_QUALIFICATION mode=session verdict=pass\n"

            def run_case(candidate, verify_results=None, backend="gdscript_reference"):
                class Process:
                    returncode = 0
                    def __init__(self, command, **kwargs):
                        output.write_text(json.dumps(candidate), encoding="utf-8")
                        kwargs["stdout"].write(marker)
                    def wait(self, timeout):
                        return 0
                results = verify_results or [mac, mac]
                with patch("subprocess.Popen", Process), \
                        patch.object(MAC_RECEIPT, "verify_for_launch", side_effect=results):
                    return _run_probe(godot=executable, app_dir=root, probe=probe, output_json=output,
                                      log_path=log, aircraft_id=report["aircraft_id"], case_id="trim", observer=True,
                                      warmup_ticks=4, sample_ticks=5, timeout=5, physics_backend=backend,
                                      native_source_sha256="c" * 64, release_executable=True,
                                      executable_sha256=exe_hash, probe_sha256=probe_hash, mac_identity=mac)

            good = run_case(report)
            self.assertTrue(good["accepted"], good["failures"])
            for changes in ({"solver_sha256": "2" * 64}, {"solver_identity_kind": "packaged-executable-v1"},
                            {"probe_sha256": "f" * 64}, {"machine": dict(report["machine"], architecture="riscv64")},
                            {"machine": dict(report["machine"], os="Linux")}):
                with self.subTest(changes=changes):
                    self.assertFalse(run_case(dict(report, **changes))["accepted"])
            self.assertFalse(run_case(report, [mac, dict(mac, probe_sha256="f" * 64)])["accepted"])
            self.assertFalse(run_case(report, [ValueError("receipt changed")])["accepted"])
            self.assertFalse(run_case(report, backend="native")["accepted"])

    def test_release_probe_requires_exact_host_executable_and_embedded_probe(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, probe = root / "release", root / "probe.gd"
            executable.write_bytes(b"release executable")
            probe.write_bytes(b"probe source")
            library = root / "native/kernel/libopenrc_native_kernel.so"
            library.parent.mkdir(parents=True)
            library.write_bytes(b"native library")
            exe_hash, probe_hash = _sha256_file(executable), _sha256_file(probe)
            output, log = root / "report.json", root / "run.log"
            report = valid_current_report("native")
            report["backend"]["actual"]["binary_sha256"] = _sha256_file(library)
            report.update({"template_release": True, "solver_identity_kind": "packaged-executable-v1",
                           "solver_sha256": exe_hash, "probe_sha256": probe_hash})
            marker = "NATIVE_QUALIFICATION mode=session verdict=pass\n"

            def run_case(candidate: dict, output_marker: str, expected_hash: str = exe_hash):
                class Process:
                    returncode = 0

                    def __init__(self, command, **kwargs):
                        self.command = command
                        output.write_text(json.dumps(candidate), encoding="utf-8")
                        kwargs["stdout"].write(output_marker)

                    def wait(self, timeout):
                        return 0

                with patch("subprocess.Popen", Process):
                    return _run_probe(godot=executable, app_dir=root, probe=probe, output_json=output,
                                      log_path=log, aircraft_id=report["aircraft_id"], case_id="trim",
                                      observer=True, warmup_ticks=4, sample_ticks=5, timeout=5,
                                      physics_backend="native", native_source_sha256="c" * 64,
                                      release_executable=True, executable_sha256=expected_hash,
                                      probe_sha256=probe_hash)

            accepted = run_case(report, marker)
            self.assertTrue(accepted["accepted"], accepted["failures"])
            self.assertIn("--native-qualification=session", accepted["command"])
            self.assertNotIn("--path", accepted["command"])
            self.assertNotIn("--script", accepted["command"])
            historical = dict(report, machine=dict(report["machine"], godot="4.8-beta1 (official)"))
            self.assertFalse(run_case(historical, marker)["accepted"])
            for field, value in (("template_release", False), ("solver_sha256", "1" * 64),
                                 ("solver_identity_kind", "source-tree-v1"), ("probe_sha256", "2" * 64)):
                changed = dict(report, **{field: value})
                with self.subTest(field=field):
                    self.assertFalse(run_case(changed, marker)["accepted"])
            self.assertFalse(run_case(report, "")["accepted"])
            self.assertFalse(run_case(report, marker, "0" * 64)["accepted"])
            malformed = dict(report, backend={"requested": "native", "actual": [], "native_stats": {}})
            self.assertFalse(run_case(malformed, marker)["accepted"])
            library.write_bytes(b"different native library")
            self.assertFalse(run_case(report, marker)["accepted"])


class PreparedMacSourceTests(unittest.TestCase):
    def _installation(self, root: Path):
        app = root / "app"
        native = app / "native/kernel"
        native.mkdir(parents=True)
        executable = root / "Godot"
        executable.write_bytes(b"official engine fixture")
        library = native / "libopenrc_native_kernel.dylib"
        library.write_bytes(b"signed native fixture")
        (native / "openrc_native_kernel_macos.gdextension").write_text("mac descriptor")
        engine_sha = _sha256_file(executable)
        source_sha = "c" * 64
        row = {"platform": "macos", "architecture": "arm64", "backend": "native",
               "qualification_scope": "macos-arm64-fixed-wing-experimental-v1",
               "engine_sha256": engine_sha, "engine": {"sha256": engine_sha},
               "source_sha256": source_sha, "binary_sha256": _sha256_file(library), "lock_sha256": "d" * 64,
               "backend_version": "openrc-native-kernel-stage-v1", "abi_version": 1,
               "runtime_os_version": "27.0.1", "runtime_os_build": "26A434"}
        receipt = {"format": "openrc-native-kernel-receipt", "backend": "native",
                   "backend_version": row["backend_version"], "abi_version": row["abi_version"], "platforms": {"macos": row}}
        (native / "build-receipt-macos.json").write_text(json.dumps(receipt))
        return app, executable, library, receipt

    def test_real_prepared_project_verifier_rejects_content_and_settings_changes(self):
        with tempfile.TemporaryDirectory(prefix="session-project-") as directory:
            root = Path(directory)
            runner_path = root / "research/native-kernel/run.py"
            runner_path.parent.mkdir(parents=True)
            shutil.copy2(Path(baseline.__file__).resolve().parents[2] / "research/native-kernel/run.py", runner_path)
            app = root / "app"
            (app / "sim").mkdir(parents=True)
            project_data = (b'[application]\nconfig/name="OpenRC Simulator"\n'
                            b'[rendering]\nlights_and_shadows/multi_bounce_occlusion/enabled=true\n')
            (app / "project.godot").write_bytes(project_data)
            (app / "sim/core.gd").write_text("# canonical\n")
            prepared = root / "isolated/app"
            (prepared / "sim").mkdir(parents=True)
            name = "OpenRC-Research-" + "a" * 32
            edited = project_data.replace(b'config/name="OpenRC Simulator"', f'config/name="{name}"'.encode()).replace(
                b"enabled=true", b"enabled=false")
            (prepared / "project.godot").write_bytes(edited)
            (prepared / "sim/core.gd").write_text("# canonical\n")
            validator = load_project_validator(root)
            receipt = {"format": "openrc-graphics-research-preparation v1", "complete": True,
                       "source": {"copied_app_manifest_sha256": validator._inventory_hash(validator._project_inventory(app))},
                       "destination": {"app": str(prepared), "project_name": name,
                                       "project_sha256": _sha256_file(prepared / "project.godot")}}
            (prepared.parent / "research-preparation.json").write_text(json.dumps(receipt))
            proof = validator.validate_project(prepared.resolve())
            self.assertEqual(proof["checked_files"], 2)
            (prepared / "sim/core.gd").write_text("# changed\n")
            with self.assertRaisesRegex(ValueError, "content differs"):
                validator.validate_project(prepared.resolve())

    def test_mac_source_receipt_binds_engine_scope_source_and_actual_library(self):
        with tempfile.TemporaryDirectory(prefix="session-mac-source-") as directory:
            root = Path(directory)
            app, executable, library, receipt = self._installation(root)
            engine_sha = _sha256_file(executable)
            identity = mac_source_install_identity(app, engine_sha, "c" * 64)
            self.assertEqual(identity["binary_sha256"], _sha256_file(library))
            for engine, source in (("0" * 64, "c" * 64), (engine_sha, "0" * 64)):
                with self.subTest(engine=engine, source=source), self.assertRaises(ValueError):
                    mac_source_install_identity(app, engine, source)
            receipt["platforms"]["macos"]["qualification_scope"] = "production"
            (app / "native/kernel/build-receipt-macos.json").write_text(json.dumps(receipt))
            with self.assertRaises(ValueError):
                mac_source_install_identity(app, engine_sha, "c" * 64)
            library.unlink()
            with self.assertRaises(ValueError):
                mac_source_install_identity(app, engine_sha, "c" * 64)

    def test_opt_in_is_explicit_and_native_fallback_or_binary_changes_fail(self):
        with tempfile.TemporaryDirectory(prefix="session-mac-probe-") as directory:
            root = Path(directory)
            app, executable, library, _receipt = self._installation(root)
            probe, output, log = root / "probe.gd", root / "report.json", root / "run.log"
            probe.write_text("# probe")
            engine_sha = _sha256_file(executable)
            identity = mac_source_install_identity(app, engine_sha, "c" * 64)
            report = valid_current_report("native")
            report["backend"]["actual"]["binary_sha256"] = identity["binary_sha256"]
            report["machine"].update(os="macOS", architecture="arm64")
            report.update(experimental_native_macos=True, template_release=False, solver_identity_kind="source-tree-v1")

            def run_case(candidate, *, requested=True, source=identity, backend="native", change_library=False):
                class Process:
                    returncode = 0
                    def __init__(self, command, **_kwargs):
                        output.write_text(json.dumps(candidate))
                    def wait(self, timeout):
                        if change_library:
                            library.write_bytes(b"changed while measured")
                        return 0
                with patch("subprocess.Popen", Process):
                    return _run_probe(godot=executable, app_dir=app, probe=probe, output_json=output, log_path=log,
                                      aircraft_id=report["aircraft_id"], case_id="trim", observer=True,
                                      warmup_ticks=4, sample_ticks=5, timeout=5, physics_backend=backend,
                                      native_source_sha256="c" * 64, executable_sha256=engine_sha,
                                      experimental_native_macos=requested, mac_source_identity=source)

            accepted = run_case(report)
            self.assertTrue(accepted["accepted"], accepted["failures"])
            self.assertIn("--experimental-native-macos=true", accepted["command"])
            self.assertFalse(run_case(dict(report, experimental_native_macos=False))["accepted"])
            self.assertFalse(run_case(report, source=None)["accepted"])
            fallback = dict(report, backend={"requested": "native", "actual": {"backend": "gdscript_reference"},
                                             "native_stats": {}})
            self.assertFalse(run_case(fallback)["accepted"])
            self.assertFalse(run_case(report, change_library=True)["accepted"])
            library.write_bytes(b"signed native fixture")
            reference = valid_current_report()
            without_opt_in = run_case(reference, requested=False, source=None, backend="gdscript_reference")
            self.assertTrue(without_opt_in["accepted"], without_opt_in["failures"])
            self.assertNotIn("--experimental-native-macos=true", without_opt_in["command"])
            self.assertFalse(run_case(dict(reference, experimental_native_macos=True), requested=False,
                                      source=None, backend="gdscript_reference")["accepted"])

    def test_release_and_campaign_comparison_do_not_silently_ignore_source_flags(self):
        with tempfile.TemporaryDirectory(prefix="session-flags-") as directory:
            root = Path(directory)
            engine = root / "Godot"
            engine.write_bytes(b"engine")
            with patch.object(baseline, "run_campaign") as run:
                self.assertEqual(baseline.main(["--godot", str(engine), "--out", str(root / "one"),
                                                "--release-executable", "--project", str(root / "app")]), 1)
                self.assertEqual(baseline.main(["--godot", str(engine), "--out", str(root / "two"),
                                                "--release-executable", "--experimental-native-macos"]), 1)
                run.assert_not_called()
            with patch.object(baseline, "compare_campaigns") as compare:
                self.assertEqual(baseline.main(["--compare-campaigns", "before.json", "after.json",
                                                "--out", str(root / "three"), "--experimental-native-macos"]), 1)
                compare.assert_not_called()
            malformed = valid_current_report()
            malformed["experimental_native_macos"] = 1
            self.assertIn("experimental_native_macos must be a boolean", validate_probe_report(malformed))

    def test_paired_campaign_forwards_project_opt_in_and_rejects_changed_inventory(self):
        with tempfile.TemporaryDirectory(prefix="session-campaign-") as directory:
            root = Path(directory)
            app, engine, _library, _receipt = self._installation(root)
            (app / "project.godot").write_text("config_version=5\n")
            source_identity = mac_source_install_identity(app, _sha256_file(engine), "c" * 64)
            proof = {"canonical_manifest_sha256": "a" * 64, "executed_project_content_sha256": "b" * 64,
                     "checked_files": 2, "excluded_generated_suffixes": [".import", ".uid"]}
            seen = []
            def run_probe(**kwargs):
                seen.append((kwargs["physics_backend"], kwargs["app_dir"], kwargs["experimental_native_macos"]))
                report = valid_current_report(kwargs["physics_backend"])
                report["machine"].update(os="macOS", architecture="arm64")
                report.update(experimental_native_macos=True, template_release=False, solver_identity_kind="source-tree-v1")
                if kwargs["physics_backend"] == "native":
                    report["backend"]["actual"]["binary_sha256"] = source_identity["binary_sha256"]
                kwargs["output_json"].write_text(json.dumps(report))
                return {"accepted": True, "report": report, "failures": [], "validation_errors": [],
                        "report_file": str(kwargs["output_json"]), "log": str(kwargs["log_path"])}
            def campaign(output: Path, project_results):
                validator = SimpleNamespace(validate_project=unittest.mock.Mock(side_effect=project_results))
                args = ["--godot", str(engine), "--project", str(app), "--out", str(output),
                        "--aircraft", "jensen-das-ugly-stik-60", "--case", "trim", "--warmup-ticks", "4",
                        "--sample-ticks", "5", "--repeats", "2", "--compare-backends", "--experimental-native-macos"]
                with patch.object(baseline, "capture_workspace_identity", return_value={}), \
                     patch.object(baseline, "inspect_godot", return_value={"sha256": _sha256_file(engine)}), \
                     patch.object(baseline, "native_source_digest", return_value="c" * 64), \
                     patch.object(baseline, "app_source_digest", return_value="app-digest"), \
                     patch.object(baseline, "load_project_validator", return_value=validator), \
                     patch.object(baseline, "_run_probe", side_effect=run_probe):
                    result = baseline.main(args)
                return result, json.loads((output / "session_baseline.json").read_text())
            code, report = campaign(root / "good", [proof, proof])
            self.assertEqual(code, 0, report["failures"])
            self.assertTrue(report["complete"])
            self.assertEqual(report["format"], baseline.BASELINE_FORMAT)
            self.assertEqual(report["configuration"]["pair_type"], "backends")
            self.assertFalse((root / "good/session_identical.json").exists())
            self.assertEqual([mode for mode, _app, _enabled in seen], ["gdscript_reference", "native", "native", "gdscript_reference"])
            self.assertTrue(all(path == app.resolve() and enabled for _mode, path, enabled in seen))
            self.assertEqual(report["metadata"]["project"]["inventory_before"], proof)
            campaign_path = root / "good/session_baseline.json"
            _campaign, raw = baseline._campaign_runs(campaign_path)
            self.assertEqual(len(raw), 2)
            native_row = report["pairs"][0]["runs"]["native"]
            native_path = campaign_path.parent / native_row["report_relative_path"]
            tampered = json.loads(native_path.read_text())
            tampered["backend"]["native_stats"]["stage_calls"] = 0
            native_path.write_text(json.dumps(tampered))
            native_row["report_sha256"] = _sha256_file(native_path)
            campaign_path.write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "not comparable"):
                baseline._campaign_runs(campaign_path)
            seen.clear()
            code, report = campaign(root / "stale", [proof, dict(proof, checked_files=3)])
            self.assertEqual(code, 1)
            self.assertFalse(report["complete"])
            self.assertTrue(any("inventory verifier changed" in error for error in report["failures"]))


def mac_release_fixture(root: Path):
    executable = root / "OpenRC.app/Contents/MacOS/OpenRC"
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b"verified release executable")
    probe = Path(baseline.__file__).with_name("session_probe.gd").resolve()
    reference_receipt, native_receipt = "1" * 64, "2" * 64
    identity = lambda value: hashlib.sha256((value + "\narm64").encode()).hexdigest()
    reference = {"kind": MAC_RECEIPT.KIND, "architecture": "arm64", "sha256": identity(reference_receipt),
                 "receipt_sha256": reference_receipt, "executable_sha256": _sha256_file(executable),
                 "pack_sha256": "3" * 64, "probe_sha256": _sha256_file(probe),
                 "source_commit": "a" * 40, "source_tree": "b" * 40, "source_worktree_sha256": "c" * 64}
    native = {"kind": MAC_RECEIPT.NATIVE_KIND, "architecture": "arm64", "sha256": identity(native_receipt),
              "receipt_sha256": native_receipt, "reference_receipt_sha256": reference_receipt,
              "manifest_sha256": "4" * 64, "descriptor_sha256": "5" * 64, "library_sha256": "6" * 64,
              "license_sha256": "7" * 64}
    return executable, probe, reference, native


def mac_release_source_fixture(reference: dict) -> dict:
    return {"commit": reference["source_commit"], "tree": reference["source_tree"],
            "worktree_sha256": reference["source_worktree_sha256"], "dirty": True}


def mac_release_report(backend: str, reference: dict, native: dict) -> dict:
    report = valid_current_report(backend)
    report["machine"].update(os="macOS", architecture="arm64")
    report.update(experimental_native_macos=True, template_release=True,
                  solver_identity_kind=MAC_RECEIPT.NATIVE_KIND if backend == "native" else MAC_RECEIPT.KIND,
                  solver_sha256=native["sha256"] if backend == "native" else reference["sha256"],
                  probe_sha256=reference["probe_sha256"])
    if backend == "native":
        report["backend"]["actual"].update(binary_sha256=native["library_sha256"],
            abi_version=2, backend_version="openrc-native-kernel-stage-v2")
    return report


class MacNativeReleaseTests(unittest.TestCase):
    def test_actual_git_declaration_detects_application_changes(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-source-git-") as directory:
            root = Path(directory)
            app_file = root / "app/sim.gd"
            app_file.parent.mkdir()
            app_file.write_text("# committed source\n")
            def git(*args):
                return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "--quiet")
            git("add", "app/sim.gd")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture")
            before = baseline.capture_mac_release_source(root)
            reference = {"source_commit": before["commit"], "source_tree": before["tree"],
                         "source_worktree_sha256": before["worktree_sha256"]}
            self.assertTrue(baseline.mac_release_source_matches(reference, before))
            app_file.write_text("# changed application source\n")
            after = baseline.capture_mac_release_source(root)
            self.assertFalse(baseline.mac_release_source_matches(reference, after))
            self.assertTrue(after["dirty"])

    def test_real_receipt_verifiers_interoperate_with_release_pair_policy(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-real-verifiers-") as directory:
            root = Path(directory)
            bundle = root / "OpenRC.app"
            executable = bundle / "Contents/MacOS/OpenRC"
            pack = bundle / "Contents/Resources/OpenRC.pck"
            library = bundle / MAC_RECEIPT.NATIVE_LIBRARY
            descriptor = bundle / MAC_RECEIPT.NATIVE_DESCRIPTOR
            license_file = bundle / MAC_RECEIPT.NATIVE_LICENSE
            for path in (executable, pack, library, descriptor, license_file):
                path.parent.mkdir(parents=True, exist_ok=True)
            macho = struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(56)
            executable.write_bytes(macho)
            library.write_bytes(macho)
            pack.write_bytes(struct.pack("<4sIIIIIQQI", b"GDPC", 4, 4, 8, 0, 2, 0, 40, 1) + b"fixture data")
            descriptor.write_bytes(MAC_RECEIPT.NATIVE_DESCRIPTOR_TEXT.encode("utf-8"))
            license_file.write_bytes(b"godot-cpp license notice fixture\n")
            snapshot = root / "inputs.json"
            snapshot.write_bytes(b"release inputs")
            probe = root / "research/performance/session_probe.gd"
            probe.parent.mkdir(parents=True)
            probe.write_bytes(Path(baseline.__file__).with_name("session_probe.gd").read_bytes())
            source = {"commit": "a" * 40, "tree": "b" * 40, "worktree_sha256": "c" * 64}
            with patch.object(MAC_RECEIPT, "_source_snapshot", return_value=source):
                MAC_RECEIPT.create(bundle, snapshot, root)
            row = {"platform": "macos", "architecture": "arm64", "backend": "native",
                   "backend_version": "openrc-native-kernel-stage-v2", "abi_version": 2,
                   "qualification_scope": MAC_RECEIPT.NATIVE_SCOPE, "binary_sha256": _sha256_file(library),
                   "source_sha256": "1" * 64, "lock_sha256": "2" * 64, "engine_sha256": "3" * 64,
                   "engine_version": "fixture", "runtime_os_version": "27.0.1", "runtime_os_build": "26A434",
                   "mirrored_sources": {"app/physics/aero.gd": "4" * 64}, "verification": {"oracle": "fixture"}}
            manifest = {"format": MAC_RECEIPT.NATIVE_MANIFEST_FORMAT, "platform": "macos", "architecture": "arm64",
                        "engine_version": "fixture", "solver_sha256": "5" * 64,
                        "license_sha256": _sha256_file(license_file),
                        "native_receipt": {"format": "openrc-native-kernel-receipt", "backend": "native",
                            "backend_version": "openrc-native-kernel-stage-v2", "abi_version": 2,
                            "platforms": {"macos": row}},
                        "qualification_sources": {name: _sha256_file(probe) if name == "session_probe.gd" else "6" * 64
                                                  for name in MAC_RECEIPT.NATIVE_DIAGNOSTICS}}
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest))
            MAC_RECEIPT.create_native(bundle, manifest_path)
            reference, native = baseline.verify_macos_release_identities(executable)
            self.assertEqual(native["reference_receipt_sha256"], reference["receipt_sha256"])
            self.assertEqual(native["library_sha256"], _sha256_file(library))
            self.assertEqual(native["license_sha256"], _sha256_file(license_file))
            ref_report = mac_release_report("gdscript_reference", reference, native)
            native_report = mac_release_report("native", reference, native)
            self.assertTrue(reduce_backend_pair(ref_report, native_report, mac_reference_identity=reference,
                                                mac_native_identity=native)["comparable"])
            notice = license_file.read_bytes()
            for replacement in (None, b"changed notice\n"):
                if replacement is None:
                    license_file.unlink()
                else:
                    license_file.write_bytes(replacement)
                with self.assertRaises(ValueError):
                    baseline.verify_macos_release_identities(executable)
                license_file.write_bytes(notice)
            library.write_bytes(macho + b"modified")
            with self.assertRaises(ValueError):
                baseline.verify_macos_release_identities(executable)

    def test_distinct_identities_are_comparable_only_with_linked_verified_receipts(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-pair-") as directory:
            _exe, _probe, reference, native = mac_release_fixture(Path(directory))
            ref_report = mac_release_report("gdscript_reference", reference, native)
            native_report = mac_release_report("native", reference, native)
            self.assertEqual(validate_probe_report(native_report), [])
            self.assertFalse(reduce_backend_pair(ref_report, native_report)["comparable"])
            compare = lambda r, n, a=reference, b=native: reduce_backend_pair(
                r, n, mac_reference_identity=a, mac_native_identity=b)
            self.assertTrue(compare(ref_report, native_report)["comparable"])
            for field, value in (("binary_sha256", "0" * 64), ("backend_version", "other"), ("abi_version", 1)):
                with self.subTest(field=field):
                    changed = copy.deepcopy(native_report)
                    changed["backend"]["actual"][field] = value
                    self.assertFalse(compare(ref_report, changed)["comparable"])
            for field, value in (("solver_identity_kind", MAC_RECEIPT.KIND), ("solver_sha256", "0" * 64),
                                 ("experimental_native_macos", False)):
                with self.subTest(field=field):
                    changed = copy.deepcopy(native_report)
                    changed[field] = value
                    self.assertFalse(compare(ref_report, changed)["comparable"])
            changed = dict(native, reference_receipt_sha256="0" * 64)
            self.assertFalse(compare(ref_report, native_report, reference, changed)["comparable"])

    def test_probe_checks_both_receipts_each_time_and_rejects_tampering_or_fallback(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-probe-") as directory:
            root = Path(directory)
            executable, probe, reference, native = mac_release_fixture(root)
            output, log = root / "report.json", root / "run.log"
            marker = "NATIVE_QUALIFICATION mode=session verdict=pass\n"
            def run(candidate, backend="native", *, opt_in=True, native_identity=native,
                    reference_results=None, native_results=None, corrupt_while_parsing=False, corrupt_log=False):
                class Process:
                    returncode = 0
                    def __init__(self, command, **kwargs):
                        output.write_text(json.dumps(candidate))
                        kwargs["stdout"].write(marker)
                    def wait(self, timeout): return 0
                parser = baseline._parse_probe_bytes
                def parse_captured(raw):
                    if corrupt_while_parsing:
                        output.write_text('{"replaced": true}')
                    return parser(raw)
                scanner, original_log_hash = baseline._engine_error_lines, []
                def scan_captured(text):
                    if corrupt_log:
                        original_log_hash.append(_sha256_file(log))
                        log.write_text("log replaced during validation")
                    return scanner(text)
                with patch("subprocess.Popen", Process), \
                        patch.object(MAC_RECEIPT, "verify", side_effect=reference_results or [reference, reference]) as ref_verify, \
                        patch.object(MAC_RECEIPT, "verify_native", side_effect=native_results or [native, native]) as native_verify, \
                        patch.object(baseline, "_parse_probe_bytes", side_effect=parse_captured), \
                        patch.object(baseline, "_engine_error_lines", side_effect=scan_captured):
                    result = _run_probe(godot=executable, app_dir=root, probe=probe, output_json=output, log_path=log,
                        aircraft_id="jensen-das-ugly-stik-60", case_id="trim", observer=True, warmup_ticks=4,
                        sample_ticks=5, timeout=5, physics_backend=backend, native_source_sha256="c" * 64,
                        release_executable=True, executable_sha256=reference["executable_sha256"],
                        probe_sha256=reference["probe_sha256"], mac_identity=reference,
                        mac_native_identity=native_identity, experimental_native_macos=opt_in)
                    if original_log_hash:
                        self.assertEqual(result["log_sha256"], original_log_hash[0])
                    return result, ref_verify.call_count, native_verify.call_count
            for backend in ("gdscript_reference", "native"):
                report = mac_release_report(backend, reference, native)
                result, reference_calls, native_calls = run(report, backend)
                self.assertTrue(result["accepted"], result["failures"])
                self.assertEqual((reference_calls, native_calls), (2, 2))
                self.assertIn("--native-qualification=session", result["command"])
                self.assertIn("--experimental-native-macos=true", result["command"])
                for forbidden in ("--path", "--script", "--main-pack"):
                    self.assertNotIn(forbidden, result["command"])
            report = mac_release_report("native", reference, native)
            self.assertFalse(run(report, opt_in=False)[0]["accepted"])
            self.assertFalse(run(report, native_identity=None)[0]["accepted"])
            raced = run(report, corrupt_while_parsing=True)[0]
            self.assertFalse(raced["accepted"])
            self.assertEqual(raced["report_sha256"], hashlib.sha256(json.dumps(report).encode("utf-8")).hexdigest())
            self.assertTrue(any("changed during validation" in reason for reason in raced["failures"]))
            raced_log = run(report, corrupt_log=True)[0]
            self.assertFalse(raced_log["accepted"])
            self.assertTrue(any("changed during validation" in reason for reason in raced_log["failures"]))
            self.assertFalse(run(report, native_results=[native, dict(native, library_sha256="0" * 64)])[0]["accepted"])
            self.assertFalse(run(report, reference_results=[reference, dict(reference, pack_sha256="0" * 64)])[0]["accepted"])
            for change in (lambda r: r["backend"]["actual"].update(backend="gdscript_reference"),
                           lambda r: r["backend"]["actual"].update(binary_sha256="0" * 64),
                           lambda r: r["backend"]["native_stats"].update(stage_calls=0),
                           lambda r: r["backend"]["native_stats"].update(context_calls=0),
                           lambda r: r["backend"]["actual"].update(source_sha256="0" * 64),
                           lambda r: r["machine"].update(architecture="x86_64"),
                           lambda r: r.update(experimental_native_macos=False)):
                changed = copy.deepcopy(report)
                change(changed)
                self.assertFalse(run(changed)[0]["accepted"])

    def test_five_pair_campaign_and_rereader_refuse_receipt_or_report_drift(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-campaign-") as directory:
            root = Path(directory)
            executable, probe, reference, native = mac_release_fixture(root)
            output = root / "campaign"
            launches = []
            class Process:
                returncode = 0
                def __init__(self, command, **kwargs):
                    launches.append(command)
                    output_arg = next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output="))
                    backend = next(arg.removeprefix("--physics-backend=") for arg in command
                                   if arg.startswith("--physics-backend="))
                    Path(output_arg).write_text(json.dumps(mac_release_report(backend, reference, native)))
                    kwargs["stdout"].write("NATIVE_QUALIFICATION mode=session verdict=pass\n")
                def wait(self, timeout): return 0
            engine = {"path": str(executable), "sha256": reference["executable_sha256"],
                      "runtime_binary_sha256": reference["executable_sha256"]}
            args = ["--godot", str(executable), "--out", str(output), "--release-executable", "--compare-backends",
                    "--experimental-native-macos", "--aircraft", "jensen-das-ugly-stik-60", "--case", "trim",
                    "--warmup-ticks", "4", "--sample-ticks", "5", "--repeats", "5"]
            with patch.object(baseline, "capture_workspace_identity", return_value={}), \
                 patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
                 patch.object(baseline, "capture_mac_release_source", return_value=mac_release_source_fixture(reference)), \
                 patch.object(baseline, "inspect_godot", return_value=engine), \
                 patch.object(baseline, "native_source_digest", return_value="c" * 64), \
                 patch.object(baseline, "app_source_digest", return_value="app-digest"), \
                 patch.object(MAC_RECEIPT, "verify", return_value=reference) as ref_verify, \
                 patch.object(MAC_RECEIPT, "verify_native", return_value=native) as native_verify, \
                 patch("subprocess.Popen", Process):
                self.assertEqual(baseline.main(args), 0)
                self.assertEqual(len(launches), 10)
                self.assertEqual((ref_verify.call_count, native_verify.call_count), (22, 22))
                campaign_path = output / "session_baseline.json"
                campaign, rows = baseline._campaign_runs(campaign_path)
                self.assertEqual(len(rows), 5)
                self.assertTrue(campaign["complete"])
                self.assertNotIn("mac_source_install", campaign["metadata"])
                self.assertEqual(campaign["metadata"]["mac_release_source"]["before"],
                                 campaign["metadata"]["mac_release_source"]["after"])
                self.assertEqual(campaign["pairs"][0]["backend_order"], ["reference", "native"])
                self.assertEqual(campaign["pairs"][1]["backend_order"], ["native", "reference"])
                original = copy.deepcopy(campaign)
                native_entry = campaign["pairs"][0]["runs"]["native"]
                native_path = output / native_entry["report_relative_path"]
                original_raw = native_path.read_text()
                changed = json.loads(original_raw)
                changed["backend"]["actual"]["binary_sha256"] = "0" * 64
                native_path.write_text(json.dumps(changed))
                native_entry["report_sha256"] = _sha256_file(native_path)
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "not comparable"):
                    baseline._campaign_runs(campaign_path)
                native_path.write_text(original_raw)
                campaign = copy.deepcopy(original)
                campaign["metadata"]["mac_native_bundle"]["reference_receipt_sha256"] = "0" * 64
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "invalid Mac release receipt"):
                    baseline._campaign_runs(campaign_path)
                campaign = copy.deepcopy(original)
                campaign["metadata"]["mac_release_source"]["after"]["worktree_sha256"] = "0" * 64
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "invalid Mac release receipt"):
                    baseline._campaign_runs(campaign_path)
                campaign = copy.deepcopy(original)
                campaign["pairs"][0]["runs"]["native"]["command"].append("--script=other.gd")
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "invalid Mac release probe command"):
                    baseline._campaign_runs(campaign_path)
                campaign = copy.deepcopy(original)
                campaign["metadata"]["mac_source_install"] = {"binary_sha256": native["library_sha256"]}
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "invalid Mac release receipt"):
                    baseline._campaign_runs(campaign_path)
                campaign = copy.deepcopy(original)
                entry = campaign["pairs"][0]["runs"]["native"]
                log_path = output / entry["log_relative_path"]
                original_log = log_path.read_text()
                log_path.write_text("missing completion marker\n")
                entry["log_sha256"] = _sha256_file(log_path)
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "clean completion marker"):
                    baseline._campaign_runs(campaign_path)
                log_path.write_text(original_log)
                campaign_path.write_text(json.dumps(original))
                self.assertEqual(baseline.compare_campaigns(campaign_path, campaign_path, root / "same-bundle-comparison"), 0)
                with patch.object(MAC_RECEIPT, "verify_native", return_value=dict(native, library_sha256="0" * 64)):
                    with self.assertRaisesRegex(ValueError, "differs from retained evidence"):
                        baseline._campaign_runs(campaign_path)
                original["configuration"]["experimental_native_macos"] = False
                campaign_path.write_text(json.dumps(original))
                with self.assertRaisesRegex(ValueError, "explicit opt-in"):
                    baseline._campaign_runs(campaign_path)

    def test_native_release_refuses_missing_opt_in_wrong_host_and_end_of_campaign_drift(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-admission-") as directory:
            root = Path(directory)
            executable, _probe, reference, native = mac_release_fixture(root)
            engine = {"path": str(executable), "sha256": reference["executable_sha256"],
                      "runtime_binary_sha256": reference["executable_sha256"]}
            produced_logs = []
            mutate_earlier_log = [False]
            def fake_probe(**kwargs):
                if mutate_earlier_log[0] and produced_logs:
                    produced_logs[0].write_text("changed after the earlier probe\n")
                report = mac_release_report(kwargs["physics_backend"], reference, native)
                kwargs["output_json"].write_text(json.dumps(report))
                kwargs["log_path"].write_text("NATIVE_QUALIFICATION mode=session verdict=pass\n")
                produced_logs.append(kwargs["log_path"])
                return {"accepted": True, "report": report, "failures": [], "validation_errors": [],
                        "report_file": str(kwargs["output_json"]), "log": str(kwargs["log_path"]),
                        "report_sha256": _sha256_file(kwargs["output_json"]), "log_sha256": _sha256_file(kwargs["log_path"])}
            def args(name, opt_in):
                result = ["--godot", str(executable), "--out", str(root / name), "--release-executable",
                          "--compare-backends", "--aircraft", "jensen-das-ugly-stik-60", "--case", "trim",
                          "--warmup-ticks", "4", "--sample-ticks", "5", "--repeats", "1"]
                return result + (["--experimental-native-macos"] if opt_in else [])
            with patch.object(baseline, "capture_workspace_identity", return_value={}), \
                 patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}) as system, \
                 patch.object(baseline, "capture_mac_release_source", return_value=mac_release_source_fixture(reference)) as source, \
                 patch.object(baseline, "inspect_godot", return_value=engine), \
                 patch.object(baseline, "native_source_digest", return_value="c" * 64), \
                 patch.object(baseline, "app_source_digest", return_value="app-digest"), \
                 patch.object(MAC_RECEIPT, "verify", return_value=reference), \
                 patch.object(MAC_RECEIPT, "verify_native", side_effect=[native, dict(native, library_sha256="0" * 64)]) as verify, \
                 patch.object(baseline, "_run_probe", side_effect=fake_probe) as launch:
                self.assertEqual(baseline.main(args("no-opt-in", False)), 1)
                launch.assert_not_called()
                verify.assert_not_called()
                system.return_value = {"system": "Darwin", "machine": "x86_64"}
                self.assertEqual(baseline.main(args("wrong-host", True)), 1)
                launch.assert_not_called()
                verify.assert_not_called()
                system.return_value = {"system": "Darwin", "machine": "arm64"}
                source.return_value = dict(mac_release_source_fixture(reference), worktree_sha256="0" * 64)
                verify.side_effect = [native]
                self.assertEqual(baseline.main(args("changed-source", True)), 1)
                launch.assert_not_called()
                verify.reset_mock()
                verify.side_effect = [native, dict(native, library_sha256="0" * 64)]
                source.return_value = mac_release_source_fixture(reference)
                self.assertEqual(baseline.main(args("final-drift", True)), 1)
                self.assertEqual(launch.call_count, 2)
                report = json.loads((root / "final-drift/session_baseline.json").read_text())
                self.assertFalse(report["complete"])
                self.assertTrue(any("bundle changed during the campaign" in reason for reason in report["failures"]))
                verify.side_effect = [native, native]
                source.side_effect = [mac_release_source_fixture(reference),
                                      dict(mac_release_source_fixture(reference), worktree_sha256="0" * 64)]
                produced_logs.clear()
                self.assertEqual(baseline.main(args("source-drift", True)), 1)
                report = json.loads((root / "source-drift/session_baseline.json").read_text())
                self.assertFalse(report["complete"])
                self.assertTrue(any("Git/worktree source changed" in reason for reason in report["failures"]))
                source.side_effect = None
                source.return_value = mac_release_source_fixture(reference)
                verify.side_effect = [native, native]
                produced_logs.clear()
                mutate_earlier_log[0] = True
                self.assertEqual(baseline.main(args("evidence-drift", True)), 1)
                report = json.loads((root / "evidence-drift/session_baseline.json").read_text())
                self.assertFalse(report["complete"])
                self.assertTrue(any("probe report or log changed" in reason for reason in report["failures"]))
                verify.side_effect = [native, native]
                produced_logs.clear()
                mutate_earlier_log[0] = False
                real_safe_view = baseline._safe_report_view
                mutated = [False]
                def mutate_between_guard_and_record(run):
                    view = real_safe_view(run)
                    if not mutated[0]:
                        Path(run["report_file"]).write_text('{"changed": true}')
                        mutated[0] = True
                    return view
                with patch.object(baseline, "_safe_report_view", side_effect=mutate_between_guard_and_record):
                    self.assertEqual(baseline.main(args("guard-race", True)), 1)
                report = json.loads((root / "guard-race/session_baseline.json").read_text())
                self.assertFalse(report["complete"])
                self.assertTrue(any("probe report or log changed" in reason for reason in report["failures"]))

    def test_different_mac_release_bundles_are_explicitly_not_comparable(self):
        with tempfile.TemporaryDirectory(prefix="mac-release-cross-bundle-") as directory:
            root = Path(directory)
            _exe, _probe, reference, native = mac_release_fixture(root)
            before = {"metadata": {"mac_native_bundle": native, "mac_reference_bundle": reference}}
            after = copy.deepcopy(before)
            after["metadata"]["mac_native_bundle"]["sha256"] = "0" * 64
            with patch.object(baseline, "_campaign_runs", side_effect=[(before, {}), (after, {})]):
                self.assertEqual(baseline.compare_campaigns(root / "one.json", root / "two.json", root / "out"), 1)
            report = json.loads((root / "out/session_comparison.json").read_text())
            self.assertFalse(report["complete"])
            self.assertEqual(report["pairs"], [])
            self.assertTrue(any("cannot compare different bundles" in failure for failure in report["failures"]))

class IdenticalCampaignTests(unittest.TestCase):
    def test_comparison_modes_are_mutually_exclusive(self):
        parser = baseline.build_parser()
        for options in (("--compare-identical", "--compare-backends"),
                        ("--compare-identical", "--compare-campaigns", "one", "two")):
            with self.subTest(options=options), patch.object(sys, "stderr"):
                with self.assertRaises(SystemExit):
                    parser.parse_args(["--out", "output", *options])
        self.assertTrue(parser.parse_args(["--out", "output", "--compare-identical",
                                           "--physics-backend", "native"]).compare_identical)

    def source_campaign(self, root: Path, *, problem: str = "", identical: bool = True,
                        backend: str = "native", opt_in: bool = True):
        app, executable, library, _receipt = PreparedMacSourceTests._installation(self, root)
        (app / "project.godot").write_text("config_version=5\n")
        binary_sha = _sha256_file(library)
        proof = {"canonical_manifest_sha256": "a" * 64, "executed_project_content_sha256": "b" * 64,
                 "checked_files": 2, "excluded_generated_suffixes": [".import", ".uid"]}
        final_proof = dict(proof, checked_files=3) if problem == "project-drift" else proof
        validator = SimpleNamespace(validate_project=unittest.mock.Mock(side_effect=[proof, final_proof]))
        launches, outputs = [], []
        class Process:
            returncode = 0
            def __init__(self, command, **_kwargs):
                launches.append(command)
                output = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
                if problem == "evidence-drift" and outputs:
                    outputs[0].write_text('{"changed": true}')
                outputs.append(output)
                backend = next(arg.removeprefix("--physics-backend=") for arg in command if arg.startswith("--physics-backend="))
                observer = "--observer=on" in command
                report = valid_current_report(backend, observer)
                report["machine"].update(os="macOS", architecture="arm64")
                report.update(experimental_native_macos=opt_in, template_release=False, solver_identity_kind="source-tree-v1",
                              probe_sha256=_sha256_file(Path(baseline.__file__).with_name("session_probe.gd")))
                if backend == "native":
                    report["backend"]["actual"]["binary_sha256"] = binary_sha
                if output.stem.endswith("-b"):
                    report["input_usec"] = [item + 1 for item in report["input_usec"]]
                    report["tick_usec"] = [item + 1 for item in report["tick_usec"]]
                    if problem == "fingerprint":
                        report["fingerprint"] = "0" * 64
                    if problem == "fallback":
                        report["backend"]["actual"] = {"backend": "gdscript_reference"}
                    if problem == "native-coverage":
                        report["backend"]["native_stats"]["stage_calls"] = 0
                output.write_text(json.dumps(report))
                self.change_library = problem == "library-drift" and len(launches) == 2
            def wait(self, timeout):
                if self.change_library:
                    library.write_bytes(b"changed during the probe")
                return 0
        output = root / "campaign"
        args = ["--godot", str(executable), "--project", str(app), "--out", str(output),
                "--physics-backend", backend, "--aircraft", "jensen-das-ugly-stik-60",
                "--case", "trim", "--warmup-ticks", "4", "--sample-ticks", "5", "--repeats", "2"]
        if opt_in:
            args.append("--experimental-native-macos")
        if identical:
            args.append("--compare-identical")
        with patch.object(baseline, "capture_workspace_identity", return_value={}), \
             patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
             patch.object(baseline, "inspect_godot", return_value={"sha256": _sha256_file(executable)}), \
             patch.object(baseline, "native_source_digest", return_value="c" * 64,
                          side_effect=["c" * 64, "0" * 64] if problem == "source-drift" else None), \
             patch.object(baseline, "app_source_digest", return_value="app-digest"), \
             patch.object(baseline, "load_project_validator", return_value=validator), patch("subprocess.Popen", Process):
            code = baseline.main(args)
        name = "session_identical.json" if identical else "session_baseline.json"
        return code, json.loads((output / name).read_text()), launches, output, proof

    def test_prepared_native_source_roles_preserve_checks_and_are_not_backend_campaigns(self):
        with tempfile.TemporaryDirectory(prefix="session-identical-source-") as directory:
            code, report, launches, output, proof = self.source_campaign(Path(directory))
            self.assertEqual(code, 0, report["failures"])
            self.assertEqual(report["format"], baseline.IDENTICAL_FORMAT)
            self.assertEqual(report["configuration"]["pair_type"], "identical")
            self.assertEqual(report["metadata"]["project"]["inventory_before"], proof)
            self.assertEqual(report["metadata"]["project"]["inventory_after"], proof)
            self.assertEqual([pair["role_order"] for pair in report["pairs"]], [["a", "b"], ["b", "a"]])
            self.assertEqual(len(launches), 4)
            self.assertTrue(all("--physics-backend=native" in command and "--observer=on" in command
                                and "--experimental-native-macos=true" in command for command in launches))
            for pair in report["pairs"]:
                self.assertTrue(pair["comparable"])
                self.assertEqual(pair["a_callback_mean_usec_per_tick"], 5)
                self.assertEqual(pair["b_callback_mean_usec_per_tick"], 6)
                self.assertEqual(pair["a_over_b_callback_mean_ratio"], 5 / 6)
                self.assertEqual(pair["absolute_callback_mean_difference_usec_per_tick"], 1)
                self.assertAlmostEqual(pair["absolute_ratio_deviation_percent"], 100 / 6)
                self.assertEqual(pair["runs"]["a"]["backend"]["actual"], pair["runs"]["b"]["backend"]["actual"])
            self.assertFalse((output / "session_baseline.json").exists())
            with self.assertRaisesRegex(ValueError, "campaign is not complete"):
                baseline._campaign_runs(output / "session_identical.json")
            self.assertEqual(baseline.compare_campaigns(output / "session_identical.json",
                                                        output / "session_identical.json", output.parent / "compare"), 1)

    def test_source_failures_are_not_counted_as_identical_pairs(self):
        for problem in ("fingerprint", "fallback", "native-coverage", "project-drift", "library-drift",
                        "source-drift", "evidence-drift"):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory(prefix="session-identical-failed-") as directory:
                code, report, _launches, _output, _proof = self.source_campaign(Path(directory), problem=problem)
                self.assertEqual(code, 1)
                self.assertFalse(report["complete"])
                self.assertTrue(report["failures"])

    def test_reference_identical_uses_selected_backend_without_mac_opt_in(self):
        with tempfile.TemporaryDirectory(prefix="session-identical-reference-") as directory:
            code, report, launches, _output, _proof = self.source_campaign(
                Path(directory), backend="gdscript_reference", opt_in=False)
            self.assertEqual(code, 0, report["failures"])
            self.assertFalse(report["configuration"]["experimental_native_macos"])
            self.assertTrue(all("--physics-backend=gdscript_reference" in command and "--observer=on" in command
                                and "--experimental-native-macos=true" not in command for command in launches))
            self.assertEqual([pair["a_over_b_callback_mean_ratio"] for pair in report["pairs"]], [5 / 6, 5 / 6])

    def test_existing_observer_campaign_format_is_unchanged(self):
        with tempfile.TemporaryDirectory(prefix="session-observer-default-") as directory:
            code, report, launches, output, _proof = self.source_campaign(Path(directory), identical=False)
            self.assertEqual(code, 0, report["failures"])
            self.assertEqual(report["format"], baseline.BASELINE_FORMAT)
            self.assertEqual(report["configuration"]["pair_type"], "observer")
            self.assertEqual([pair["observer_order"] for pair in report["pairs"]], [["on", "off"], ["off", "on"]])
            self.assertEqual(sum("--observer=on" in command for command in launches), 2)
            self.assertFalse((output / "session_identical.json").exists())
            self.assertNotIn("scope", report)

    def release_campaign(self, root: Path, problem: str, *, opt_in: bool = True):
        executable, _probe, reference, native = mac_release_fixture(root)
        engine = {"path": str(executable), "sha256": reference["executable_sha256"],
                  "runtime_binary_sha256": reference["executable_sha256"]}
        source = mac_release_source_fixture(reference)
        launches, outputs = [], []
        class Process:
            returncode = 0
            def __init__(self, command, **kwargs):
                launches.append(command)
                output = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
                if problem == "evidence-drift" and outputs:
                    outputs[0].write_text('{"changed": true}')
                outputs.append(output)
                report = mac_release_report("native", reference, native)
                if len(launches) == 2 and problem == "fallback":
                    report["backend"]["actual"] = {"backend": "gdscript_reference"}
                if len(launches) == 2 and problem == "fingerprint":
                    report["fingerprint"] = "0" * 64
                output.write_text(json.dumps(report))
                kwargs["stdout"].write("NATIVE_QUALIFICATION mode=session verdict=pass\n")
            def wait(self, timeout): return 0
        output = root / "campaign"
        args = ["--godot", str(executable), "--out", str(output), "--release-executable", "--compare-identical",
                "--physics-backend", "native", "--aircraft", "jensen-das-ugly-stik-60",
                "--case", "trim", "--warmup-ticks", "4", "--sample-ticks", "5", "--repeats", "1"]
        if opt_in:
            args.append("--experimental-native-macos")
        source_values = [source, dict(source, worktree_sha256="0" * 64)] if problem == "source-drift" else [source, source]
        native_values = [native] * 5 + [dict(native, library_sha256="0" * 64)] if problem == "bundle-drift" else None
        with patch.object(baseline, "capture_workspace_identity", return_value={}), \
             patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
             patch.object(baseline, "capture_mac_release_source", side_effect=source_values), \
             patch.object(baseline, "inspect_godot", return_value=engine), \
             patch.object(baseline, "native_source_digest", return_value="c" * 64), \
             patch.object(baseline, "app_source_digest", return_value="app-digest"), \
             patch.object(MAC_RECEIPT, "verify", return_value=reference) as verify, \
             patch.object(MAC_RECEIPT, "verify_native", side_effect=native_values, return_value=native) as verify_native, \
             patch("subprocess.Popen", Process):
            code = baseline.main(args)
            calls = (verify.call_count, verify_native.call_count)
        return code, json.loads((output / "session_identical.json").read_text()), launches, calls

    def test_release_native_identical_uses_fixed_host_and_both_verified_receipts(self):
        with tempfile.TemporaryDirectory(prefix="session-identical-release-") as directory:
            code, report, launches, calls = self.release_campaign(Path(directory), "")
            self.assertEqual(code, 0, report["failures"])
            self.assertEqual(report["format"], baseline.IDENTICAL_FORMAT)
            self.assertEqual(calls, (6, 6))
            self.assertEqual(len(launches), 2)
            for command in launches:
                self.assertIn("--native-qualification=session", command)
                self.assertIn("--physics-backend=native", command)
                self.assertIn("--observer=on", command)
                self.assertIn("--experimental-native-macos=true", command)
                self.assertFalse(any(option in command for option in ("--path", "--script", "--main-pack")))
            self.assertEqual(report["pairs"][0]["a_over_b_callback_mean_ratio"], 1)
            self.assertEqual(report["pairs"][0]["absolute_callback_mean_difference_usec_per_tick"], 0)

    def test_reference_release_identical_remains_reference_only(self):
        with tempfile.TemporaryDirectory(prefix="session-identical-reference-release-") as directory:
            root = Path(directory)
            executable, _probe, reference, native = mac_release_fixture(root)
            reference_launch = {**reference, "identities": {"arm64": reference["sha256"]}}
            engine = {"path": str(executable), "sha256": reference["executable_sha256"],
                      "runtime_binary_sha256": reference["executable_sha256"]}
            launches = []
            class Process:
                returncode = 0
                def __init__(self, command, **kwargs):
                    launches.append(command)
                    output = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
                    report = mac_release_report("gdscript_reference", reference, native)
                    report["experimental_native_macos"] = False
                    output.write_text(json.dumps(report))
                    kwargs["stdout"].write("NATIVE_QUALIFICATION mode=session verdict=pass\n")
                def wait(self, timeout): return 0
            output = root / "campaign"
            args = ["--godot", str(executable), "--out", str(output), "--release-executable", "--compare-identical",
                    "--aircraft", "jensen-das-ugly-stik-60", "--case", "trim", "--warmup-ticks", "4",
                    "--sample-ticks", "5", "--repeats", "1"]
            with patch.object(baseline, "capture_workspace_identity", return_value={}), \
                 patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
                 patch.object(baseline, "inspect_godot", return_value=engine), \
                 patch.object(baseline, "native_source_digest", return_value="c" * 64), \
                 patch.object(baseline, "app_source_digest", return_value="app-digest"), \
                 patch.object(MAC_RECEIPT, "verify_for_launch", return_value=reference_launch) as verify, \
                 patch.object(MAC_RECEIPT, "verify_native") as verify_native, patch("subprocess.Popen", Process):
                self.assertEqual(baseline.main(args), 0)
                self.assertEqual(verify.call_count, 6)
                verify_native.assert_not_called()
            report = json.loads((output / "session_identical.json").read_text())
            self.assertTrue(report["complete"], report["failures"])
            self.assertTrue(all("--physics-backend=gdscript_reference" in command and "--observer=on" in command
                                and "--experimental-native-macos=true" not in command for command in launches))

    def test_release_drift_fallback_or_different_trajectory_fails(self):
        for problem in ("fallback", "fingerprint", "source-drift", "bundle-drift", "evidence-drift"):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory(prefix="session-identical-release-failed-") as directory:
                code, report, _launches, _calls = self.release_campaign(Path(directory), problem)
                self.assertEqual(code, 1)
                self.assertFalse(report["complete"])
                self.assertTrue(report["failures"])

    def test_native_release_without_opt_in_never_launches(self):
        with tempfile.TemporaryDirectory(prefix="session-identical-release-no-opt-in-") as directory:
            code, report, launches, calls = self.release_campaign(Path(directory), "", opt_in=False)
            self.assertEqual(code, 1)
            self.assertFalse(report["complete"])
            self.assertEqual(report["format"], baseline.IDENTICAL_FORMAT)
            self.assertEqual(launches, [])
            self.assertEqual(calls, (0, 0))


class BatteryModeTests(unittest.TestCase):
    @staticmethod
    def report(backend: str, mode: str, *, data_sha: str = "f" * 64) -> dict:
        report = valid_current_report(backend)
        report["aircraft_id"] = "stik-electric-6s"
        report["aircraft_sha256"] = data_sha
        report.update(template_release=False, solver_identity_kind="source-tree-v1")
        report["battery"] = {"mode": mode,
            "data_path": "res://data/aircraft/battery/stik_electric_6s_pack.json" if mode == "pack"
                         else "res://data/aircraft/stik_electric_6s.json",
            "data_sha256": data_sha, "dynamic": mode == "pack", "pack": mode == "pack"}
        return report

    def test_explicit_data_identity_and_actual_session_mode_are_required(self):
        for mode in ("ideal", "pack"):
            report = self.report("native", mode)
            self.assertEqual(validate_probe_report(report, expected={"battery": mode}), [])
            self.assertTrue(validate_probe_report(report, expected={"battery": None}))
            for change in (lambda b: b.update(data_sha256="0" * 64),
                           lambda b: b.update(data_path="res://data/aircraft/../outside.json"),
                           lambda b: b.update(dynamic=1), lambda b: b.update(pack=not b["pack"]),
                           lambda b: b.update(mode="unknown"), lambda b: b.update(extra=True)):
                changed = copy.deepcopy(report)
                change(changed["battery"])
                with self.subTest(mode=mode, changed=changed["battery"]):
                    self.assertTrue(validate_probe_report(changed, expected={"battery": mode}))
        pack = self.report("native", "pack")
        pack["battery"]["dynamic"] = False
        self.assertTrue(validate_probe_report(pack))
        legacy = valid_current_report()
        self.assertEqual(validate_probe_report(legacy, expected={"battery": None}), [])
        self.assertTrue(validate_probe_report(legacy, expected={"battery": "pack"}))

    def test_pair_reducers_do_not_mix_pack_ideal_or_data_paths(self):
        reference, native = self.report("gdscript_reference", "pack"), self.report("native", "pack")
        self.assertTrue(reduce_backend_pair(reference, native)["comparable"])
        self.assertTrue(baseline.reduce_identical_pair(native, copy.deepcopy(native), "native")["comparable"])
        changed = copy.deepcopy(native)
        changed["battery"]["data_path"] = "res://data/aircraft/battery/other.json"
        self.assertEqual(validate_probe_report(changed), [])
        self.assertFalse(reduce_backend_pair(reference, changed)["comparable"])
        self.assertFalse(baseline.reduce_identical_pair(native, changed, "native")["comparable"])
        self.assertFalse(reduce_backend_pair(reference, self.report("native", "ideal"))["comparable"])
        missing = copy.deepcopy(native)
        del missing["battery"]
        self.assertFalse(reduce_backend_pair(reference, missing)["comparable"])

    def source_campaign(self, root: Path, mode: str | None, *, identical: bool = False,
                        mismatch: bool = False, file_drift: bool = False, trim_profile: str | None = None,
                        bad_trim: str = ""):
        app, executable, library, _receipt = PreparedMacSourceTests._installation(self, root)
        (app / "project.godot").write_text("config_version=5\n")
        data_dir = app / "data/aircraft/battery"
        data_dir.mkdir(parents=True)
        data = data_dir / "stik_electric_6s_pack.json"
        data.write_bytes(b"finite-pack aircraft data")
        source_identity = mac_source_install_identity(app, _sha256_file(executable), "c" * 64)
        proof = {"canonical_manifest_sha256": "a" * 64, "executed_project_content_sha256": "b" * 64,
                 "checked_files": 2, "excluded_generated_suffixes": [".import", ".uid"]}
        validator = SimpleNamespace(validate_project=unittest.mock.Mock(side_effect=[proof, proof]))
        commands = []
        class Process:
            returncode = 0
            def __init__(self, command, **_kwargs):
                commands.append(command)
                output = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
                backend = next(arg.removeprefix("--physics-backend=") for arg in command if arg.startswith("--physics-backend="))
                actual_mode = "ideal" if mismatch and backend == "native" else mode
                data_sha = "0" * 64 if file_drift and backend == "native" else _sha256_file(data)
                report = BatteryModeTests.report(backend, actual_mode or "ideal", data_sha=data_sha)
                if mode is None:
                    del report["battery"]
                elif actual_mode == "ideal":
                    report["battery"]["data_path"] = "res://data/aircraft/battery/stik_electric_6s_pack.json"
                report["machine"].update(os="macOS", architecture="arm64")
                report["experimental_native_macos"] = True
                if backend == "native":
                    report["backend"]["actual"]["binary_sha256"] = source_identity["binary_sha256"]
                if trim_profile is not None:
                    report["trim_profile"] = trim_profile
                    if trim_profile == "production":
                        report["trim_start"] = TrimProfileTests.start(backend)
                        if backend == "native" and bad_trim == "guard":
                            report["trim_start"]["backend_domain_guard"] = False
                        if backend == "native" and bad_trim == "drift":
                            report["trim_start"]["start_sha256"] = "8" * 64
                output.write_text(json.dumps(report))
            def wait(self, timeout): return 0
        output = root / "campaign"
        args = ["--godot", str(executable), "--project", str(app), "--out", str(output),
                "--aircraft", "stik-electric-6s", "--case", "trim", "--warmup-ticks", "4", "--sample-ticks", "5",
                "--repeats", "1", "--experimental-native-macos", "--compare-identical" if identical else "--compare-backends"]
        if identical:
            args += ["--physics-backend", "native"]
        if mode is not None:
            args += ["--battery", mode]
        if trim_profile is not None:
            args += ["--trim-profile", trim_profile]
        with patch.object(baseline, "capture_workspace_identity", return_value={}), \
             patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
             patch.object(baseline, "inspect_godot", return_value={"sha256": _sha256_file(executable)}), \
             patch.object(baseline, "native_source_digest", return_value="c" * 64), \
             patch.object(baseline, "app_source_digest", return_value="app-digest"), \
             patch.object(baseline, "load_project_validator", return_value=validator), patch("subprocess.Popen", Process):
            code = baseline.main(args)
        name = "session_identical.json" if identical else "session_baseline.json"
        return code, json.loads((output / name).read_text()), commands, output

    def test_source_campaign_forwards_battery_and_rereader_rejects_downgrade(self):
        with tempfile.TemporaryDirectory(prefix="session-battery-source-") as directory:
            code, campaign, commands, output = self.source_campaign(Path(directory), "pack")
            self.assertEqual(code, 0, campaign["failures"])
            self.assertEqual(campaign["configuration"]["battery"], "pack")
            self.assertTrue(all("--battery=pack" in command for command in commands))
            for item in campaign["pairs"][0]["runs"].values():
                self.assertTrue(item["battery"]["dynamic"])
                self.assertTrue(item["battery"]["pack"])
            campaign_path = output / "session_baseline.json"
            _loaded, rows = baseline._campaign_runs(campaign_path)
            self.assertEqual(len(rows), 1)
            campaign["configuration"]["battery"] = "ideal"
            campaign_path.write_text(json.dumps(campaign))
            with self.assertRaisesRegex(ValueError, "requested battery mode"):
                baseline._campaign_runs(campaign_path)
        with tempfile.TemporaryDirectory(prefix="session-battery-identical-") as directory:
            code, campaign, commands, _output = self.source_campaign(Path(directory), "pack", identical=True)
            self.assertEqual(code, 0, campaign["failures"])
            self.assertTrue(all("--battery=pack" in command for command in commands))
            self.assertEqual(campaign["configuration"]["battery"], "pack")
        with tempfile.TemporaryDirectory(prefix="session-battery-default-") as directory:
            code, campaign, commands, _output = self.source_campaign(Path(directory), None)
            self.assertEqual(code, 0, campaign["failures"])
            self.assertNotIn("battery", campaign["configuration"])
            self.assertTrue(all(not any(arg.startswith("--battery=") for arg in command) for command in commands))

    def test_wrong_runtime_battery_fails_the_campaign(self):
        with tempfile.TemporaryDirectory(prefix="session-battery-fallback-") as directory:
            code, campaign, _commands, _output = self.source_campaign(Path(directory), "pack", mismatch=True)
            self.assertEqual(code, 1)
            self.assertFalse(campaign["complete"])
            self.assertTrue(any("battery mode does not match requested run" in item for item in campaign["failures"]))
        with tempfile.TemporaryDirectory(prefix="session-battery-data-drift-") as directory:
            code, campaign, _commands, _output = self.source_campaign(Path(directory), "pack", file_drift=True)
            self.assertEqual(code, 1)
            self.assertTrue(any("aircraft data differs from the measured project" in item for item in campaign["failures"]))

    def test_release_pair_rereader_requires_battery_in_exact_command(self):
        with tempfile.TemporaryDirectory(prefix="session-battery-release-") as directory:
            root = Path(directory)
            executable, _probe, reference, native = mac_release_fixture(root)
            engine = {"path": str(executable), "sha256": reference["executable_sha256"],
                      "runtime_binary_sha256": reference["executable_sha256"]}
            commands = []
            class Process:
                returncode = 0
                def __init__(self, command, **kwargs):
                    commands.append(command)
                    output = Path(next(arg.removeprefix("--output=") for arg in command if arg.startswith("--output=")))
                    backend = next(arg.removeprefix("--physics-backend=") for arg in command if arg.startswith("--physics-backend="))
                    report = mac_release_report(backend, reference, native)
                    report["aircraft_id"] = "stik-electric-6s"
                    report["battery"] = {"mode": "pack", "data_path": "res://data/aircraft/battery/stik_electric_6s_pack.json",
                                         "data_sha256": report["aircraft_sha256"], "dynamic": True, "pack": True}
                    output.write_text(json.dumps(report))
                    kwargs["stdout"].write("NATIVE_QUALIFICATION mode=session verdict=pass\n")
                def wait(self, timeout): return 0
            output = root / "campaign"
            args = ["--godot", str(executable), "--out", str(output), "--release-executable", "--compare-backends",
                    "--experimental-native-macos", "--aircraft", "stik-electric-6s", "--battery", "pack", "--case", "trim",
                    "--warmup-ticks", "4", "--sample-ticks", "5", "--repeats", "1"]
            with patch.object(baseline, "capture_workspace_identity", return_value={}), \
                 patch.object(baseline, "capture_system_identity", return_value={"system": "Darwin", "machine": "arm64"}), \
                 patch.object(baseline, "capture_mac_release_source", return_value=mac_release_source_fixture(reference)), \
                 patch.object(baseline, "inspect_godot", return_value=engine), \
                 patch.object(baseline, "native_source_digest", return_value="c" * 64), \
                 patch.object(baseline, "app_source_digest", return_value="app-digest"), \
                 patch.object(MAC_RECEIPT, "verify", return_value=reference), \
                 patch.object(MAC_RECEIPT, "verify_native", return_value=native), patch("subprocess.Popen", Process):
                self.assertEqual(baseline.main(args), 0)
                campaign_path = output / "session_baseline.json"
                campaign, _rows = baseline._campaign_runs(campaign_path)
                self.assertTrue(all("--battery=pack" in command for command in commands))
                campaign["pairs"][0]["runs"]["native"]["command"].remove("--battery=pack")
                campaign_path.write_text(json.dumps(campaign))
                with self.assertRaisesRegex(ValueError, "invalid Mac release probe command"):
                    baseline._campaign_runs(campaign_path)

    def test_comparison_command_does_not_ignore_battery_mode(self):
        with tempfile.TemporaryDirectory(prefix="session-battery-compare-") as directory:
            with patch.object(baseline, "compare_campaigns") as compare:
                self.assertEqual(baseline.main(["--compare-campaigns", "one.json", "two.json", "--battery", "pack",
                                                "--out", str(Path(directory) / "out")]), 1)
                compare.assert_not_called()


class TrimProfileTests(unittest.TestCase):
    @staticmethod
    def start(backend: str) -> dict:
        return {"selected_throttle": 0.5, "requested_throttle": 0.5, "start_sha256": "9" * 64,
                "backend_domain_guard": backend == "native", "domain_guard_checks": 19}

    @classmethod
    def report(cls, backend: str) -> dict:
        report = valid_current_report(backend)
        report["machine"].update(os="macOS", architecture="arm64")
        report["experimental_native_macos"] = True
        report.update(template_release=False, solver_identity_kind="source-tree-v1", trim_profile="production",
                      trim_start=cls.start(backend))
        return report

    def test_production_proof_requires_start_guard_and_tick_coverage(self):
        for backend in ("gdscript_reference", "native"):
            report = self.report(backend)
            self.assertEqual(validate_probe_report(report, expected={"trim_profile": "production"}), [])
            mutations = (
                lambda r: r.pop("trim_start"),
                lambda r: r["trim_start"].update(selected_throttle=True),
                lambda r: r["trim_start"].update(requested_throttle=0.6),
                lambda r: r["trim_start"].update(start_sha256="bad"),
                lambda r: r["trim_start"].update(backend_domain_guard=backend != "native"),
                lambda r: r["trim_start"].update(domain_guard_checks=18),
                lambda r: r["trim_start"].update(domain_guard_checks=True),
                lambda r: r["trim_start"].update(extra=True),
                lambda r: r["backend"]["actual"].update(backend="fallback"),
            )
            for mutation in mutations:
                changed = copy.deepcopy(report)
                mutation(changed)
                with self.subTest(backend=backend, changed=changed):
                    self.assertTrue(validate_probe_report(changed, expected={"trim_profile": "production"}))
        native = self.report("native")
        native["machine"]["architecture"] = "x86_64"
        self.assertTrue(validate_probe_report(native))
        native = self.report("native")
        native["experimental_native_macos"] = False
        self.assertTrue(validate_probe_report(native))

    def test_legacy_absence_and_explicit_reference_are_distinct(self):
        legacy = valid_current_report()
        self.assertEqual(validate_probe_report(legacy, expected={"trim_profile": None}), [])
        self.assertTrue(validate_probe_report(legacy, expected={"trim_profile": "production"}))
        explicit = copy.deepcopy(legacy)
        explicit["trim_profile"] = "reference"
        self.assertEqual(validate_probe_report(explicit, expected={"trim_profile": "reference"}), [])
        self.assertTrue(validate_probe_report(explicit, expected={"trim_profile": None}))
        explicit["trim_start"] = self.start("gdscript_reference")
        self.assertTrue(validate_probe_report(explicit))

    def test_pair_rejects_changed_start_or_missing_guard(self):
        reference, native = self.report("gdscript_reference"), self.report("native")
        self.assertTrue(reduce_backend_pair(reference, native)["comparable"])
        self.assertTrue(baseline.reduce_identical_pair(native, copy.deepcopy(native), "native")["comparable"])
        changed = copy.deepcopy(native)
        changed["trim_start"]["start_sha256"] = "8" * 64
        self.assertEqual(validate_probe_report(changed), [])
        self.assertFalse(reduce_backend_pair(reference, changed)["comparable"])
        self.assertFalse(baseline.reduce_identical_pair(native, changed, "native")["comparable"])
        changed = copy.deepcopy(native)
        changed["trim_start"]["backend_domain_guard"] = False
        self.assertFalse(reduce_backend_pair(reference, changed)["comparable"])

    def test_source_campaign_forwards_profiles_and_rereader_rejects_downgrade(self):
        helper = BatteryModeTests()
        with tempfile.TemporaryDirectory(prefix="session-trim-source-") as directory:
            code, campaign, commands, output = helper.source_campaign(Path(directory), "pack", trim_profile="production")
            self.assertEqual(code, 0, campaign["failures"])
            self.assertEqual(campaign["configuration"]["trim_profile"], "production")
            self.assertTrue(all("--trim-profile=production" in command for command in commands))
            self.assertTrue(campaign["pairs"][0]["runs"]["native"]["trim_start"]["backend_domain_guard"])
            path = output / "session_baseline.json"
            self.assertEqual(len(baseline._campaign_runs(path)[1]), 1)
            campaign["configuration"]["trim_profile"] = "reference"
            path.write_text(json.dumps(campaign))
            with self.assertRaisesRegex(ValueError, "requested trim profile"):
                baseline._campaign_runs(path)
        with tempfile.TemporaryDirectory(prefix="session-trim-reference-") as directory:
            code, campaign, commands, output = helper.source_campaign(Path(directory), "pack", trim_profile="reference")
            self.assertEqual(code, 0, campaign["failures"])
            self.assertTrue(all("--trim-profile=reference" in command for command in commands))
            self.assertEqual(len(baseline._campaign_runs(output / "session_baseline.json")[1]), 1)
        with tempfile.TemporaryDirectory(prefix="session-trim-identical-") as directory:
            code, campaign, commands, _output = helper.source_campaign(Path(directory), "pack", identical=True,
                                                                       trim_profile="production")
            self.assertEqual(code, 0, campaign["failures"])
            self.assertTrue(all("--trim-profile=production" in command for command in commands))
        for bad in ("guard", "drift"):
            with self.subTest(bad=bad), tempfile.TemporaryDirectory(prefix="session-trim-bad-") as directory:
                code, campaign, _commands, _output = helper.source_campaign(Path(directory), "pack", trim_profile="production", bad_trim=bad)
                self.assertEqual(code, 1)
                self.assertFalse(campaign["complete"])
        with tempfile.TemporaryDirectory(prefix="session-trim-default-") as directory:
            code, campaign, commands, _output = helper.source_campaign(Path(directory), None)
            self.assertEqual(code, 0, campaign["failures"])
            self.assertNotIn("trim_profile", campaign["configuration"])
            self.assertTrue(all(not any(arg.startswith("--trim-profile=") for arg in command) for command in commands))
            self.assertTrue(all("trim_profile" not in item and "trim_start" not in item
                                for item in campaign["pairs"][0]["runs"].values()))

    def test_release_and_comparison_do_not_silently_ignore_explicit_profile(self):
        with patch.object(baseline, "run_campaign") as campaign, patch.object(baseline, "compare_campaigns") as compare:
            self.assertEqual(baseline.main(["--godot", "fake", "--out", "out", "--release-executable", "--trim-profile", "production"]), 1)
            self.assertEqual(baseline.main(["--compare-campaigns", "one", "two", "--out", "out", "--trim-profile", "reference"]), 1)
            campaign.assert_not_called()
            compare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
