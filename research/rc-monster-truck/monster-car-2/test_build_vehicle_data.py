#!/usr/bin/env python3
"""Verify the Monster Car 2 generator is fresh and source-sensitive."""

from __future__ import annotations

import json
import runpy
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
GENERATOR = Path(__file__).with_name("build_vehicle_data.py")
BUILDER = runpy.run_path(str(GENERATOR))
BUILD = BUILDER["build"]
SHA256 = BUILDER["sha256"]
SPEC = ROOT / "assets/vehicles/monster-car-2/datos_simulacion_1.json"
GLB = ROOT / "assets/vehicles/monster-car-2/monster_truck_nitro_1.glb"
COLLISION_GLB = ROOT / "monster car 2/monster_truck_colisiones_1.glb"
OUTPUT = ROOT / "app/data/vehicles/ground/monster_car_2.json"


def encode(model: dict) -> bytes:
    return (json.dumps(model, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


class VehicleDataGeneratorTests(unittest.TestCase):
    def test_checked_in_vehicle_data_is_fresh(self) -> None:
        generated = encode(BUILD(SPEC, GLB, COLLISION_GLB))
        self.assertEqual(OUTPUT.read_bytes(), generated)

    def test_disposable_source_mutation_changes_geometry_output(self) -> None:
        source_hash_before = SHA256(SPEC)
        baseline = BUILD(SPEC, GLB, COLLISION_GLB)
        with tempfile.TemporaryDirectory(prefix="openrc-mc2-generator-test-") as temporary:
            mutated_spec = Path(temporary) / SPEC.name
            shutil.copyfile(SPEC, mutated_spec)
            source = json.loads(mutated_spec.read_text(encoding="utf-8"))
            source["geometria"]["radio_rueda"] += 0.001
            mutated_spec.write_text(
                json.dumps(source, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            candidate = BUILD(mutated_spec, GLB, COLLISION_GLB)

        self.assertAlmostEqual(
            candidate["parameters"]["tire_radius_m"]["value"]
            - baseline["parameters"]["tire_radius_m"]["value"],
            0.001,
            places=12,
        )
        self.assertNotEqual(encode(candidate), encode(baseline))
        self.assertEqual(SHA256(SPEC), source_hash_before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
