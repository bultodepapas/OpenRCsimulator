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
ENGINE_VERSION = "4.8.beta1.official.4d10419ca"
ENGINE = "e" * 64
SOURCES = {"app/sim/flight_session.gd": "b" * 64}


def evidence(kind):
    """Synthetic completed run, including actual coverage and the independent checked-run receipt."""
    components = {name: {"count": 12000, "identical": 12000} for name in (
        "stage_shape", "prop_loads", "hull_loads", "ground_evaluation_ok", "ground_up",
        "stage_bytes", "stage_loads", "stage_derivative", "stage_rotor_momentum",
        "ground_evaluation_loads", "ground_evaluation_derivative")}
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
        "build_receipt": {"binary_sha256": BINARY}, "binary_sha256_before": BINARY, "binary_sha256_after": BINARY,
        "sources": {name.replace("app/", "res://", 1): digest for name, digest in SOURCES.items()},
        "sources_after": {name.replace("app/", "res://", 1): digest for name, digest in SOURCES.items()},
        "harness_sources": {str(path.relative_to(builder.ROOT)): builder.sha256_file(path) for path in
                            [*HERE.glob("*.gd"), HERE / "run.py", builder.ROOT / "app/sim/native_stage.gd",
                             builder.ROOT / "tools/godot/run_checked.py"]},
        "components": components,
        "total": {"compared": 132000, "identical": 132000, "mismatched": 0},
        "coverage": {name: {"states": 4000, "malformed": 100, "stage_shaped": 4000}
                     for name in ("stage_air", "stage_ground", "stage_hull")},
        "trajectories": {name: copy.deepcopy(case) for name in builder.TRAJECTORY_CASES},
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
            case["ticks_run"] = 959
            self.rejected("trajectory", data)

    def test_missing_cases_and_historical_trajectory_format_are_rejected(self):
        data = evidence("trajectory")
        del data["trajectories"]["lake"]
        self.rejected("trajectory", data)
        data = evidence("trajectory")
        data["format"] = "openrc-nk3-trajectory v1"
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
                             ("run_valid", False), ("engine", "different engine"),
                             ("engine_sha256_before", "d" * 64), ("engine_sha256_after", "d" * 64)):
            data = evidence("trajectory")
            data[field] = value
            self.rejected("trajectory", data)

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


if __name__ == "__main__":
    unittest.main()
