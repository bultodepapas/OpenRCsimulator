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


def fixed_wing_sources() -> dict[str, dict[str, Any]]:
    # Rotorcraft use a separate loader and module contract in the shared directory.
    sources = {path.name: read_aircraft(path.name) for path in sorted(AIRCRAFT.glob("*.json"))}
    return {name: source for name, source in sources.items() if source.get("vehicle") != "rotorcraft"}


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
    liquid_field = read_aircraft("p51d_mustang_120.json")
    liquid_field["propulsion"]["fuel_consumption"]["future_field"] = True
    liquid_law = read_aircraft("p51d_mustang_120.json")
    liquid_law["propulsion"]["fuel_consumption"]["law"] = "unknown_liquid_law"
    liquid_missing_tank = read_aircraft("p51d_mustang_120.json")
    del liquid_missing_tank["propulsion"]["fuel_consumption"]["tank_id"]
    liquid_missing_block = read_aircraft("p51d_mustang_120.json")
    del liquid_missing_block["propulsion"]["fuel_consumption"]
    return {
        "invalid:version": version,
        "invalid:capability_value": capability,
        "invalid:module_field": module_field,
        "invalid:battery_relation": battery_relation,
        "invalid:turbine_integrator": turbine_integrator,
        "invalid:gear_relation": gear_relation,
        "invalid:liquid_consumption_field": liquid_field,
        "invalid:liquid_consumption_law": liquid_law,
        "invalid:liquid_consumption_missing_tank": liquid_missing_tank,
        "invalid:missing_liquid_consumption": liquid_missing_block,
    }


class AircraftModuleTests(unittest.TestCase):
    def test_all_checked_in_sources_classify_and_keep_descriptor_modules(self):
        sources = fixed_wing_sources()
        self.assertGreaterEqual(len(sources), 10)
        for name, source in sources.items():
            with self.subTest(aircraft=name):
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

    def test_finite_liquid_gasoline_and_turbine_laws_are_registered(self):
        p51 = classify(read_aircraft("p51d_mustang_120.json"))
        self.assertTrue(p51["ok"], p51["errors"])
        self.assertIn("energy.finite_liquid_fuel.v1", p51["laws"])
        self.assertIn("propulsion.glow_prop.shaft_balance.v1", p51["laws"])
        self.assertIn("propulsion.shaft.v1", p51["modules"])
        self.assertFalse(p51["compiler_transforms"]["scale"])
        self.assertFalse(p51["compiler_transforms"]["weight"])
        self.assertFalse(p51["compiler_transforms"]["power"])

        turbine = classify(read_aircraft("sebart_avanti_s_a200.json"))
        self.assertTrue(turbine["ok"], turbine["errors"])
        self.assertIn("energy.finite_liquid_fuel.v1", turbine["laws"])
        self.assertIn("propulsion.turbine.spool.rk4.v1", turbine["laws"])

    def test_fuel_consumption_block_is_closed_and_bound_to_finite_energy(self):
        valid = read_aircraft("p51d_mustang_120.json")
        unknown_field = json.loads(json.dumps(valid))
        unknown_field["propulsion"]["fuel_consumption"]["future_field"] = True
        result = classify(unknown_field)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item["code"] == "module.field.unknown" for item in result["diagnostics"]))
        self.assertEqual(result["modules"], [])
        self.assertEqual(result["laws"], [])

        unknown_law = json.loads(json.dumps(valid))
        unknown_law["propulsion"]["fuel_consumption"]["law"] = "unknown_liquid_law"
        result = classify(unknown_law)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item["code"] == "module.section.selector.unknown" for item in result["diagnostics"]))

        missing_binding = json.loads(json.dumps(valid))
        del missing_binding["propulsion"]["fuel_consumption"]["tank_id"]
        result = classify(missing_binding)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item["code"] == "module.section.field.missing" for item in result["diagnostics"]))

        missing_block = json.loads(json.dumps(valid))
        del missing_block["propulsion"]["fuel_consumption"]
        result = classify(missing_block)
        self.assertFalse(result["ok"])
        self.assertTrue(any(item["code"] == "module.capability.relation" for item in result["diagnostics"]))

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
            source["id"]: projection(classify(source))
            for source in fixed_wing_sources().values()
        }
        python_results.update({key: projection(classify(source)) for key, source in parity_invalid_sources().items()})
        self.assertEqual(gdscript_results, python_results)


if __name__ == "__main__":
    unittest.main()
