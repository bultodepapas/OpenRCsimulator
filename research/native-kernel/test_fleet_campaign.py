#!/usr/bin/env python3
"""Failure-oriented tests for aggregation of native fleet evidence."""
from __future__ import annotations

import asyncio
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("fleet_campaign", HERE / "fleet_campaign.py")
assert SPEC is not None and SPEC.loader is not None
campaign = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(campaign)


def fixtures():
    a = {"aircraft": "fixed", "vehicle": "fixed-wing", "battery": "ideal", "case": "trim",
         "weather": "calm", "soft_hull": True, "default_battery": True}
    refusal = {"aircraft": "fixed", "vehicle": "fixed-wing", "battery": "ideal", "case": "runway",
               "weather": "crosswind", "soft_hull": False, "default_battery": True,
               "expected": "reference-refusal", "expected_refusal_reason": "exact reset refusal"}
    b = {"aircraft": "heli", "vehicle": "rotorcraft", "battery": "ideal", "case": "ground",
         "weather": "calm", "soft_hull": None, "default_battery": True, "expected": "flight"}
    manifest = {"format": "openrc-nk3-fleet-manifest v1", "aircraft": ["fixed", "heli"],
                "rows": [a, refusal, b]}
    binary, source, lock, engine, fleet = (x * 64 for x in "abcde")
    guard = {"binary_sha256": binary, "engine_sha256": engine, "fleet_sha256": fleet,
             "receipt": {"binary_sha256": binary, "source_sha256": source, "lock_sha256": lock},
             "reference_sources": {"app/a.gd": "1" * 64}}

    def run(requested, rotor):
        native = requested == "native"
        identity = {"backend": requested}
        if native:
            identity.update(abi_version=2, binary_sha256=binary, source_sha256=source, lock_sha256=lock)
        return {"complete": True, "requested": requested, "actual": requested, "identity": identity,
                "error": "", "reason": "", "warmup_completed": 2, "samples_completed": 3,
                "fingerprint_boundaries": 6, "end": {"tick": 5, "fault": "", "crashed": False,
                                                       "paused": False, "held": False},
                "fingerprint": "a" * 64, "aircraft_sha256": "b" * 64,
                "native_covered_every_tick": native, "context_calls": 5 if native else 0,
                "stage_calls": 20 if native else 0, "stage_in_use": "stage" if native else "reference",
                "replay_requested": 5 if rotor else 0, "replay_completed": 5 if rotor else 0,
                "replay_ok": rotor, "replay_native_covered": rotor and native}

    def flight(row):
        return {**row, "status": "pass", "reason": "", "fingerprint_equal": True,
                "reference": run("gdscript_reference", row["vehicle"] == "rotorcraft"),
                "native": run("native", row["vehicle"] == "rotorcraft")}

    def refused(row):
        source_row = {key: value for key, value in row.items() if key != "expected_refusal_reason"}
        reason = row["expected_refusal_reason"]
        return {**source_row, "status": "reference-refused", "reason": reason, "fingerprint_equal": False,
                "reference": {"complete": False, "requested": "gdscript_reference", "phase": "reset", "error": reason},
                "native": {"complete": False, "requested": "native", "phase": "reset", "error": reason}}

    def component(count):
        return {"count": count, "identical": count}

    def report(aircraft, rows, flights, refusals):
        components = {"literals": component(1), "fleet_pair": component(flights)}
        if refusals:
            components["fleet_reference_refusal"] = component(refusals)
        count = sum(x["count"] for x in components.values())
        command = ["godot", "--extension=res://native/kernel/openrc_native_kernel.gdextension",
                   f"--aircraft={aircraft}", "--warmup=2", "--samples=3"]
        harness = {name: "1" * 64 for name in ("research/native-kernel/oracle.gd",
            "research/native-kernel/trajectory.gd", "research/native-kernel/run.py", "research/native-kernel/build.py",
            "tools/godot/run_checked.py", "app/sim/native_stage.gd")}
        harness["research/native-kernel/fleet.gd"] = fleet
        return {"format": "openrc-nk3-fleet v2", "run_valid": True, "verdict": "pass", "failures": [],
                "self_test": {"passed": True}, "checked_run": {"ok": True, "complete": True,
                    "reason": "passed", "process_exit": 0, "counts": {"error": 0},
                    "missing_required_text": [], "required_text": ["NK3_ORACLE verdict=pass"], "command": command},
                "library": {"ok": True, "reason": ""}, "identity": {"backend": "native", "abi_version": 2},
                "build_receipt": copy.deepcopy(guard["receipt"]), "binary_sha256_before": binary, "binary_sha256_after": binary,
                "engine_sha256_before": engine, "engine_sha256_after": engine,
                "reference_sources_before": copy.deepcopy(guard["reference_sources"]),
                "reference_sources_after": copy.deepcopy(guard["reference_sources"]),
                "sources": {"res://physics/a.gd": "1" * 64}, "sources_after": {"res://physics/a.gd": "1" * 64},
                "harness_sources": harness, "engine": "engine", "seed": 1,
                "law_identity": {"law": "same"}, "fleet_scope": {"scope": "scoped",
                    "filters": {"aircraft": aircraft, "weather": "", "soft_hull": ""},
                    "declared_aircraft": ["fixed", "heli"], "declared_rows": 3, "selected_rows": len(rows),
                    "matrix_complete": False, "warmup_requested": 2, "samples_requested": 3, "failed": 0,
                    "flight_passed": flights, "reference_refused": refusals},
                "fleet": rows, "components": components,
                "total": {"compared": count, "identical": count, "mismatched": 0}}

    return manifest, {"fixed": report("fixed", [flight(a), refused(refusal)], 1, 1),
                      "heli": report("heli", [flight(b)], 1, 0)}, guard


