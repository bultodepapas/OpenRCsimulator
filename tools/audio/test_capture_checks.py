"""Focused regression fixtures for the two native audio capture checkers."""
from __future__ import annotations

import copy
import json
import math
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

import numpy as np

import check_captures
import check_fleet_sequence
import check_mechanical_capture


LIVE_FRAMES = 480
MIX_RATE = 48_000
STAGE_NAMES = (
    "idle",
    "servo_small_slow",
    "servo_large_fast",
    "simultaneous_servos",
    "gear_extension_reversal_interruption_endpoint",
    "near_far_listener_camera_motion",
    "engine_mask_0",
    "engine_mask_05",
    "engine_mask_1",
    "pause_reset_rewind_detach_reattach_configure",
)
PROFILES = ("standard_electric", "standard_pneumatic", "high_torque_electric", "high_torque_pneumatic")


def write_wave(path: Path, pcm: np.ndarray, rate: int = MIX_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.astype("<i2", copy=False).tobytes())


def frame_bookkeeping(recorded: int, *, flushed: int = 0) -> dict:
    pushed = recorded + flushed
    return {
        "buffer_length_frames": MIX_RATE,
        "initial": {"pushed_frames": 0, "discarded_frames": 0, "available_frames": 0},
        "final": {
            "pushed_frames": pushed,
            "discarded_frames": 0,
            "available_frames_before_flush": flushed,
            "flushed_frames": flushed,
            "available_frames_after_flush": 0,
        },
        "pushed_frames": pushed,
        "recorded_frames": recorded,
        "flushed_frames": flushed,
        "truncated_frames": 0,
        "overflow_discarded_frames": 0,
        "unaccounted_pushed_frames": 0,
    }


class CaptureCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tempdir = tempfile.TemporaryDirectory(prefix="openrc-audio-checks-")
        cls.root = Path(cls.tempdir.name)
        cls.live_prefix = cls.root / "gameplay"
        cls._write_live_fixture()
        cls.mechanical_dir = cls.root / "mechanical"
        cls._write_mechanical_fixture()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    @classmethod
    def _write_live_fixture(cls) -> None:
        pcm = np.full((LIVE_FRAMES, 2), 3000, dtype="<i2")
        write_wave(cls.live_prefix.with_suffix(".wav"), pcm)
        peak_dbfs = 20.0 * math.log10(3000.0 / 32768.0)
        report = {
            "format": "openrc-audio-gameplay-v1",
            "arguments": {"wildlife-review": True},
            "driver": "WASAPI",
            "display": "headless",
            "requested_fps": 60,
            "aircraft": "fixture-aircraft",
            "frames": LIVE_FRAMES,
            "mix_rate": MIX_RATE,
            "captured_seconds": LIVE_FRAMES / MIX_RATE,
            "capture_wall_seconds": LIVE_FRAMES / MIX_RATE,
            "capture_effect_removed": True,
            "capture_bookkeeping": frame_bookkeeping(LIVE_FRAMES),
            "probe_sha256": "a" * 64,
            "finite_samples": True,
            "peak_dbfs": peak_dbfs,
            "rms_dbfs": peak_dbfs,
            "discarded_frames": 0,
            "soundscape_update_p95_us": 100,
            "soundscape_update_max_us": 200,
            "soundscape_timing_sample_count": 1,
            "distance_min_m": 1.0,
            "distance_max_m": 10.0,
            "events": [],
            "final_paused": False,
            "final_tick": 10,
            "wildlife_events": [{"species": "songbird", "variant": "one"}],
        }
        cls.live_report = report
        cls._write_json(cls.live_prefix.with_suffix(".json"), report)

    @classmethod
    def _write_mechanical_fixture(cls) -> None:
        stages: list[dict] = []
        samples = 0
        for profile in PROFILES:
            for name in STAGE_NAMES:
                amplitude = {
                    "idle": 0,
                    "servo_small_slow": 1000,
                    "servo_large_fast": 3000,
                    "simultaneous_servos": 2000,
                    "gear_extension_reversal_interruption_endpoint": 2000,
                    "near_far_listener_camera_motion": 2000,
                    "engine_mask_0": 0,
                    "engine_mask_05": 1000,
                    "engine_mask_1": 2000,
                    "pause_reset_rewind_detach_reattach_configure": 2000,
                }[name]
                pcm = np.zeros((MIX_RATE, 2), dtype="<i2")
                if name == "near_far_listener_camera_motion":
                    pcm[: MIX_RATE // 2] = amplitude
                elif name == "pause_reset_rewind_detach_reattach_configure":
                    pcm[: int(0.4 * MIX_RATE)] = amplitude
                elif amplitude:
                    pcm[:] = amplitude
                write_wave(cls.mechanical_dir / profile / f"{name}.wav", pcm)
                samples += len(pcm)
                stages.append({
                    "profile": profile,
                    "name": name,
                    "frames": len(pcm),
                    "mix_rate_hz": MIX_RATE,
                    "wall_seconds": 1.0,
                    "max_motion_voice_count": 0,
                    "max_event_voice_count": 0,
                    "timed_out": False,
                    "flushed_frames_before_stage": 0,
                })
        report = {
            "format": "openrc-mechanical-audio-staged-probe-v1",
            "driver": "WASAPI",
            "mix_rate_hz": MIX_RATE,
            "captured_seconds": samples / MIX_RATE,
            "capture_wall_seconds": 40.0,
            "scripted_wall_seconds": 40.0,
            "discarded_frames": 0,
            "capture_effect_removed": True,
            "probe_sha256": "b" * 64,
            "capture_bookkeeping": frame_bookkeeping(samples),
            "stage_results": stages,
        }
        report["capture_bookkeeping"]["staged_capture_memory_limit_seconds"] = 60.0
        cls.mechanical_report = report
        cls._write_json(cls.mechanical_dir / "report.json", report)

    @staticmethod
    def _write_json(path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, allow_nan=True), encoding="utf-8")

    def _write_live_report(self, report: dict) -> None:
        self._write_json(self.live_prefix.with_suffix(".json"), report)

    def _write_mechanical_report(self, report: dict) -> None:
        self._write_json(self.mechanical_dir / "report.json", report)

    def test_valid_gameplay_fixture_passes(self) -> None:
        self._write_live_report(copy.deepcopy(self.live_report))
        result = check_captures.analyze(self.live_prefix)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["capture_bookkeeping"]["unaccounted_pushed_frames"], 0)
        self.assertEqual(len(result["checker_sha256"]), 64)

    def test_gameplay_wall_time_must_be_finite_and_positive(self) -> None:
        for wall in (None, float("nan"), 0.0, -1.0):
            with self.subTest(wall=wall):
                report = copy.deepcopy(self.live_report)
                if wall is None:
                    report.pop("capture_wall_seconds")
                else:
                    report["capture_wall_seconds"] = wall
                self._write_live_report(report)
                result = check_captures.analyze(self.live_prefix)
                self.assertFalse(result["passed"])
                self.assertIn("capture wall time is missing, non-finite, or non-positive", result["failures"])

    def test_gameplay_bookkeeping_and_sample_finiteness_are_gated(self) -> None:
        report = copy.deepcopy(self.live_report)
        report["capture_bookkeeping"]["unaccounted_pushed_frames"] = 1
        report["finite_samples"] = False
        self._write_live_report(report)
        result = check_captures.analyze(self.live_prefix)
        self.assertFalse(result["passed"])
        self.assertIn("capture pushed/recorded/flushed frame counts do not balance", result["failures"])
        self.assertIn("capture contains non-finite samples", result["failures"])

    def test_valid_mechanical_fixture_passes(self) -> None:
        self._write_mechanical_report(copy.deepcopy(self.mechanical_report))
        result = check_mechanical_capture.analyze(self.mechanical_dir)
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["stage_wav_seconds"], 40.0)
        self.assertEqual(len(result["checker_sha256"]), 64)

    def test_mechanical_wall_time_must_be_finite_and_positive(self) -> None:
        for wall in (None, float("nan"), 0.0, -1.0):
            with self.subTest(wall=wall):
                report = copy.deepcopy(self.mechanical_report)
                if wall is None:
                    report.pop("capture_wall_seconds")
                else:
                    report["capture_wall_seconds"] = wall
                self._write_mechanical_report(report)
                result = check_mechanical_capture.analyze(self.mechanical_dir)
                self.assertFalse(result["passed"])
                self.assertIn("Capture wall time is missing, non-finite, or non-positive", result["failures"])

    def test_mechanical_unbalanced_bookkeeping_fails(self) -> None:
        report = copy.deepcopy(self.mechanical_report)
        report["capture_bookkeeping"]["unaccounted_pushed_frames"] = 1
        self._write_mechanical_report(report)
        result = check_mechanical_capture.analyze(self.mechanical_dir)
        self.assertFalse(result["passed"])
        self.assertIn("Capture pushed/recorded/flushed frame counts do not balance", result["failures"])


