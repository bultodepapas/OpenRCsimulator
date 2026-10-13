"""AS-07 parity and strictness checks for the shared module registry."""

from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path
from typing import Any

from modules import classify


ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT = ROOT / "app" / "data" / "aircraft"
PARITY_PREFIX = "AS07_PARITY_JSON="


def read_aircraft(name: str) -> dict[str, Any]:
    return json.loads((AIRCRAFT / name).read_text(encoding="utf-8"))


def projection(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "ok": result["ok"],
        "errors": result["errors"],
        "diagnostics": result["diagnostics"],
        "modules": result["modules"],
        "laws": result["laws"],
        "parameters": result["parameters"],
        "compiler_transforms": result["compiler_transforms"],
        "compiler_transform_reasons": result["compiler_transform_reasons"],
    }


def parity_invalid_sources() -> dict[str, dict[str, Any]]:
    version = read_aircraft("jensen_ugly_stik_60.json")
    version["format"] = "openrc-aircraft v99"
    capability = read_aircraft("jensen_ugly_stik_60.json")
    capability["capabilities"]["gear"] = "retractable"
    module_field = read_aircraft("jensen_ugly_stik_60.json")
    module_field["propulsion"]["engine"]["future_module"] = {}
    battery_relation = read_aircraft("synthetic_stik_electric_4s.json")
    battery_relation["capabilities"]["energy"] = "ocv_resistance"
    turbine_integrator = read_aircraft("sebart_avanti_s_a200.json")
    turbine_integrator["propulsion"]["engine"]["spool_integrator"] = "semi_implicit"
    gear_relation = read_aircraft("sebart_avanti_s_a200.json")
    gear_relation["capabilities"]["gear"] = "fixed_tricycle"
    return {
        "invalid:version": version,
        "invalid:capability_value": capability,
        "invalid:module_field": module_field,
        "invalid:battery_relation": battery_relation,
        "invalid:turbine_integrator": turbine_integrator,
        "invalid:gear_relation": gear_relation,
    }


class AircraftModuleTests(unittest.TestCase):
    def test_all_checked_in_sources_classify_and_keep_descriptor_modules(self):
        files = sorted(AIRCRAFT.glob("*.json"))
        self.assertGreaterEqual(len(files), 10)
        for path in files:
            with self.subTest(aircraft=path.name):
                source = json.loads(path.read_text(encoding="utf-8"))
                result = classify(source)
                self.assertTrue(result["ok"], result["errors"])
                descriptor = ROOT / "app" / "data" / "workshop" / f"{source['id']}.json"
                if descriptor.exists():
                    previous = json.loads(descriptor.read_text(encoding="utf-8"))
                    self.assertEqual(result["modules"], previous["modules"])

    def test_selected_laws_are_specific_to_existing_runtime_variants(self):
        cases = [
            ("jensen_ugly_stik_60.json", "propulsion.glow_prop.legacy_prescribed_rpm.v1"),
            ("p51d_mustang_120.json", "propulsion.glow_prop.shaft_balance.v1"),
            ("stik_glow_55ax_2t.json", "propulsion.glow_prop.finite_glow_installation.v1"),
            ("synthetic_stik_electric_4s.json", "energy.battery.fixed_voltage.v1"),
            ("synthetic_stik_electric_4s_battery.json", "energy.battery.ocv_resistance.v1"),
            ("sebart_avanti_s_a200.json", "propulsion.turbine.spool.rk4.v1"),
        ]
        for filename, law in cases:
            with self.subTest(aircraft=filename):
                result = classify(read_aircraft(filename))
                self.assertTrue(result["ok"], result["errors"])
                self.assertIn(law, result["laws"])

    def test_turbine_integrator_default_is_normalized(self):
        source = read_aircraft("sebart_avanti_s_a200.json")
        del source["propulsion"]["engine"]["spool_integrator"]
        result = classify(source)
        self.assertTrue(result["ok"], result["errors"])
        self.assertIn("propulsion.turbine.spool.sampled.v1", result["laws"])
        self.assertEqual(result["parameters"]["propulsion.engine.spool_integrator"], "sampled")

    def test_unknown_versions_fields_and_invalid_relations_fail_without_partial_modules(self):
        cases: list[tuple[str, dict[str, Any], str]] = []
        unknown_version = read_aircraft("jensen_ugly_stik_60.json")
        unknown_version["format"] = "openrc-aircraft v99"
        cases.append(("version", unknown_version, "module.source.version"))

        unknown_capability = read_aircraft("jensen_ugly_stik_60.json")
        unknown_capability["capabilities"]["gear"] = "retractable"
        cases.append(("capability value", unknown_capability, "module.capability.unknown"))

        unknown_field = read_aircraft("jensen_ugly_stik_60.json")
        unknown_field["propulsion"]["engine"]["future_module"] = {}
        cases.append(("module field", unknown_field, "module.field.unknown"))

        battery_mismatch = read_aircraft("synthetic_stik_electric_4s.json")
        battery_mismatch["capabilities"]["energy"] = "ocv_resistance"
        cases.append(("battery relation", battery_mismatch, "module.relation.battery_energy"))

        turbine_integrator = read_aircraft("sebart_avanti_s_a200.json")
        turbine_integrator["propulsion"]["engine"]["spool_integrator"] = "semi_implicit"
        cases.append(("turbine integrator", turbine_integrator, "module.turbine.integrator.unknown"))

        gear_relation = read_aircraft("sebart_avanti_s_a200.json")
        gear_relation["capabilities"]["gear"] = "fixed_tricycle"
        cases.append(("gear relation", gear_relation, "module.capability.relation"))

        for label, source, code in cases:
            with self.subTest(case=label):
                result = classify(source)
                self.assertFalse(result["ok"])
                self.assertTrue(any(item["code"] == code for item in result["diagnostics"]), result)
                self.assertEqual(result["modules"], [])
                self.assertEqual(result["laws"], [])

    def test_python_and_gdscript_emit_identical_classification_for_every_source(self):
        configured = os.environ.get("OPENRC_TEST_GODOT", "")
        candidates = [Path(configured)] if configured else [
            ROOT / ".tools/Godot_v4.7.2-stable_win64.exe",
            ROOT / ".tools/Godot_v4.7.2-stable_linux.x86_64",
        ]
        godot = next((path for path in candidates if path.is_file()), None)
        if godot is None:
            if configured:
                self.fail("OPENRC_TEST_GODOT does not name an existing executable")
            self.skipTest("set OPENRC_TEST_GODOT to the pinned Godot executable for cross-language parity")
        completed = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT / "app"),
                "--script",
                "res://tests/test_aircraft_modules.gd",
                "--",
                "--emit-parity-json",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        parity_line = next((line for line in completed.stdout.splitlines() if line.startswith(PARITY_PREFIX)), None)
        self.assertIsNotNone(parity_line, completed.stdout)
        gdscript_results = json.loads(parity_line.removeprefix(PARITY_PREFIX))
        python_results = {
            json.loads(path.read_text(encoding="utf-8"))["id"]: projection(classify(json.loads(path.read_text(encoding="utf-8"))))
            for path in sorted(AIRCRAFT.glob("*.json"))
        }
        python_results.update({key: projection(classify(source)) for key, source in parity_invalid_sources().items()})
        self.assertEqual(gdscript_results, python_results)


if __name__ == "__main__":
    unittest.main()
