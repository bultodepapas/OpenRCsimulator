"""NK-3 promotion regressions: disposable evidence, no compiler, library or Godot required."""

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location("nk3_test_" + name, HERE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load("build")
runner = load("run")
BINARY = "a" * 64
ENGINE_VERSION = "4.8-beta1 (official)"
ENGINE = "e" * 64
SOURCES = {"app/sim/flight_session.gd": "b" * 64}


def evidence(kind):
    """Synthetic completed run, including actual coverage and the independent checked-run receipt."""
    if kind == "stage_oracle":
        counts = {name: 12000 for name in (
            "stage_shape", "prop_loads", "hull_loads", "ground_evaluation_ok", "ground_up",
            "stage_bytes", "stage_loads", "stage_derivative", "stage_rotor_momentum",
            "ground_evaluation_loads", "ground_evaluation_derivative")}
    else:
        counts = {"trajectory_end": 5, "trajectory_fingerprint": 5,
                  **{name: 4800 for name in ("trajectory_tick_floats", "trajectory_tick_sizes", "trajectory_tick_modes")},
                  **{name: 5 for name in ("fault_path_end", "fault_path_bytes", "fault_path_sizes", "fault_path_modes")},
                  **{name: 2400 for name in ("checkpoint_tick_floats", "checkpoint_tick_sizes", "checkpoint_tick_modes")},
                  "checkpoint_pass_length": 2, "fallback_reference_kept": 1}
    components = {name: {"count": count, "identical": count} for name, count in counts.items()}
    compared = sum(counts.values())
    end = {"tick": 960, "fault": "", "crashed": False, "paused": False}
    case = {"ticks_requested": 960, "ticks_run": 960, "reference_end": end, "native_end": end.copy(),
            "completion_ok": True, "native_fingerprint": "c" * 64, "reference_fingerprint": "c" * 64,
            "first_divergence_tick": -1, "native_lost_install_ticks": 0, "native_uncovered_ticks": 0,
            "native_context_calls": 960, "native_stage_calls": 3840}
    return {
        "format": "openrc-nk3-stage-oracle v1" if kind == "stage_oracle" else "openrc-nk3-trajectory v2",
        "verdict": "pass", "failures": [], "run_valid": True,
        "engine": ENGINE_VERSION, "engine_sha256_before": ENGINE, "engine_sha256_after": ENGINE,
        "checked_run": {"ok": True, "complete": True, "reason": "passed", "process_exit": 0,
                        "counts": {"error": 0}, "missing_required_text": []},
        "build_receipt": {"binary_sha256": BINARY, "mutant": False, "cxxflags_appended": [],
                          "source_sha256": builder.source_digest(), "lock_sha256": builder.sha256_file(builder.locked.LOCK_PATH),
                          "builder_sha256": builder.sha256_file(Path(builder.__file__)),
                          "backend_version": builder.BACKEND_VERSION, "abi_version": builder.ABI_VERSION,
                          "reference_sources_sha256": copy.deepcopy(SOURCES)},
        "binary_sha256_before": BINARY, "binary_sha256_after": BINARY,
        "reference_sources_before": copy.deepcopy(SOURCES), "reference_sources_after": copy.deepcopy(SOURCES),
        "sources": {name.replace("app/", "res://", 1): digest for name, digest in SOURCES.items()},
        "sources_after": {name.replace("app/", "res://", 1): digest for name, digest in SOURCES.items()},
        "harness_sources": {str(path.relative_to(builder.ROOT)): builder.sha256_file(path) for path in
                            [*HERE.glob("*.gd"), HERE / "run.py", HERE / "build.py", builder.ROOT / "app/sim/native_stage.gd",
                             builder.ROOT / "tools/godot/run_checked.py"]},
        "components": components,
        "total": {"compared": compared, "identical": compared, "mismatched": 0},
        "coverage": {name: {"states": 4000, "malformed": 100, "stage_shaped": 4000}
                     for name in ("stage_air", "stage_ground", "stage_hull")},
        "trajectories": {name: copy.deepcopy(case) for name in builder.TRAJECTORY_CASES},
        "fault_paths": {
            name: {"advanced": False,
                   "reference": {"tick": 1200, "fault": reason, "paused": True, "crashed": False},
                   "native": {"tick": 1200, "fault": reason, "paused": True, "crashed": False}}
            for name, reason in {
                "state_nan_velocity": "step rejected: current state is nonfinite, malformed, or has a degenerate quaternion",
                "continuous_nan_wheel": "step rejected: input or auxiliary state is nonfinite or malformed",
                "overflow_velocity": "step rejected: pre-step produced nonfinite or malformed auxiliary state",
                "overflow_rates": "step rejected: pre-step produced nonfinite or malformed auxiliary state",
                "buried_state": "step rejected: joint stage evaluation is nonfinite or malformed",
            }.items()},
        "checkpoint": {"reference": {"restored": True, "resumed": True, "native_after_restore": False},
                       "native": {"restored": True, "resumed": True, "native_after_restore": True},
                       "passes": [{"ticks_reference": 1200, "ticks_native": 1200, "mismatches": 0} for _ in range(2)]},
        "fallback": {"aircraft": "jensen-das-ugly-stik-60", "rejected_configuration": "weather_pending_reset",
                     "refused": True, "reason": "unsupported session capability",
                     "reference_ticks": 960, "ticks": 960, "stage_after_attempt": "_wheel_evaluate", "fingerprint_equal": True},
    }


class PromotionEvidence(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="nk3-verification-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        patched = patch.object(builder, "TOOL_ROOT", self.root)
        patched.start()
        self.addCleanup(patched.stop)
        engine = patch.object(builder, "pinned_engine_identity", return_value=(ENGINE_VERSION, ENGINE))
        engine.start()
        self.addCleanup(engine.stop)

    def write(self, data, name="run-2.json"):
        path = self.root / name
        path.write_text(json.dumps(data))
        return path

    def find(self, kind):
        return builder.find_verification(kind, "run-*.json", BINARY, SOURCES)

    def rejected(self, kind, data):
        self.write(data)
        with self.assertRaises(SystemExit):
            self.find(kind)

    @staticmethod
    def retotal(data):
        compared = sum(row["count"] for row in data["components"].values())
        data["total"] = {"compared": compared, "identical": compared, "mismatched": 0}

    def test_completed_runs_qualify_and_pin_the_evidence_bytes(self):
        for kind in ("stage_oracle", "trajectory"):
            with self.subTest(kind=kind):
                path = self.write(evidence(kind))
                selected = self.find(kind)
                self.assertEqual(selected["results_sha256"], builder.sha256_file(path))

    def test_empty_truncated_faulted_or_uncovered_trajectories_never_qualify(self):
        for field, value in (("ticks_run", 0), ("ticks_run", 959), ("ticks_run", "960"),
                             ("ticks_requested", 14400), ("completion_ok", False),
                             ("native_uncovered_ticks", 1), ("native_lost_install_ticks", 1),
                             ("native_stage_calls", 0), ("native_context_calls", 0),
                             ("first_divergence_tick", 42), ("native_fingerprint", "d" * 64)):
            with self.subTest(field=field, value=value):
                data = evidence("trajectory")
                data["trajectories"]["trim"][field] = value
                self.rejected("trajectory", data)
        for field, value in (("fault", "same fault in both"), ("paused", True), ("crashed", True)):
            with self.subTest(end_field=field):
                data = evidence("trajectory")
                for name in ("reference_end", "native_end"):
                    data["trajectories"]["trim"][name][field] = value
                self.rejected("trajectory", data)

    def test_only_declared_crash_cases_can_finish_early_after_the_minimum(self):
        for name in ("takeoff", "lake"):
            data = evidence("trajectory")
            case = data["trajectories"][name]
            case["ticks_requested"] = 14400
            for key in ("reference_end", "native_end"):
                case[key].update(crashed=True, paused=True)
            self.write(data)
            self.find("trajectory")
            for key in ("reference_end", "native_end"):
                case[key]["paused"] = False
            self.rejected("trajectory", data)
            for key in ("reference_end", "native_end"):
                case[key]["paused"] = True
            case["ticks_run"] = 959
            self.rejected("trajectory", data)

    def test_missing_cases_and_historical_trajectory_format_are_rejected(self):
        data = evidence("trajectory")
        del data["trajectories"]["lake"]
        self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["format"] = "openrc-nk3-trajectory v1"
        self.rejected("trajectory", data)

    def test_fault_phases_require_all_cases_and_complete_matching_comparisons(self):
        names = list(evidence("trajectory")["fault_paths"])
        for name in names:
            with self.subTest(missing_case=name):
                data = evidence("trajectory")
                del data["fault_paths"][name]
                self.rejected("trajectory", data)
        for field, value in (("advanced", True), ("advanced", 0)):
            data = evidence("trajectory")
            data["fault_paths"][names[0]][field] = value
            self.rejected("trajectory", data)
        for field, value in (("tick", 1199), ("fault", ""), ("fault", "unexpected failure"),
                             ("paused", False), ("crashed", True)):
            with self.subTest(end_field=field, value=value):
                data = evidence("trajectory")
                for backend in ("reference", "native"):
                    data["fault_paths"][names[0]][backend][field] = value
                self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["fault_paths"][names[0]]["native"]["fault"] += " mismatch"
        self.rejected("trajectory", data)
        for field, value in (("tick", 1200.0), ("paused", 1), ("crashed", 0)):
            with self.subTest(native_type=field):
                data = evidence("trajectory")
                data["fault_paths"][names[0]]["native"][field] = value
                self.rejected("trajectory", data)
        for name in ("fault_path_end", "fault_path_bytes", "fault_path_sizes", "fault_path_modes"):
            with self.subTest(component=name):
                data = evidence("trajectory")
                data["components"][name] = {"count": 4, "identical": 4}
                self.retotal(data)
                self.rejected("trajectory", data)

    def test_checkpoint_phase_requires_restore_and_both_full_matching_passes(self):
        for backend, field in (("reference", "restored"), ("reference", "resumed"),
                               ("native", "restored"), ("native", "resumed"),
                               ("native", "native_after_restore")):
            with self.subTest(backend=backend, field=field):
                data = evidence("trajectory")
                data["checkpoint"][backend][field] = False
                self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["checkpoint"]["native"].update(native_after_restore=False, reinstalled=True)
        self.write(data)
        self.find("trajectory")
        for attempt in range(2):
            for field, value in (("ticks_reference", 1199), ("ticks_native", 0), ("mismatches", 1)):
                with self.subTest(attempt=attempt, field=field):
                    data = evidence("trajectory")
                    data["checkpoint"]["passes"][attempt][field] = value
                    self.rejected("trajectory", data)
        for name in ("checkpoint_tick_floats", "checkpoint_tick_sizes", "checkpoint_tick_modes", "checkpoint_pass_length"):
            with self.subTest(component=name):
                data = evidence("trajectory")
                data["components"][name]["count"] -= 1
                data["components"][name]["identical"] -= 1
                self.retotal(data)
                self.rejected("trajectory", data)

    def test_fallback_phase_requires_refusal_and_full_matching_reference(self):
        for field, value in (("aircraft", "wrong"), ("rejected_configuration", "weather_ready"),
                             ("refused", False), ("reason", ""), ("reason", " "),
                             ("reference_ticks", 959), ("ticks", 959), ("stage_after_attempt", "stage"),
                             ("stage_after_attempt", "evaluate"),
                             ("fingerprint_equal", False)):
            with self.subTest(field=field):
                data = evidence("trajectory")
                data["fallback"][field] = value
                self.rejected("trajectory", data)
        data = evidence("trajectory")
        del data["components"]["fallback_reference_kept"]
        self.retotal(data)
        self.rejected("trajectory", data)

    def test_missing_phase_or_truncated_tick_comparisons_cannot_pass(self):
        for phase, prefix in (("fault_paths", "fault_path_"), ("checkpoint", "checkpoint_"),
                              ("fallback", "fallback_")):
            with self.subTest(phase=phase):
                data = evidence("trajectory")
                del data[phase]
                for component in list(data["components"]):
                    if component.startswith(prefix):
                        del data["components"][component]
                self.retotal(data)
                self.rejected("trajectory", data)
        for name in ("trajectory_tick_floats", "trajectory_tick_sizes", "trajectory_tick_modes",
                     "trajectory_end", "trajectory_fingerprint"):
            with self.subTest(component=name):
                data = evidence("trajectory")
                data["components"][name]["count"] -= 1
                data["components"][name]["identical"] -= 1
                self.retotal(data)
                self.rejected("trajectory", data)

    def test_stage_requests_are_not_actual_coverage(self):
        for count in (0, 3333):
            data = evidence("stage_oracle")
            data["states"] = 12000
            for row in data["coverage"].values():
                row["states"] = count
            self.rejected("stage_oracle", data)
        data = evidence("stage_oracle")
        for row in data["coverage"].values():
            row["malformed"] = 0
        self.rejected("stage_oracle", data)
        data = evidence("stage_oracle")
        del data["components"]["stage_bytes"]
        self.rejected("stage_oracle", data)

    def test_process_errors_and_changed_inputs_cannot_promote_a_pass_label(self):
        for field, value in (("complete", False), ("ok", False), ("reason", "engine_error"),
                             ("process_exit", 1), ("counts", {"error": 1})):
            data = evidence("trajectory")
            data["checked_run"][field] = value
            self.rejected("trajectory", data)
        for field, value in (("binary_sha256_before", "d" * 64), ("binary_sha256_after", "d" * 64),
                             ("sources_after", {}), ("sources", {}), ("harness_sources", {}),
                             ("reference_sources_before", {}), ("reference_sources_after", {}),
                             ("run_valid", False), ("engine", "different engine"),
                             ("engine_sha256_before", "d" * 64), ("engine_sha256_after", "d" * 64)):
            data = evidence("trajectory")
            data[field] = value
            self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["harness_sources"]["research/native-kernel/glow_oracle.gd"] = "stale"
        self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["sources"]["res://physics/math3d.gd"] = "stale"
        data["sources_after"] = copy.deepcopy(data["sources"])
        self.rejected("trajectory", data)

    def test_release_and_negative_control_require_current_build_identities(self):
        for field in ("source_sha256", "lock_sha256", "builder_sha256", "backend_version", "abi_version",
                      "reference_sources_sha256"):
            data = evidence("stage_oracle")
            data["build_receipt"][field] = "stale"
            self.rejected("stage_oracle", data)
        mutant_path = self.root / "lib/libopenrc_native_kernel_mutant.so"
        mutant_path.parent.mkdir()
        mutant_path.write_bytes(b"intentional mutation")
        mutant_sha = builder.sha256_file(mutant_path)
        data = evidence("stage_oracle")
        data["build_receipt"].update(binary_sha256=mutant_sha, mutant=True, cxxflags_appended=["-DNK_MUTATION=1"])
        data["binary_sha256_before"] = data["binary_sha256_after"] = mutant_sha
        data["checked_run"].update(ok=False, reason="process_exit", process_exit=1)
        data["verdict"] = "fail"
        data["components"]["stage_bytes"]["identical"] -= 1
        data["total"]["identical"] -= 1
        data["total"]["mismatched"] = 1
        self.write(data, "run-1_mutant.json")
        self.assertEqual(self.find("negative_control")["verdict"], "fail")
        for change in (lambda row: row["checked_run"].update(complete=False),
                       lambda row: row["checked_run"].update(counts={"error": 1}),
                       lambda row: row["checked_run"].update(missing_required_text=["missing"]),
                       lambda row: row["build_receipt"].update(source_sha256="stale"),
                       lambda row: row["build_receipt"].update(mutant=False),
                       lambda row: row["build_receipt"].update(cxxflags_appended=[]),
                       lambda row: row["reference_sources_after"].clear(),
                       lambda row: row["components"]["stage_bytes"].update(identical=12000)):
            invalid = copy.deepcopy(data)
            change(invalid)
            self.write(invalid, "run-1_mutant.json")
            with self.assertRaises(SystemExit):
                self.find("negative_control")

    def test_malformed_newer_reports_do_not_hide_older_valid_evidence(self):
        self.write(evidence("trajectory"), "run-1.json")
        for invalid in (None, [], {}, {"build_receipt": None}, {"trajectories": None}):
            self.write(invalid)
            self.assertEqual(self.find("trajectory")["results"], "run-1.json")
        self.root.joinpath("run-2.json").write_text("{")
        self.assertEqual(self.find("trajectory")["results"], "run-1.json")


class CheckedRunner(unittest.TestCase):
    def test_options_cannot_override_artifact_identity_or_repeat_a_setting(self):
        runner.validate_options("trajectory.gd", ["ticks=960", "skip-timing=true"])
        for options in (["extension=other.gdextension"], ["output=other.json"], ["states=0"],
                        ["ticks=960", "ticks=0"], ["ticks"], ["ticks="]):
            with self.subTest(options=options), self.assertRaises(ValueError):
                runner.validate_options("trajectory.gd", options)

    def test_mutant_must_fail_cleanly_and_completely(self):
        report = evidence("trajectory")["checked_run"]
        self.assertTrue(runner.checked_run_matches(report, False))
        self.assertFalse(runner.checked_run_matches(report, True))
        report.update(ok=False, reason="process_exit", process_exit=1)
        self.assertTrue(runner.checked_run_matches(report, True))
        for field, value in (("complete", False), ("counts", {"error": 1}),
                             ("missing_required_text", ["NK3_ORACLE verdict=fail"]),
                             ("reason", "timeout"), ("process_exit", 139)):
            candidate = copy.deepcopy(report)
            candidate[field] = value
            self.assertFalse(runner.checked_run_matches(candidate, True))

    def test_binary_is_resolved_from_the_actual_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.gdextension"
            path.write_text('[libraries]\nlinux.x86_64 = "lib/actual.so"\n')
            self.assertEqual(runner.selected_binary(path), path.parent / "lib/actual.so")
            path.write_text('[libraries]\nlinux.x86_64 = "res://native/kernel/actual.so"\n')
            self.assertEqual(runner.selected_binary(path), builder.ROOT / "app/native/kernel/actual.so")


class ManualLoadingInstallation(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="nk3-manual-loading-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.destination = self.app / "native/kernel"
        self.registry = self.app / ".godot/extension_list.cfg"
        self.own_entry = b"res://native/kernel/openrc_native_kernel.gdextension"

    def prepare(self):
        builder.prepare_manual_loading(self.app, self.destination)

    def test_fresh_install_excludes_descriptor_before_import(self):
        self.prepare()
        self.assertTrue((self.destination / ".gdignore").is_file())
        self.assertFalse(self.registry.exists())
        self.prepare()  # repeated installs are harmless

    def test_migration_removes_only_our_entries_and_preserves_other_bytes_and_mode(self):
        self.registry.parent.mkdir()
        other = b"res://native/ground_vehicle/ground.gdextension\r\n"
        remainder = b"res://another.gdextension\n"
        self.registry.write_bytes(other + self.own_entry + b"\r\n" + remainder + self.own_entry)
        self.registry.chmod(0o640)
        self.prepare()
        self.assertEqual(self.registry.read_bytes(), other + remainder)
        self.assertEqual(self.registry.stat().st_mode & 0o777, 0o640)
        self.assertTrue((self.destination / ".gdignore").is_file())
        self.prepare()
        self.assertEqual(self.registry.read_bytes(), other + remainder)

    def test_unrelated_registry_is_not_rewritten(self):
        self.registry.parent.mkdir()
        content = b"res://native/kernel/another.gdextension\n"
        self.registry.write_bytes(content)
        inode = self.registry.stat().st_ino
        self.prepare()
        self.assertEqual(self.registry.read_bytes(), content)
        self.assertEqual(self.registry.stat().st_ino, inode)

    def test_failed_atomic_replace_leaves_old_registry_intact(self):
        self.registry.parent.mkdir()
        original = self.own_entry + b"\nres://other.gdextension\n"
        self.registry.write_bytes(original)
        with patch.object(builder.os, "replace", side_effect=OSError("failed")):
            with self.assertRaises(OSError):
                self.prepare()
        self.assertEqual(self.registry.read_bytes(), original)
        self.assertEqual(list(self.registry.parent.glob(".nk3-extension-list-*")), [])

    def test_refuses_external_destination_and_symlinked_registry(self):
        with self.assertRaises(SystemExit):
            builder.prepare_manual_loading(self.app, self.root / "outside")
        outside = self.root / "external-list"
        outside.write_bytes(self.own_entry + b"\n")
        self.registry.parent.mkdir()
        self.registry.symlink_to(outside)
        with self.assertRaises(SystemExit):
            self.prepare()
        self.assertEqual(outside.read_bytes(), self.own_entry + b"\n")

    def test_refuses_symlinked_native_directory_and_import_marker(self):
        self.destination.parent.mkdir()
        alternate = self.app / "other"
        alternate.mkdir()
        self.destination.symlink_to(alternate, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.prepare()
        self.assertFalse((alternate / ".gdignore").exists())
        self.destination.unlink()
        self.destination.mkdir()
        marker_target = self.root / "marker-target"
        marker_target.write_text("unchanged")
        (self.destination / ".gdignore").symlink_to(marker_target)
        with self.assertRaises(SystemExit):
            self.prepare()
        self.assertEqual(marker_target.read_text(), "unchanged")

    def test_refuses_symlinked_cache_directory(self):
        alternate = self.app / "other-cache"
        alternate.mkdir()
        alternate_registry = alternate / "extension_list.cfg"
        alternate_registry.write_bytes(self.own_entry + b"\n")
        (self.app / ".godot").symlink_to(alternate, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.prepare()
        self.assertEqual(alternate_registry.read_bytes(), self.own_entry + b"\n")


if __name__ == "__main__":
    unittest.main()