class FleetCatalogScopeTests(unittest.TestCase):
    @staticmethod
    def rows(ids: list[str]) -> list[dict]:
        return [{"aircraft": value, "live_contact_sequence_complete_without_route_failure": True,
                 "continuous_flight_qualified": True} for value in ids]

    def test_listing_follows_catalog_growth_and_shrinkage(self) -> None:
        for count in (1, 9, 11, 14):
            with self.subTest(count=count):
                ids = [f"fixture-{i}" for i in range(count)]
                output = "\n".join("FLEET_AIRCRAFT_ID=" + value for value in ids)
                with patch("check_fleet_sequence.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                    self.assertEqual(check_fleet_sequence.list_aircraft(Path("fixture")), ids)

    def test_invalid_listings_refuse(self) -> None:
        for output in ("", "FLEET_AIRCRAFT_ID=", "FLEET_AIRCRAFT_ID=a\nFLEET_AIRCRAFT_ID=a"):
            with self.subTest(output=output), patch("check_fleet_sequence.subprocess.run", return_value=subprocess.CompletedProcess([], 0, output, "")):
                with self.assertRaises(RuntimeError):
                    check_fleet_sequence.list_aircraft(Path("fixture"))

    def test_full_catalog_qualification_has_no_historical_count(self) -> None:
        for count in (1, 9, 11, 14):
            ids = [f"fixture-{i}" for i in range(count)]
            summary = check_fleet_sequence.batch_scope(ids, ids, self.rows(ids))
            self.assertTrue(summary["catalog_coverage_complete"])
            self.assertTrue(summary["all_continuous_flights_qualified"])
            self.assertTrue(summary["all_live_contact_sequences_complete_without_route_failure"])

    def test_selected_success_does_not_claim_whole_fleet(self) -> None:
        summary = check_fleet_sequence.batch_scope(["a", "b"], ["a"], self.rows(["a"]))
        self.assertTrue(summary["all_requested_continuous_flights_qualified"])
        self.assertFalse(summary["catalog_coverage_complete"])
        self.assertFalse(summary["all_continuous_flights_qualified"])
        self.assertEqual(summary["requested_aircraft_ids"], ["a"])

    def test_duplicate_missing_or_wrong_results_never_qualify(self) -> None:
        for requested, observed in ((["a", "a"], ["a", "a"]), (["a", "b"], ["a"]),
                                    (["a", "b"], ["a", "a"]), (["a"], ["b"]), ([], [])):
            summary = check_fleet_sequence.batch_scope(["a", "b"], requested, self.rows(observed))
            self.assertFalse(summary["all_requested_continuous_flights_qualified"])
            self.assertFalse(summary["all_continuous_flights_qualified"])

    def test_unmeasured_or_truthy_strings_are_not_success(self) -> None:
        for value in (None, False, "true", 1):
            rows = self.rows(["a"])
            rows[0]["continuous_flight_qualified"] = value
            summary = check_fleet_sequence.batch_scope(["a"], ["a"], rows)
            self.assertFalse(summary["all_continuous_flights_qualified"])
            self.assertTrue(summary["all_live_contact_sequences_complete_without_route_failure"])


class HullCaptureCheckTests(unittest.TestCase):
    """Synthetic checker fixtures exercise logic, never masquerade as native PCM."""

    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="openrc-hull-check-")
        self.addCleanup(self.tempdir.cleanup)
        self.prefix = Path(self.tempdir.name) / "hull"
        self.rate = 48000
        self.pcm = np.zeros((12 * self.rate, 2), dtype="<i2")
        self.pcm[int(2.04 * self.rate):int(3.95 * self.rate)] = 1000
        self.pcm[int(7.04 * self.rate):int(11.95 * self.rate)] = 2000
        boundaries = (0, 1, 2, 4, 5, 6, 7, 12)
        sources = {path: "a" * 64 for path in check_captures.HULL_SOURCES}
        sources["probe"] = "c" * 64
        aircraft = "jensen-das-ugly-stik-60"
        source = check_captures.HULL_AIRCRAFT[aircraft]
        sources[source] = "d" * 64
        sources["res://landscapes/green_paradise/landscape.gd"] = "e" * 64
        sources["res://landscapes/green_paradise/field.json"] = "f" * 64
        phases, accepted, rendered = [], [], []
        for i, name in enumerate(check_captures.HULL_PHASES):
            phase = {"index": i, "name": name, "start_wall_s": boundaries[i],
                     "end_wall_s": boundaries[i+1], "start_frame": boundaries[i]*self.rate,
                     "end_frame": boundaries[i+1]*self.rate, "reset_accepted": True,
                     "emitted_before": int(i > 2), "emitted_after": int(i >= 2),
                     "epoch": (1, 2, 3, 3, 3, 4, 5)[i], "start_tick": 0, "generation": 3 if i < 5 else 4,
                     "start_accepted_index": i, "end_accepted_index": i+1,
                     "start_render_index": i, "end_render_index": i+1}
            phases.append(phase)
            accepted.append({"epoch": phase["epoch"], "phase": i, "tick": 1, "generation": phase["generation"],
                             "geometric_contacts": int(i in (1, 2)), "loaded_contacts": int(i == 2),
                             "friction_power_w": 28.8 if i == 2 else 0.0,
                             "contact_ids": ["probe_wing_tip"] if i == 2 else [], "queued": 0,
                             "emitted": int(i >= 2), "tagged_voices": int(i == 2), "render_index": i,
                             "paused": i in (3, 6), "terminal": i == 6, "available": True,
                             "cancellation_pending": False, "wall_s": boundaries[i]+.1,
                             "sim_time_s": 1/240, "reason": "", "clock_origin": "accepted_step"})
            rendered.append({"wall_s": boundaries[i]+.5, "phase": i, "tick": 1,
                             "generation": phase["generation"], "render_index": i+1, "paused": i in (3, 6),
                             "terminal": i == 6, "primary_played": i == 6, "max_voices": 8,
                             "active_voices": 1 if i == 2 else (3 if i == 6 else 0),
                             "active_tagged_voices": int(i == 2), "fault_reason": "",
                             "diagnostics": {"queued": 0, "emitted": int(i >= 2), "overflow": 0,
                                             "stale": 0, "invalid": 0, "tagged_voices": int(i == 2)}})
        self.report = {"format": "openrc-audio-gameplay-v1", "arguments": {"hull-scrape-review": True},
                       "driver": "WASAPI", "display": "headless", "requested_fps": 60,
                       "aircraft": aircraft, "frames": len(self.pcm), "mix_rate": self.rate,
                       "captured_seconds": 12., "capture_wall_seconds": 12., "capture_effect_removed": True,
                       "capture_bookkeeping": frame_bookkeeping(len(self.pcm)), "probe_sha256": "c" * 64,
                       "finite_samples": True, "peak_dbfs": -20., "rms_dbfs": -30., "discarded_frames": 0,
                       "soundscape_update_p95_us": 600, "soundscape_update_max_us": 1200,
                       "soundscape_timing_sample_count": 20, "distance_min_m": 10., "distance_max_m": 30.,
                       "events": [], "hull_scrape_review": {
                           "format": "openrc-hull-scrape-native-review-v1",
                           "capture_bus_role": "crash_fx_after_local_limiter", "capture_bus_send": "Master",
                           "landscape_id": "green_paradise", "field_source": "res://landscapes/green_paradise/field.json",
                           "lake_enabled": False, "lake_identity": "",
                           "master_capture": False, "power_sampling": "accepted_endpoint_instantaneous_power",
                           "cue_age_clock": "accepted_simulation_time", "cue_max_age_s": .25,
                           "law_identity": "fixture-current-law", "failures": [], "truncated": False,
                           "source_before": sources, "source_after": sources.copy(),
                           "source_files_unchanged": True, "aircraft_source": source,
                           "phases": phases, "accepted": accepted, "render": rendered}}

    def analyze(self) -> dict:
        write_wave(self.prefix.with_suffix(".wav"), self.pcm, self.rate)
        self.prefix.with_suffix(".json").write_text(json.dumps(self.report))
        return check_captures.analyze(self.prefix)

    def test_hull_valid_fixture_keeps_pcm_and_source_facts_separate(self) -> None:
        result = self.analyze()
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["review_kind"], "hull_scrape")
        self.assertGreater(result["hull_scrape"]["phase_pcm"]["brush"]["peak_linear"], 0)
        self.assertEqual(result["hull_scrape"]["scope"], "CrashFX bus only, no Master/combined mix or acoustic calibration")

    def test_hull_default_field_uses_actual_dry_scope_with_configured_lake(self) -> None:
        review = self.report["hull_scrape_review"]
        sources = review["source_before"]
        sources.pop("res://landscapes/green_paradise/landscape.gd")
        sources.pop("res://landscapes/green_paradise/field.json")
        sources["res://landscapes/club_field/landscape.gd"] = "e" * 64
        sources["res://data/fields/default.json"] = "f" * 64
        sources.update({path: "b" * 64 for path in check_captures.HULL_LAKE_SOURCES})
        review.update(landscape_id="club_field", field_source="res://data/fields/default.json",
                      lake_enabled=True, lake_identity="1" * 64, source_after=sources.copy())
        result = self.analyze()
        self.assertTrue(result["passed"], result["failures"])

    def test_hull_early_terminal_is_not_relabelled_success(self) -> None:
        self.report["hull_scrape_review"]["accepted"][2]["terminal"] = True
        self.assertIn("hull fixture terminated before its declared terminal phase", self.analyze()["failures"])

    def test_hull_reordered_or_reassigned_samples_refuse(self) -> None:
        review = self.report["hull_scrape_review"]
        review["accepted"][0], review["accepted"][1] = review["accepted"][1], review["accepted"][0]
        self.assertIn("hull accepted sample is reassigned to another phase/epoch/generation", self.analyze()["failures"])

    def test_hull_epoch_and_generation_are_bound_to_phase(self) -> None:
        self.report["hull_scrape_review"]["accepted"][2]["epoch"] += 1
        self.assertIn("hull accepted sample is reassigned to another phase/epoch/generation", self.analyze()["failures"])

    def test_hull_render_generation_and_frame_order_are_bound(self) -> None:
        self.report["hull_scrape_review"]["render"][1]["generation"] += 1
        self.assertIn("hull render sample is reassigned to another phase/generation", self.analyze()["failures"])

    def test_hull_partial_or_overlapping_partitions_refuse(self) -> None:
        review = self.report["hull_scrape_review"]
        for field, value in (("start_accepted_index", 1), ("end_accepted_index", 2),
                             ("start_render_index", True), ("end_render_index", 2)):
            with self.subTest(field=field):
                prior = review["phases"][0][field]
                review["phases"][0][field] = value
                self.assertIn("hull trace phase index partitions are invalid or incomplete", self.analyze()["failures"])
                review["phases"][0][field] = prior

    def test_hull_wall_and_render_chronology_refuse_reordering(self) -> None:
        row = self.report["hull_scrape_review"]["accepted"][2]
        row["wall_s"] = .5
        self.assertIn("hull accepted wall/render clocks are reordered or outside their phase", self.analyze()["failures"])

    def test_hull_render_clock_cannot_be_relabelled(self) -> None:
        self.report["hull_scrape_review"]["render"][2]["render_index"] = 1
        self.assertIn("hull render wall/frame clocks are reordered or outside their phase", self.analyze()["failures"])

    def test_hull_only_true_leading_reset_publication_row_is_allowed(self) -> None:
        review = self.report["hull_scrape_review"]
        phase = review["phases"][5]
        phase["fixture"] = "existing public Session.reset; new physical generation"
        new_row = copy.deepcopy(review["accepted"][5])
        new_row.update(tick=0, sim_time_s=0., clock_origin="fixture_boundary", render_index=5)
        old_row = copy.deepcopy(new_row)
        old_row.update(generation=review["phases"][4]["generation"], clock_origin="accepted_step")
        review["accepted"][5:6] = [old_row, new_row]
        phase["end_accepted_index"] += 1
        review["phases"][6]["start_accepted_index"] += 1
        review["phases"][6]["end_accepted_index"] += 1
        result = self.analyze()
        self.assertTrue(result["passed"], result["failures"])
        # This is a narrow exception: a repeated old row after the committed
        # generation, or an old row without the exact post-return boundary, fails.
        new_row["generation"] = old_row["generation"]
        self.assertIn("hull reset publication generation transition is invalid", self.analyze()["failures"])

    def test_hull_unknown_mixed_generation_is_rejected(self) -> None:
        self.report["hull_scrape_review"]["accepted"][2]["generation"] -= 1
        self.assertIn("hull reset publication generation transition is invalid", self.analyze()["failures"])

    def test_hull_trailing_unowned_samples_are_rejected(self) -> None:
        self.report["hull_scrape_review"]["accepted"].append(copy.deepcopy(self.report["hull_scrape_review"]["accepted"][-1]))
        self.assertIn("hull trace phase index partitions are invalid or incomplete", self.analyze()["failures"])

    def test_hull_duplicated_clock_is_rejected_inside_valid_partition(self) -> None:
        review = self.report["hull_scrape_review"]
        row = copy.deepcopy(review["accepted"][2])
        review["accepted"].insert(3, row)
        review["phases"][2]["end_accepted_index"] += 1
        for phase in review["phases"][3:]:
            phase["start_accepted_index"] += 1
            phase["end_accepted_index"] += 1
        self.assertIn("hull accepted clock was duplicated", self.analyze()["failures"])

    def test_hull_same_phase_old_generation_after_new_boundary_refuses(self) -> None:
        review = self.report["hull_scrape_review"]
        phase = review["phases"][5]
        phase["fixture"] = "existing public Session.reset; new physical generation"
        boundary = copy.deepcopy(review["accepted"][5])
        boundary.update(tick=0, sim_time_s=0., clock_origin="fixture_boundary", render_index=5)
        prior = copy.deepcopy(boundary)
        prior.update(generation=review["phases"][4]["generation"], clock_origin="accepted_step")
        review["accepted"][5:6] = [prior, boundary, copy.deepcopy(prior)]
        phase["end_accepted_index"] += 2
        review["phases"][6]["start_accepted_index"] += 2
        review["phases"][6]["end_accepted_index"] += 2
        self.assertIn("hull accepted sample is reassigned to another phase/epoch/generation", self.analyze()["failures"])

    def test_hull_emission_counter_does_not_prove_pcm(self) -> None:
        self.pcm[2*self.rate:4*self.rate] = 0
        result = self.analyze()
        self.assertFalse(result["passed"])
        self.assertIn("brush has no independent nonzero CrashFX PCM interval", result["failures"])

    def test_hull_pcm_does_not_prove_loaded_source(self) -> None:
        row = self.report["hull_scrape_review"]["accepted"][2]
        row.update(loaded_contacts=0, contact_ids=[], friction_power_w=0.)
        result = self.analyze()
        self.assertIn("brush phase lacks actual loaded source and native tagged playback facts", result["failures"])

    def test_hull_opening_label_does_not_prove_geometric_overlap(self) -> None:
        self.report["hull_scrape_review"]["accepted"][1]["geometric_contacts"] = 0
        result = self.analyze()
        self.assertIn("opening overlap did not demonstrate zero clamped friction without grains", result["failures"])

    def test_hull_opening_loaded_grains_are_rejected(self) -> None:
        self.report["hull_scrape_review"]["accepted"][1].update(loaded_contacts=1, contact_ids=["probe"], friction_power_w=1., queued=1)
        self.assertFalse(self.analyze()["passed"])

    def test_hull_pause_pcm_must_be_measured_silent(self) -> None:
        self.pcm[4*self.rate:5*self.rate] = 500
        self.assertIn("pause CrashFX PCM did not reach silence", self.analyze()["failures"])

    def test_hull_wrong_bus_or_master_role_is_not_accepted(self) -> None:
        self.report["hull_scrape_review"]["capture_bus_role"] = "soundscape"
        self.assertIn("hull PCM must identify the separate CrashFX bus and exclude Master capture", self.analyze()["failures"])

    def test_hull_driver_and_source_stability_are_required(self) -> None:
        self.report["driver"] = "Dummy"
        self.report["hull_scrape_review"]["source_after"]["probe"] = "b" * 64
        result = self.analyze()
        self.assertIn("hull review requires an actual native audio driver", result["failures"])
        self.assertIn("hull source/asset/aircraft identity is incomplete or changed during capture", result["failures"])

    def test_hull_material_or_work_claim_cannot_replace_sampling_contract(self) -> None:
        self.report["hull_scrape_review"]["power_sampling"] = "integrated_heat"
        self.assertIn("hull power sampling or accepted-simulation cue-age contract is invalid", self.analyze()["failures"])

    def test_hull_terminal_live_tags_are_rejected(self) -> None:
        self.report["hull_scrape_review"]["render"][6]["diagnostics"]["tagged_voices"] = 1
        self.assertIn("actual terminal handoff did not exclusively cancel living-hull scrape", self.analyze()["failures"])

    def test_hull_malformed_facts_fail_without_exception(self) -> None:
        for value in (None, True, 1, "bad", []):
            with self.subTest(value=value):
                original = self.report["hull_scrape_review"]["accepted"][0]
                self.report["hull_scrape_review"]["accepted"][0] = value
                self.assertFalse(self.analyze()["passed"])
                self.report["hull_scrape_review"]["accepted"][0] = original

    def test_hull_boolean_or_nonfinite_count_is_not_a_factual_clock(self) -> None:
        self.report["hull_scrape_review"]["accepted"][0]["tick"] = True
        self.assertFalse(self.analyze()["passed"])

    def test_hull_phase_names_without_samples_are_insufficient(self) -> None:
        self.report["hull_scrape_review"]["accepted"] = []
        self.assertIn("hull phase or accepted/render sample inventory is invalid", self.analyze()["failures"])

    def test_hull_notifications_cannot_masquerade_as_physics_steps(self) -> None:
        for row in self.report["hull_scrape_review"]["accepted"]:
            row["clock_origin"] = "pause_notification"
        self.assertIn("hull review has no actual accepted physics advancement", self.analyze()["failures"])

    def test_hull_frame_bookkeeping_remains_mandatory(self) -> None:
        self.report["capture_bookkeeping"]["unaccounted_pushed_frames"] = 1
        self.assertIn("capture pushed/recorded/flushed frame counts do not balance", self.analyze()["failures"])

    def test_legacy_adapter_budget_gate_remains_unchanged(self) -> None:
        original = copy.deepcopy(CaptureCheckTests.live_report)
        original["soundscape_update_p95_us"] = 600
        self.prefix.with_suffix(".json").write_text(json.dumps(original))
        write_wave(self.prefix.with_suffix(".wav"), np.full((LIVE_FRAMES, 2), 3000, dtype="<i2"))
        self.assertIn("adapter update p95 exceeded 0.5 ms budget", check_captures.analyze(self.prefix)["failures"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
