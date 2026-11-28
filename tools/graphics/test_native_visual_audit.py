import importlib.util
import json
import signal
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest

import native_visual_audit as audit


class NativeVisualAuditTests(unittest.TestCase):
    def test_swaps_restore_after_exception_and_reject_concurrent_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "a.gdshader"
            path.write_bytes(b"current")
            saved = {path.name: b"current"}
            desired = {path.name: b"baseline"}
            with self.assertRaisesRegex(RuntimeError, "injected"):
                with audit.shader_variant(root, saved, desired):
                    self.assertEqual(path.read_bytes(), b"baseline")
                    raise RuntimeError("injected")
            self.assertEqual(path.read_bytes(), b"current")
            path.write_bytes(b"other edit")
            with self.assertRaisesRegex(ValueError, "Concurrent"):
                with audit.shader_variant(root, saved, desired):
                    self.fail("must reject before writing")
            self.assertEqual(path.read_bytes(), b"other edit")

    def test_shards_preserve_same_runner_orders_and_native_case_settings(self):
        for workload in audit.WORKLOADS:
            group, name = workload.split(":")
            blocks = audit.commands("/godot", "forward_plus", Path("/outputs"), workload)
            expected_order = audit.ORDER if group == "field" else audit.ORDER[:2]
            self.assertEqual(tuple(b["variant"] for b in blocks), expected_order)
            matched = set()
            for block in blocks:
                label = "field" if group == "field" else name
                self.assertEqual(set(block["commands"]), {"import", label})
                command = block["commands"][label]
                if group == "field":
                    self.assertEqual(block["field_cases"], [name])
                    self.assertIn("--resources", command)
                    for arg in ("--frames=31", "--motion=off", "--measure_render_time=on", "--cases=" + name):
                        self.assertIn(arg, command)
                    self.assertNotIn("detail-process", command)
                else:
                    self.assertNotIn("--resources", command)
                    self.assertIn("detail-process", command)
                matched.add(json.dumps(command).replace(block["block"], "fixed"))
            self.assertEqual(len(matched), 1)

    def test_post_save_signal_is_distinct_from_early_exit_and_external_kill(self):
        def run(code, grace):
            with subprocess.Popen([sys.executable, "-c", code]) as proc:
                return audit.observe_detail_shutdown(proc, lambda: "verified", grace, .01)
        natural = run("pass", 2)
        self.assertTrue(natural["accepted"])
        self.assertFalse(natural["signals_sent"])
        failed = run("raise SystemExit(13)", 2)
        self.assertEqual((failed["accepted"], failed["engine_returncode"]), (False, 13))
        killed = run("import os,signal; os.kill(os.getpid(), signal.SIGTERM)", 2)
        self.assertFalse(killed["accepted"])
        self.assertFalse(killed["signals_sent"])
        forced = run("import time; time.sleep(5)", .1)
        self.assertTrue(forced["forced_post_save_cleanup"])
        self.assertEqual(forced["signals_sent"], [signal.SIGTERM])
        self.assertTrue(forced["accepted"])
        self.assertEqual((forced["initial_verified_digest"], forced["pre_signal_verified_digest"],
                          forced["verified_digest"]), ("verified",) * 3)
        self.assertGreaterEqual(forced["first_signal_after_s"]-forced["first_verified_after_s"], .1)
        caught = run("import signal,time,sys; signal.signal(signal.SIGTERM,lambda *_:sys.exit(17)); time.sleep(5)", .4)
        self.assertFalse(caught["accepted"])
        self.assertEqual(caught["engine_returncode"], 17)

    def test_unstable_or_missing_image_evidence_cannot_authorize_cleanup(self):
        def missing():
            raise ValueError("incomplete")
        with subprocess.Popen([sys.executable, "-c", "pass"]) as proc:
            with self.assertRaisesRegex(ValueError, "incomplete"):
                audit.observe_detail_shutdown(proc, missing, .01, .01)
        with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(5)"]) as proc:
            try:
                snapshots = iter(("first", "changed"))
                with self.assertRaisesRegex(ValueError, "changed"):
                    audit.observe_detail_shutdown(proc, lambda: next(snapshots), .05, .01)
                self.assertIsNone(proc.poll())
            finally:
                proc.kill()

    @unittest.skipUnless(importlib.util.find_spec("PIL"), "Pinned visual environment supplies Pillow")
    def test_real_checked_runner_drains_short_log_and_rejects_late_engine_errors(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            fixture = out / "moon"
            fixture.mkdir()
            rows = []
            for name in audit.DETAIL["moon"][1]:
                image = Image.new("RGB", audit.SIZE)
                image.putpixel((2, 3), (255, 200, 100))
                image.save(fixture / (name + ".png"))
                rows.append({"file": name + ".png"})
            (fixture / "manifest.json").write_text(json.dumps(
                {"adapter": "llvmpipe", "engine": "fixture", "cases": rows}))
            header = "Vulkan 1.3 - Forward+ - Using Device #0: Mesa - llvmpipe (LLVM)"
            checked = [sys.executable, str(audit.ROOT / "tools/godot/run_checked.py"), "--out-dir", str(out / "checks"),
                       "--label", "moon", "--timeout", "10", "--require-text", "Verified detail-process receipt:", "--",
                       sys.executable, str(Path(audit.__file__)), "detail-process", "moon", "forward_plus", str(fixture),
                       sys.executable, "-c"]
            for marker, good in (("short stderr record", True), ("ERROR: simulated late fixture error", False)):
                child = f"import sys; print({header!r}, flush=True); print({marker!r},file=sys.stderr,flush=True)"
                result = subprocess.run([*checked, child], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(result.returncode == 0, good, result.stdout.decode(errors="replace"))
                lifecycle = json.loads((out / "moon-lifecycle.json").read_text())
                self.assertTrue(lifecycle["accepted"])
                self.assertEqual(lifecycle["engine_returncode"], 0)
            logs = [p.read_bytes() for p in (out / "checks").glob("*/engine.log")]
            self.assertTrue(any(b"short stderr record" in log and header.encode() in log for log in logs))
            self.assertTrue(any(b"ERROR: simulated late fixture error" in log for log in logs))
            first = fixture / rows[0]["file"]
            first.write_bytes(first.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, "Incomplete PNG"):
                audit.detail_snapshot("moon", "forward_plus", fixture)

    def test_metrics_suppress_zeros_and_drop_bootstrap(self):
        row = dict(timing_valid=True, render_timing_enabled=True,
                   frame_ms_raw=[1000, 1, 2, 3, 4], viewport_cpu_ms_raw=[0]*5, viewport_gpu_ms_raw=[0]*5,
                   video_memory=16, draws=8, visible_draws=5, shadow_draws=2, primitives=20)
        result = audit.metrics(row, 5)
        self.assertEqual(result["wall_ms_p50"], 2.5)
        self.assertEqual(result["throughput_fps"], 400)
        self.assertAlmostEqual(result["median_render_loop_fps"], (500 + 1000/3)/2)
        self.assertIsNone(result["viewport_gpu_poll_ms_median_freshness_unverified"])
        row["viewport_gpu_ms_raw"][2] = float("nan")
        with self.assertRaises(ValueError):
            audit.metrics(row, 5)

    def test_fallback_and_hardware_do_not_pass_as_requested_software_backend(self):
        log = "Vulkan 1.3 - Forward+ - Using Device #0: Mesa - llvmpipe (LLVM)"
        self.assertEqual(audit.renderer_line(log, "forward_plus"), log)
        for wrong in (log.replace("Forward+", "Mobile"), log.replace("llvmpipe", "RTX 3090")):
            with self.assertRaises(ValueError):
                audit.renderer_line(wrong, "forward_plus")

    def test_unregistered_and_untracked_runtime_inputs_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def git(*args):
                subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
            git("init", "-q")
            git("config", "user.email", "fixture@example.invalid")
            git("config", "user.name", "Audit Fixture")
            path = root / "app/render/lake/water.gdshader"
            path.parent.mkdir(parents=True)
            path.write_text("a")
            git("add", ".")
            git("commit", "-qm", "baseline")
            base = audit.git("rev-parse", "HEAD", root=root).decode().strip()
            path.write_text("b")
            git("add", ".")
            git("commit", "-qm", "candidate")
            self.assertEqual(audit.source_changes(base, root=root), ["app/render/lake/water.gdshader"])
            extra = root / "app/project.godot"
            extra.write_text("[application]")
            with self.assertRaisesRegex(ValueError, "clean"):
                audit.source_changes(base, root=root)
            git("add", ".")
            git("commit", "-qm", "unregistered change")
            with self.assertRaisesRegex(ValueError, "Unreviewed"):
                audit.source_changes(base, root=root)

    def test_control_evidence_uses_real_materials_and_excludes_image_outcomes(self):
        rows = []
        for name in audit.CONTROL_IDS:
            age = {"lens_curtain_partial": 0.5, "lens_curtain_held": 1.5}.get(name, 0)
            if name.startswith("dirt_"):
                controls = {"shader": "res://render/ground.gdshader", "surface": "DirtLoopSurface",
                            "mesh_vertices": 128, "track_coverage": 1, "light_visible": name != "dirt_light_off",
                            "light_specular": {"dirt_specular_035": 0.35, "dirt_specular_050": 0.5}.get(name, 0)}
            elif name == "lens_disabled":
                controls = {"enabled": False, "shader": "", "age_s": 0}
            else:
                controls = {"enabled": True, "shader": "res://render/lens/lens_film.gdshader", "age_s": age,
                            "seed": 1253, "event_key": "native-shader-controls-pilot", "view": "pilot", "film_seed": 0.2}
            rows.append({"view": name, "eye": [0, 0, 2], "at": [0, 0, 0], "fov": 32, "clock_s": 3.0 + age,
                         "controls": controls, "sha256": "0"*64, "sampled_luma": 0.25})
        report = {"records": rows, "complete": True, "method": "forward_plus", "viewport": [1920, 1080],
                  "seed": 1253, "adapter": "software", "driver": "vulkan", "engine": "fixture"}
        original = audit.common_conditions("controls", report, "forward_plus")
        rows[0]["sampled_luma"] = 0.6
        rows[0]["sha256"] = "1"*64
        self.assertEqual(original, audit.common_conditions("controls", report, "forward_plus"))
        rows[3]["controls"]["light_specular"] = 0.35
        with self.assertRaisesRegex(ValueError, "light state"):
            audit.common_conditions("controls", report, "forward_plus")
        rows[3]["controls"]["light_specular"] = 0.5
        rows[-1]["controls"]["shader"] = "res://wrong_shader.gdshader"
        with self.assertRaisesRegex(ValueError, "lens material"):
            audit.common_conditions("controls", report, "forward_plus")

    def test_reject_inactive_storm_and_fallback_paint(self):
        rows = [{"view": view, "vehicle": "turbo-lumber-evolution", "skin": "aserradero", "shader": audit.PAINT_SHADER,
                 "environment": "flight", "zoom": 1.0, "fov": 35, "position": [0, 1, 2], "target": [0, 0, 0]}
                for view in ("front34", "top")]
        self.assertEqual(set(audit.common_conditions("paint", rows, "gl_compatibility")), {"front34", "top"})
        rows[1]["shader"] = ""
        with self.assertRaisesRegex(ValueError, "activate Aserradero"):
            audit.common_conditions("paint", rows, "gl_compatibility")
        storm = {"viewport": [1920, 1080], "renderer": "gl_compatibility", "images": [
            {"id": name, "bank": {"enabled": True, "rain_count": 3, "seed": 1253}} for name in audit.DETAIL["storm"][1]]}
        self.assertEqual(audit.common_conditions("storm", storm, "gl_compatibility"), storm)
        storm["images"][0]["bank"]["rain_count"] = 0
        with self.assertRaisesRegex(ValueError, "activate seeded rain"):
            audit.common_conditions("storm", storm, "gl_compatibility")

    def test_matched_camera_and_lighting_are_checked_before_differences(self):
        def observation(eye, fov):
            return {"roof": {"device": "software device", "conditions": {"eye": eye, "fov": fov}}}
        audit.verify_matched_inputs([observation([0, 1, 2], 60)] * 2)
        with self.assertRaisesRegex(ValueError, "Unmatched"):
            audit.verify_matched_inputs([observation([0, 1, 2], 60), observation([0, 2, 2], 60)])

    def test_matched_commands_and_single_dimension_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            blocks = audit.commands("/engine", "forward_plus", out)
            self.assertEqual(tuple(row["variant"] for row in blocks), audit.ORDER)
            for kind, (path, _) in audit.DETAIL.items():
                self.assertIn(b"Vector2i(1920, 1080)", audit.fixture_bytes(path), kind)
            def normalize(row):
                return json.dumps(row["commands"]["field"]).replace(row["block"], "block")
            self.assertEqual(len({normalize(row) for row in blocks}), 1)
            self.assertEqual(list(out.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