class FleetCampaignTests(unittest.TestCase):
    def test_complete_union(self):
        manifest, reports, guard = fixtures()
        self.assertEqual(campaign.validate_reports(manifest, reports, guard, 2, 3),
                         {"declared": 3, "flight_passed": 2, "reference_refused": 1})

    def test_manifest_rejects_duplicates_and_missing_refusal_proof(self):
        manifest, _, _ = fixtures()
        manifest["rows"].append(copy.deepcopy(manifest["rows"][0]))
        with self.assertRaises(campaign.CampaignError):
            campaign.manifest_index(manifest)
        manifest, _, _ = fixtures()
        del manifest["rows"][1]["expected_refusal_reason"]
        with self.assertRaises(campaign.CampaignError):
            campaign.manifest_index(manifest)

    def test_missing_duplicate_and_filtered_shards_fail(self):
        def missing(m, r, g): del r["heli"]
        def duplicate(m, r, g): r["fixed"]["fleet"][1] = copy.deepcopy(r["fixed"]["fleet"][0])
        def extra(m, r, g): r["extra"] = r["heli"]
        def filter_weather(m, r, g): r["fixed"]["fleet_scope"]["filters"]["weather"] = "calm"
        def truncated(m, r, g): r["heli"]["fleet"] = []
        def wrong_aircraft(m, r, g): r["heli"]["fleet"][0]["aircraft"] = "fixed"
        for mutate in (missing, duplicate, extra, filter_weather, truncated, wrong_aircraft):
            with self.subTest(case=mutate.__name__):
                manifest, reports, guard = fixtures()
                mutate(manifest, reports, guard)
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_incomplete_fallback_and_changed_fingerprints_fail(self):
        mutations = [
            ("complete", False), ("actual", "gdscript_reference"), ("warmup_completed", 1),
            ("samples_completed", 2), ("fingerprint_boundaries", 5), ("context_calls", 4),
            ("stage_calls", 19), ("native_covered_every_tick", False), ("fingerprint", "e" * 64),
            ("aircraft_sha256", "e" * 64), ("stage_in_use", "_wheel_evaluate"),
        ]
        for key, value in mutations:
            with self.subTest(key=key):
                manifest, reports, guard = fixtures()
                reports["fixed"]["fleet"][0]["native"][key] = value
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)
        manifest, reports, guard = fixtures()
        reports["fixed"]["fleet"][0]["native"]["identity"]["binary_sha256"] = "0" * 64
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_heli_replay_requires_native_coverage(self):
        for field, value in (("replay_requested", 0), ("replay_completed", 4),
                             ("replay_ok", False), ("replay_native_covered", False)):
            with self.subTest(field=field):
                manifest, reports, guard = fixtures()
                reports["heli"]["fleet"][0]["native"][field] = value
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_refusal_requires_both_exact_reset_outcomes(self):
        mutations = [lambda r: r.update(status="pass"),
                     lambda r: r.update(fingerprint_equal=True),
                     lambda r: r["native"].update(phase="weather"),
                     lambda r: r["reference"].update(error="another failure"),
                     lambda r: r["native"].update(complete=True),
                     lambda r: r["native"].update(requested="gdscript_reference")]
        for mutate in mutations:
            manifest, reports, guard = fixtures()
            mutate(reports["fixed"]["fleet"][1])
            with self.assertRaises(campaign.CampaignError):
                campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_source_checks_and_checked_run_are_required(self):
        mutations = [
            lambda r: r.update(run_valid=False),
            lambda r: r["checked_run"].update(complete=False),
            lambda r: r["checked_run"]["counts"].update(error=1),
            lambda r: r["checked_run"]["command"].append("--weather=calm"),
            lambda r: r.update(binary_sha256_after="0" * 64),
            lambda r: r.update(engine_sha256_after="0" * 64),
            lambda r: r["reference_sources_after"].update({"app/changed.gd": "0" * 64}),
            lambda r: r["harness_sources"].update({"research/native-kernel/fleet.gd": "0" * 64}),
            lambda r: r["components"]["fleet_pair"].update(identical=0),
            lambda r: r["fleet_scope"].update(failed=False),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(case=index):
                manifest, reports, guard = fixtures()
                mutate(reports["fixed"])
                with self.assertRaises(campaign.CampaignError):
                    campaign.validate_reports(manifest, reports, guard, 2, 3)

    def test_live_source_mismatch_fails(self):
        _, reports, _ = fixtures()
        with self.assertRaises(campaign.CampaignError):
            campaign.validate_live_sources(reports["fixed"])

    def test_manifest_script_uses_actual_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            script = Path(temporary) / "manifest.gd"
            campaign.write_manifest_script(script, Path(temporary) / "manifest.json")
            source = script.read_text(encoding="utf-8")
            self.assertIn("_fleet_declared_rows()", source)
            self.assertIn("_fleet_expected_refusal(row", source)
            self.assertNotIn("FLEET_PATH", source)
            self.assertNotIn("OUTPUT_PATH", source)

    def test_failed_shard_cancels_other_running_work(self):
        async def scenario():
            active = asyncio.Event()
            cancelled = asyncio.Event()

            async def fake_shard(aircraft, _out, _semaphore, _warmup, _samples, _timeout):
                if aircraft == "bad":
                    await active.wait()
                    raise campaign.CampaignError("intentional shard failure")
                active.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled.set()
                    raise

            with mock.patch.object(campaign, "run_shard", side_effect=fake_shard):
                with self.assertRaises(campaign.CampaignError):
                    await campaign.run_shards(["bad", "running"], Path("."), 2, 2, 3, 10)
            self.assertTrue(cancelled.is_set())

        asyncio.run(scenario())

    def test_reuse_waits_for_final_checked_run_and_rejects_failure(self):
        async def scenario():
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "report.json"
                path.write_text('{"verdict":"pass"}', encoding="utf-8")

                async def finish():
                    await asyncio.sleep(0.01)
                    path.write_text('{"verdict":"pass","run_valid":true}', encoding="utf-8")

                writer = asyncio.create_task(finish())
                name, used = await campaign.wait_reused_report("heli", path, 4)
                await writer
                self.assertEqual((name, used), ("heli", path))
                path.write_text('{"verdict":"fail","run_valid":false}', encoding="utf-8")
                with self.assertRaises(campaign.CampaignError):
                    await campaign.wait_reused_report("heli", path, 1)

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
