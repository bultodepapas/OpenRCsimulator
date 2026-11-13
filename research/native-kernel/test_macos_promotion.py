from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

PATH = Path(__file__).with_name("macos_promotion.py")
SPEC = importlib.util.spec_from_file_location("macos_promotion_tested", PATH)
promotion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(promotion)


def write_json(path: Path, value: object) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")
    return promotion.sha(path)


def row(**changes: object) -> dict:
    value = {"aircraft": "jensen", "vehicle": "fixed-wing", "battery": "ideal", "case": "trim",
             "weather": "calm", "soft_hull": False, "status": "verified-flight", "start_sha256": "a" * 64}
    value.update(changes)
    return value


class SelectionTests(unittest.TestCase):
    def test_existing_validators_import_with_sibling_dependencies(self) -> None:
        modules = (("nk3_promotion_test_fleet", promotion.HERE / "fleet_campaign.py"),
                   ("nk3_promotion_test_package", promotion.HERE / "package.py"),
                   ("nk3_promotion_test_summary", promotion.ROOT / "research/performance/native_summary.py"))
        for name, path in modules:
            with self.subTest(name=name):
                self.assertIsNotNone(promotion.module(name, path))

    def test_only_verified_rows_are_allowed_and_case_maps_to_start(self) -> None:
        result = promotion.selection_rows([row(status="open"), row()])
        self.assertEqual(result, [{"aircraft": "jensen", "battery": "ideal", "start": "airborne",
                                   "weather": "calm", "soft_hull": False, "trim_profile": "production",
                                   "start_sha256": "a" * 64}])

    def test_unknown_case_duplicate_nonfixed_and_empty_refused(self) -> None:
        for rows in ([row(case="unknown")], [row(case="airborne")], [row(), row(start_sha256="b" * 64)],
                     [row(vehicle="helicopter")], [row(status="open")], [row(start_sha256="A" * 64)],
                     [row(soft_hull=1)]):
            with self.subTest(rows=rows), self.assertRaises(promotion.AdmissionError):
                promotion.selection_rows(rows)

    def test_duplicate_and_nonfinite_json_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            for text in ('{"a":1,"a":2}', '{"a":NaN}'):
                path.write_text(text, encoding="utf-8")
                with self.assertRaises(promotion.AdmissionError):
                    promotion.read_json(path)

    def test_live_inventory_matches_visible_project_and_benchmark_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "app"
            project.mkdir()
            (project / "main.gd").write_text("source", encoding="utf-8")
            (project / ".ignored").write_text("not visible", encoding="utf-8")
            for name in ("sustained_input.gd", "sustained_flight.gd"):
                path = root / "research/performance" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name, encoding="utf-8")
            with patch.object(promotion, "ROOT", root):
                sources = promotion.live_sources(project)
            self.assertEqual(set(sources), {"res://main.gd", "research/performance/sustained_input.gd",
                                            "research/performance/sustained_flight.gd"})
            self.assertEqual(sources["res://main.gd"], promotion.sha(project / "main.gd"))


class PreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.guard = {"receipt": {"runtime_os_version": "27.0.1", "runtime_os_build": "26A434"},
                      "engine_sha256": "e" * 64}
        self.preflight = {"format": "openrc-macos-preflight-v1", "host": {"model_identifier": promotion.MODEL,
                          "cpu": promotion.CPU, "hardware_arm64": True, "python_process_native_arm64": True,
                          "python_process_rosetta": False, "os_version": "27.0.1", "os_build": "26A434"},
                          "engine": {"identity": {"sha256": "e" * 64},
                                     "identity_stable_across_version_checks": True}}

    def test_matching_preflight_and_current_hardware(self) -> None:
        with patch.object(promotion, "_sysctl", side_effect=[promotion.MODEL, promotion.CPU]):
            promotion.validate_preflight(self.preflight, self.guard)

    def test_wrong_host_or_changed_engine_refused(self) -> None:
        for field, value in (("cpu", "Apple M2"), ("python_process_rosetta", True), ("os_build", "other")):
            changed = copy.deepcopy(self.preflight)
            changed["host"][field] = value
            with self.subTest(field=field), self.assertRaises(promotion.AdmissionError):
                promotion.validate_preflight(changed, self.guard)
        with patch.object(promotion, "_sysctl", side_effect=["different-model", promotion.CPU]):
            with self.assertRaises(promotion.AdmissionError):
                promotion.validate_preflight(self.preflight, self.guard)


class FleetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.tool_root = root / "tools"
        self.tool_root.mkdir()
        self.directory = root / "campaign"
        self.directory.mkdir()
        self.manifest_hash = write_json(self.directory / "manifest.json", {"manifest": "retained"})
        (self.directory / "manifest.gd").write_text("manifest source", encoding="utf-8")
        self.report = self.tool_root / "fleet-jensen.json"
        report_hash = write_json(self.report, {"scope": "raw"})
        self.guard = {"trim_profile": "production", "engine_sha256": "a" * 64}
        self.checked = {"base_oracle_boundary": {"binary_sha256": "b" * 64},
                        "verified_flight_rows": 1, "open_rows": 1, "rows": [row(), row(status="open")]}
        self.campaign = {**self.checked, "format": "openrc-nk3-fleet-campaign-macos-experimental v1",
                         "trim_profile": "production", "guard": {**self.guard,
                         "base_oracle_boundary": self.checked["base_oracle_boundary"]},
                         "manifest_sha256": self.manifest_hash,
                         "manifest_script_sha256": promotion.sha(self.directory / "manifest.gd"),
                         "selected_aircraft": ["jensen"], "shard_errors": {},
                         "reports": {"jensen": {"path": str(self.report), "sha256": report_hash}},
                         "warmup": 120, "samples": 500}
        self.campaign_path = self.directory / "campaign.json"
        self.context = {"tool_root": str(self.tool_root)}
        self.fleet = SimpleNamespace(validate_macos_reports=lambda *args: self.checked)

    def validate(self) -> tuple:
        write_json(self.campaign_path, self.campaign)
        return promotion.validate_fleet(self.fleet, self.campaign_path, self.context, self.guard)

    def test_failed_aggregate_does_not_add_unverified_rows(self) -> None:
        self.campaign["verdict"] = "fail"
        selections, proof = self.validate()
        self.assertEqual(len(selections), 1)
        self.assertEqual(proof["open_rows"], 1)

    def test_legacy_trim_and_changed_report_and_ledger_refused(self) -> None:
        self.campaign["trim_profile"] = "reference"
        with self.assertRaises(promotion.AdmissionError):
            self.validate()
        self.campaign["trim_profile"] = "production"
        self.report.write_text('{"changed":true}', encoding="utf-8")
        with self.assertRaises(promotion.AdmissionError):
            self.validate()
        write_json(self.report, {"scope": "raw"})
        self.campaign["verified_flight_rows"] = 2
        with self.assertRaises(promotion.AdmissionError):
            self.validate()


class LiveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.reference = self.work / "ref.json"
        self.native = self.work / "native.json"
        self.reference.write_text("ref", encoding="utf-8")
        self.native.write_text("native", encoding="utf-8")
        self.guard = {"receipt_sha256": "r", "descriptor_sha256": "d", "engine_sha256": "e",
                      "binary_sha256": "b", "receipt": {"source_sha256": "s", "lock_sha256": "l"}}
        self.sources = {"res://main.gd": "0" * 64}
        self.health_ref = self.work / "ref-health.json"
        self.health_nat = self.work / "native-health.json"
        health_ref_hash = write_json(self.health_ref, {"source_sha256": self.sources})
        health_nat_hash = write_json(self.health_nat, {"source_sha256": self.sources})
        installation = {"receipt_sha256": "r", "descriptor_sha256": "d", "engine_sha256": "e",
                        "native_source_sha256": "s", "identity": {"binary_sha256": "b",
                        "source_sha256": "s", "lock_sha256": "l"}}
        def run(capture: str, file: Path, digest: str) -> dict:
            return {"capture_id": capture, "benchmark_health": {"receipt": file.name, "receipt_sha256": digest,
                    "scenario": {"selected_trim_throttle": 0.5, "solved_start_sha256": "a" * 64,
                    "backend_proof": {"installation_before": copy.deepcopy(installation),
                                      "backend_domain_guard": capture == "native-id"}}}}
        self.comparison = {"complete": True, "reference": run("ref-id", self.health_ref, health_ref_hash),
                           "native": run("native-id", self.health_nat, health_nat_hash),
                           "matched_windows": [{"start_tick": 1}]}
        self.summary = SimpleNamespace(DEFAULT_POLICY={}, compare_circuit=self.compare)

    def compare(self, reference: Path, native: Path, output: Path, policy: dict) -> tuple:
        self.assertEqual(policy["minimum_warmup_s"], 30.0)
        self.assertEqual(policy["minimum_sample_s"], 1800.0)
        return self.comparison, 0

    def validate(self, seen: set | None = None) -> list:
        return promotion.validate_live(self.summary, [(self.reference, self.native)], self.guard,
                                       1800, seen if seen is not None else set(), self.work, [], self.sources)

    def test_matching_capture_bound_to_installed_candidate(self) -> None:
        self.assertEqual(self.validate()[0]["matched_windows"], 1)

    def test_reused_capture_and_wrong_binary_refused(self) -> None:
        with self.assertRaises(promotion.AdmissionError):
            self.validate({"ref-id"})
        self.comparison["native"]["benchmark_health"]["scenario"]["backend_proof"]["installation_before"]["identity"]["binary_sha256"] = "other"
        with self.assertRaises(promotion.AdmissionError):
            self.validate()

    def test_failed_comparator_is_not_admitted(self) -> None:
        self.comparison["complete"] = False
        with self.assertRaises(promotion.AdmissionError):
            self.validate()

    def test_current_source_tree_mismatch_is_refused(self) -> None:
        self.sources["res://main.gd"] = "1" * 64
        with self.assertRaises(promotion.AdmissionError):
            self.validate()

    def test_legacy_trim_or_missing_native_guard_is_refused(self) -> None:
        scenario = self.comparison["native"]["benchmark_health"]["scenario"]
        scenario["selected_trim_throttle"] = None
        with self.assertRaises(promotion.AdmissionError):
            self.validate()
        scenario["selected_trim_throttle"] = 0.5
        scenario["backend_proof"]["backend_domain_guard"] = False
        with self.assertRaises(promotion.AdmissionError):
            self.validate()
        scenario["backend_proof"]["backend_domain_guard"] = True
        scenario["solved_start_sha256"] = "missing"
        with self.assertRaises(promotion.AdmissionError):
            self.validate()


class GeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tmp").mkdir()
        self.project = self.root / "project"
        self.domain = self.root / "app/sim/native_macos_domain.gd"
        self.domain.parent.mkdir(parents=True)
        self.domain.write_text("domain", encoding="utf-8")
        project_domain = self.project / "sim/native_macos_domain.gd"
        project_domain.parent.mkdir(parents=True)
        project_domain.write_text("domain", encoding="utf-8")
        self.receipt_path = self.root / "app/native/kernel/build-receipt-macos.json"
        self.receipt_path.parent.mkdir(parents=True)
        self.receipt_path.write_text("receipt", encoding="utf-8")
        self.preflight = self.root / "preflight.json"
        write_json(self.preflight, {})
        self.campaign_path = self.root / "campaign.json"
        campaign_sha = write_json(self.campaign_path, {})
        receipt = {"source_sha256": "source", "lock_sha256": "lock",
                   "runtime_os_version": "27.0.1", "runtime_os_build": "26A434"}
        self.guard = {"receipt": receipt, "receipt_sha256": promotion.sha(self.receipt_path),
                      "binary_sha256": "binary", "engine_sha256": "engine"}
        self.installed = {"platforms": {"macos": receipt}}
        self.fleet = SimpleNamespace(snapshot=lambda context: self.guard)
        self.package = SimpleNamespace(verified_mac_install=lambda root, godot: self.installed)
        self.summary = SimpleNamespace(_checked_evidence_unchanged=lambda path, run: True)
        self.rows = promotion.selection_rows([row()])
        self.campaign = {"campaign_sha256": campaign_sha}
        self.args = SimpleNamespace(project=self.project, godot=self.root / "godot",
                                    tool_root=self.root / "tmp/tool", qualification_root=self.root / "tmp/build",
                                    preflight=self.preflight, campaign=self.campaign_path,
                                    short_pair=[(Path("a"), Path("b"))] * 5,
                                    long_pair=[(Path("c"), Path("d"))] * 3)

    def generate(self) -> dict:
        def load(name: str, path: Path) -> object:
            return {"nk3_promotion_fleet": self.fleet, "nk3_promotion_package": self.package,
                    "nk3_promotion_summary": self.summary}[name]
        with patch.object(promotion, "ROOT", self.root), patch.object(promotion, "module", side_effect=load), \
             patch.object(promotion, "validate_preflight"), \
             patch.object(promotion, "validate_fleet", return_value=(self.rows, self.campaign)), \
             patch.object(promotion, "live_sources", return_value={"res://main.gd": "hash"}), \
             patch.object(promotion, "validate_live", return_value=[]):
            return promotion.generate(self.args)

    def test_generator_binds_canonical_receipt_and_exact_selection(self) -> None:
        marker = self.generate()
        self.assertEqual(marker["format"], promotion.FORMAT)
        self.assertEqual(marker["receipt_sha256"], promotion.sha(self.receipt_path))
        self.assertEqual(marker["allowed_selections"], self.rows)
        self.assertNotIn("production_qualified", marker)

    def test_missing_required_pair_or_mismatched_project_receipt_refused(self) -> None:
        self.args.long_pair.pop()
        with self.assertRaises(promotion.AdmissionError):
            self.generate()
        self.args.long_pair.append((Path("c"), Path("d")))
        self.guard["receipt_sha256"] = "different"
        with self.assertRaises(promotion.AdmissionError):
            self.generate()


if __name__ == "__main__":
    unittest.main()
