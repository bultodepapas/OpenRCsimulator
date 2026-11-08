"""PT1h-R7: debugctl.py against a fake loopback bridge (no Godot): argument parsing, token, exit codes, output."""
from __future__ import annotations

import contextlib
import csv
import errno
import random
import io
import tempfile
import time
import json
import os
import socket
import sys
import threading
import unittest
from unittest.mock import Mock, patch
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "godot"))
import debugctl  # noqa: E402


class FakeBridge:
    """Answers each connection's single JSON line like the Godot bridge and records the requests."""

    def __init__(self) -> None:
        self.server = socket.create_server(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.requests: list[dict] = []
        self.screens = ["home"]
        self.stuck = False
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                with conn.makefile() as stream:
                    line = stream.readline()
                if not line:
                    continue # Port-reservation probes connect without sending a bridge request.
                request = json.loads(line)
                self.requests.append(request)
                if request["cmd"] == "ui":
                    result = {"scope": "AppRoot/Home", "focus": "AppRoot/Home/Fly", "controls": [
                        {"path": "AppRoot/Home/Fly", "type": "Button", "text": "Fly", "focused": True, "disabled": False},
                        {"path": "AppRoot/Home/Wind", "type": "HSlider", "text": "Wind", "focused": False,
                         "value": 2.5, "min": 0, "max": 10}]}
                    reply = {"id": request["id"], "ok": True, "result": result}
                elif request["cmd"] == "nope":
                    reply = {"id": request["id"], "ok": False, "error": "unknown command 'nope'; try help"}
                elif request["cmd"] in ("open", "close", "state", "logs"):
                    reply = self._screens(request)
                elif request["cmd"] == "assert":
                    reply = {"id": request["id"], "ok": str(request["expr"]).lower() == "true", "error": "assertion failed: x"}
                elif request["cmd"] == "sample":
                    start = 24 * len([r for r in self.requests if r["cmd"] == "sample"])
                    rows = [[start + i * request["every_ticks"], 0.1 * i, i] for i in range(request["count"])]
                    reply = {"id": request["id"], "ok": True,
                             "result": {"columns": ["tick", "time_s"] + list(request["exprs"]), "rows": rows}}
                else:
                    reply = {"id": request["id"], "ok": True, "result": {"echo": request}}
                conn.sendall((json.dumps(reply) + "\n").encode())

    def _screens(self, request: dict) -> dict:
        command, ok, result = request["cmd"], True, None
        if command == "open" and "screen" not in request:
            result = ["pause", "settings", "help"]
        elif command == "open":
            ok = request["screen"] != "pause"
            if ok:
                self.screens.append(request["screen"])
                result = {"opened": request["screen"]}
        elif command == "close":
            if not self.stuck or self.screens[-1] != "help":
                self.screens.pop()
            result = {"closed": True}
        elif command == "state":
            result = {"route": "home", "screens": list(self.screens)}
        else:
            records = [{"seq": 6, "level": "script_error", "text": "boom"}] if request.get("since") else []
            result = {"last_seq": 5, "dropped": 0, "records": records if self.stuck else []}
        return {"id": request["id"], "ok": ok, "result": result, "error": "did not open here"}

    def close(self) -> None:
        with contextlib.suppress(OSError):
            self.server.shutdown(socket.SHUT_RDWR)  # wakes the blocked accept()
        self.server.close()


class DebugctlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge = FakeBridge()
        self.env = dict(os.environ)
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(self.bridge.port)
        os.environ.pop("OPENRC_DEBUG_TOKEN", None)
        self.tmp = tempfile.TemporaryDirectory()
        self.saved_current = debugctl.CURRENT
        self.saved_sessions = debugctl.SESSIONS
        self.saved_owned_processes = debugctl._OWNED_PROCESSES
        debugctl._OWNED_PROCESSES = {}
        debugctl.CURRENT = Path(self.tmp.name) / "current.json"
        debugctl.SESSIONS = Path(self.tmp.name) / "sessions"

    def tearDown(self) -> None:
        debugctl.CURRENT = self.saved_current
        debugctl.SESSIONS = self.saved_sessions
        debugctl._OWNED_PROCESSES = self.saved_owned_processes
        self.tmp.cleanup()
        self.bridge.close()
        os.environ.clear()
        os.environ.update(self.env)

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = debugctl.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def show_output(self, command: str, result: dict, raw_json: bool = False) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            debugctl.show(command, result, False, raw_json)
        return out.getvalue()

    def test_ablate_synthetic_significance_and_overrides(self) -> None:
        result = {"baseline": {"gpu_ms": 1.7, "min_ms": 1.3, "max_ms": 1.8, "drift_ms": 0.08, "draw_calls": 387,
                               "primitives": 318944},
                  "noise_ms": 0.055, "significance": "|saved| > 3 x noise", "warmup": 10, "frames": 60, "frozen": True,
                  "gpu_timing_status": "synthetic_valid", "gpu_ms_scope": "root_only_freshness_unverified",
                  "freeze_scope": "simulation only; camera and visuals may change",
                  "paused_at_start": False,
                  "pause_restore": {"owned": True, "restored": False, "interrupted": True},
                  "skipped": ["@glow", "@half_res"], "skipped_reasons": {"@half_res": "non_bilinear_reconstruction"},
                  "rows": [{"name": "@msaa", "kind": "flag", "saved_gpu_ms": 0.254, "saved_pct": 17.6, "significant": True,
                            "gpu_timing_status": "synthetic_valid",
                            "saved_draw_calls": 0, "saved_primitives": 0, "saved_cpu_ms": 0.0, "overridden": False},
                           {"name": "SunGlare", "kind": "layer", "saved_gpu_ms": -0.02, "saved_pct": -1.2,
                            "gpu_timing_status": "synthetic_valid",
                            "significant": False, "saved_draw_calls": 0, "saved_primitives": 0, "saved_cpu_ms": 0.09,
                            "overridden": True}]}
        lines = self.show_output("ablate", result).splitlines()
        self.assertIn("baseline GPU root 1.7 ms", lines[0])
        self.assertIn("synthetic test data", lines[0])
        self.assertIn("owned simulation freeze True; paused at start False", lines[0])
        self.assertIn("simulation only; camera and visuals may change", lines[0])
        self.assertIn("@msaa", lines[2])
        self.assertIn("*", lines[2])
        self.assertIn("not trustworthy", lines[3])
        self.assertIn("skipped", lines[4])
        self.assertIn("@half_res (non_bilinear_reconstruction)", lines[4])
        self.assertIn('"restored": false', lines[5])

    def test_ablate_unverified_unavailable_and_legacy_deltas(self) -> None:
        result = {"baseline": {"gpu_ms": 2.0, "draw_calls": 10}, "frames": 60, "warmup": 10, "frozen": True,
                  "gpu_timing_status": "unverified_freshness", "gpu_ms_scope": "root_only_freshness_unverified",
                  "rows": [{"name": "positive", "baseline_gpu_ms": 2.0, "gpu_ms": 1.75, "saved_gpu_ms": 0.25,
                            "saved_pct": 12.5, "significant": True, "gpu_timing_status": "unverified_freshness",
                            "saved_draw_calls": 1, "saved_primitives": 2, "saved_cpu_ms": 0.1, "overridden": False},
                           {"name": "missing", "baseline_gpu_ms": 0.0, "gpu_ms": 0.0, "saved_gpu_ms": 0.0,
                            "saved_pct": 0.0, "significant": True, "gpu_timing_status": "unavailable_or_zero",
                            "saved_draw_calls": 0, "saved_primitives": 0, "saved_cpu_ms": 0.0, "overridden": False},
                           {"name": "mixed", "baseline_gpu_ms": 2.0, "gpu_ms": 2.125, "saved_gpu_ms": -0.125,
                            "saved_pct": -6.25, "significant": True, "gpu_timing_status": "mixed_or_unavailable",
                            "saved_draw_calls": 0, "saved_primitives": 0, "saved_cpu_ms": 0.0, "overridden": False}]}
        lines = self.show_output("ablate", result).splitlines()
        self.assertIn("0.250", lines[2])
        self.assertIn("12.5", lines[2])
        self.assertIn("delayed, freshness unverified", lines[2])
        self.assertIn("n/a", lines[3])
        self.assertIn("n/a", lines[4])
        self.assertNotIn("-0.125", lines[4])
        self.assertIn("mixed or unavailable readings", lines[4])
        self.assertNotIn("*", "\n".join(lines))
        self.assertNotIn("saving", "\n".join(lines).lower())

        legacy = dict(result, rows=[dict(result["rows"][0])])
        legacy.pop("gpu_timing_status")
        legacy.pop("gpu_ms_scope")
        legacy["rows"][0].pop("gpu_timing_status")
        legacy["rows"][0].pop("baseline_gpu_ms")
        legacy["rows"][0].pop("gpu_ms")
        text = self.show_output("ablate", legacy)
        self.assertIn("0.250", text)
        self.assertIn("scope unknown", text)
        self.assertIn("legacy or unknown status", text)
        self.assertIn("reported frozen True (ownership unknown)", text)
        self.assertNotIn("*", text)
        self.assertEqual(json.loads(self.show_output("ablate", legacy, raw_json=True)), legacy)

    def test_ablate_null_and_legacy_mixed_phase_deltas_are_unavailable(self) -> None:
        # One A-B-A baseline was unavailable (0), the target reported 4 and the other baseline 10.
        # Older responses could average 0 and 10 into 5 and claim a 1 ms delta despite the missing phase.
        row = {"name": "mixed-null", "baseline_gpu_ms": 5.0, "gpu_ms": 4.0,
               "baseline_before_gpu_ms": 0.0, "baseline_after_gpu_ms": 10.0,
               "baseline_before_gpu_timing_status": "unavailable_or_zero",
               "target_gpu_timing_status": "unverified_freshness", "baseline_after_gpu_timing_status": "unverified_freshness",
               "saved_gpu_ms": None, "saved_pct": None, "gpu_timing_status": "mixed_or_unavailable",
               "significant": True, "saved_draw_calls": 2, "saved_primitives": 10,
               "saved_cpu_ms": 0.3, "overridden": False}
        result = {"baseline": {"gpu_ms": 5.0, "min_ms": 0.0, "max_ms": 10.0, "drift_ms": 10.0,
                               "draw_calls": 20}, "noise_ms": 4.0, "frames": 60, "warmup": 10,
                  "gpu_timing_status": "mixed_or_unavailable", "frozen": False, "paused_at_start": True,
                  "rows": [row, dict(row, name="mixed-legacy", saved_gpu_ms=1.0, saved_pct=20.0),
                           dict(row, name="unverified-null", gpu_timing_status="unverified_freshness")]}
        lines = self.show_output("ablate", result).splitlines()
        self.assertIn("owned simulation freeze False; paused at start True", lines[0])
        self.assertIn("unavailable ms", lines[0])
        self.assertIn("raw range unavailable, drift unavailable, noise unavailable", lines[0])
        self.assertIn("20 draw calls", lines[0])
        for line in lines[2:4]:
            self.assertEqual(line.count("n/a"), 2)
            self.assertIn("mixed or unavailable readings", line)
            self.assertNotIn("1.000", line)
            self.assertNotIn("20.0", line)
            self.assertNotIn("*", line)
        self.assertEqual(lines[4].count("n/a"), 2)
        self.assertIn("delayed, freshness unverified", lines[4])
        self.assertIn("before unavailable (unavailable or zero)", lines[2])
        self.assertIn("target 4 (delayed, freshness unverified)", lines[2])
        self.assertIn("after 10 (delayed, freshness unverified)", lines[2])
        self.assertIn("2", lines[2])  # draw counters remain visible
        self.assertEqual(json.loads(self.show_output("ablate", result, raw_json=True)), result)

        # New producers identify baseline phases separately, even if a target phase makes the run mixed.
        result["baseline"]["gpu_timing_status"] = "unverified_freshness"
        result["noise_timing_status"] = "unverified_freshness"
        header = self.show_output("ablate", result).splitlines()[0]
        self.assertIn("baseline GPU reported (scope unknown) 5 ms (delayed, freshness unverified)", header)
        self.assertIn("noise 4 ms", header)

    @staticmethod
    def render_result() -> dict:
        return {"measuring": True, "frames": 30, "statistic": "median per frame", "gpu_ms": 2.1,
                "root_gpu_ms": 2.1, "sub_gpu_ms": 0.4, "gpu_p95_ms": 2.5, "frame_ms": 16.7, "fps": 59.9,
                "gpu_timing_status": "unverified_freshness", "gpu_ms_scope": "root_only_freshness_unverified",
                "sub_gpu_ms_scope": "last_readings_unverified_may_not_have_drawn", "bound": "CPU: misleading",
                "gpu_budget_status": "unavailable", "gpu_budget_pct": {"at_60fps": -1, "at_120fps": -1},
                "draw_calls": 12, "shadow_draw_calls": 3, "canvas_draw_calls": 1, "objects": 6, "primitives": 100,
                "config": {"renderer": "mobile", "adapter": "M1", "size": [1920, 1080], "vsync": "enabled",
                           "msaa_3d": 0, "scaling_3d_scale": 1.0, "debug_draw": "disabled"},
                "viewports": [{"gpu_ms": 0.4, "gpu_timing_status": "unverified_freshness", "size": [256, 256],
                               "update": "once", "path": "shadow"},
                              {"gpu_ms": 0.0, "gpu_timing_status": "unavailable_or_zero", "size": [64, 64],
                               "update": "always", "path": "other"}]}

    def test_render_exposes_raw_root_and_subviewport_without_claiming_budget(self) -> None:
        result = self.render_result()
        text = self.show_output("render", result)
        self.assertIn("GPU root 2.1 ms", text)
        self.assertIn("p95 2.5", text)
        self.assertIn("SubViewport last-reading sum: 0.4 ms", text)
        self.assertIn("not included in root; may not have drawn", text)
        self.assertIn("delayed, freshness unverified", text)
        self.assertIn("unavailable ms", text)
        self.assertIn("bound: unknown", text)
        self.assertIn("GPU budget unavailable", text)
        self.assertNotIn("CPU: misleading", text)
        self.assertNotIn("-1", text)
        self.assertEqual(json.loads(self.show_output("render", result, raw_json=True)), result)

    def test_render_invalid_and_legacy_timings_are_not_a_bottleneck(self) -> None:
        result = self.render_result()
        result.update(gpu_ms=0.0, root_gpu_ms=float("nan"), sub_gpu_ms=float("inf"), gpu_p95_ms=-1,
                      gpu_timing_status="unavailable_or_zero")
        result["viewports"][0]["gpu_ms"] = float("nan")
        text = self.show_output("render", result)
        self.assertIn("GPU root unavailable ms", text)
        self.assertIn("SubViewport last-reading sum: unavailable ms", text)
        self.assertIn("bound: unknown", text)
        self.assertNotIn("nan", text.lower())
        self.assertNotIn("inf", text.lower())
        self.assertNotIn("CPU: misleading", text)

        legacy = self.render_result()
        legacy.update(gpu_ms=2.5, bound="frame cap: GPU headroom 14 ms")
        for key in ("gpu_timing_status", "gpu_ms_scope", "sub_gpu_ms_scope", "gpu_budget_status"):
            legacy.pop(key)
        for row in legacy["viewports"]:
            row.pop("gpu_timing_status")
        text = self.show_output("render", legacy)
        self.assertIn("GPU reported (scope unknown) 2.5 ms", text)
        self.assertIn("root GPU reading: 2.1 ms", text)
        self.assertIn("legacy or unknown", text)
        self.assertNotIn("GPU headroom", text)

    def test_frames_label_legacy_gpu_claims_and_unavailable_values(self) -> None:
        result = {"frames": 10, "mean_ms": 16.0, "p50_ms": 16.0, "p95_ms": 17.0, "p99_ms": 17.0,
                  "max_ms": 18.0, "fps_mean": 62.5, "fps_1pct_low": 55.5, "physics_catch_up_frames": 0,
                  "hitch_total": 1, "hitch_ms": 50, "factor": 3, "typical_ms": 16,
                  "gpu": {"p50_ms": 1.2, "p95_ms": 0.0, "p99_ms": float("inf"), "max_ms": -1},
                  "hitches": [{"frame": 2, "ms": 60, "physics_ticks": 1, "causes": ["GPU-bound (50 ms GPU)"],
                               "deltas": {}, "log": []}]}
        text = self.show_output("frames", result)
        self.assertIn("p50 1.2, p95 unavailable, p99 unavailable, max unavailable", text)
        self.assertIn("legacy or unknown status", text)
        self.assertIn("GPU-bound (50 ms GPU) [legacy claim; freshness unverified]", text)
        result["gpu"]["status"] = "unverified_freshness"
        self.assertIn("GPU root (delayed, freshness unverified)", self.show_output("frames", result))
        result.pop("gpu")
        result["gpu_timing_status"] = "unavailable_or_zero"
        self.assertIn("GPU root: unavailable", self.show_output("frames", result))

    def test_bugit_report_summarizes_and_bugitgo_refuses_without_checkpoint(self) -> None:
        folder = Path(self.tmp.name) / "bugit"
        folder.mkdir()
        report = {"created": "2026-11-06T14:39:16+00:00", "note": "wing drop on landing",
                  "git": {"head": "f3770ac6f913aa", "branch": "main", "changed_files": 2, "changed": []},
                  "ping": {"godot": "4.8-beta2", "display": "Windows"},
                  "state": {"route": "flight", "screens": [],
                            "flight": {"aircraft": "jensen-das-ugly-stik-60", "tick": 799, "time_s": 3.3,
                                       "height_m": 41.5, "speed_mps": 25.2, "attitude_deg": {}, "paused": True,
                                       "crashed": False}},
                  "frames": {"p50_ms": 8.33, "p95_ms": 8.47, "max_ms": 16.6, "hitch_total": 1},
                  "render": {"measuring": True, "gpu_ms": 2.3, "draw_calls": 797.0, "bound": "frame cap"},
                  "problems": {"groups": [{"count": 3, "level": "warning", "text": "slow shader", "script": "x.gd"}]},
                  "checkpoint": {"path": str(folder / "checkpoint.json")}}
        text = debugctl._bugit_markdown(report, folder)
        self.assertIn("wing drop on landing", text)
        self.assertIn("`jensen-das-ugly-stik-60` tick 799", text)
        self.assertIn("3× warning: slow shader", text)
        self.assertIn("bugitgo", text)
        (folder / "report.json").write_text(json.dumps(report), encoding="utf-8")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            status = debugctl.bugitgo([str(folder)])  # no checkpoint.json on disk
        self.assertEqual(status, 1)
        self.assertIn("no flight checkpoint", err.getvalue())

    def test_exported_launch_uses_packaged_executable_without_project_path(self) -> None:
        exe = Path(self.tmp.name) / "packaged app.exe"
        exe.touch()
        out = Path(self.tmp.name) / "exported-run"
        os.environ["OPENRC_GODOT"] = str(exe)
        process = SimpleNamespace(pid=12345)
        with patch.object(debugctl, "reserve_port", return_value=43210) as reserve, \
                patch.object(debugctl.subprocess, "run") as run, \
                patch.object(debugctl.subprocess, "Popen", return_value=process) as popen, \
                patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}) as ready, \
                patch.object(debugctl.secrets, "token_hex", return_value="session-secret"):
            status, output, err = self.run_cli("launch", "--exported", "--headless", "--port", "43210",
                                                "--out", str(out), "--", "--quick-flight", "--app")
        self.assertEqual((status, err), (0, ""))
        reserve.assert_called_once_with(43210)
        run.assert_not_called()
        command = popen.call_args.args[0]
        self.assertEqual(command, [str(exe.resolve()), "--headless", "--audio-driver", "Dummy",
                                   "--", "--quick-flight", "--app"])
        self.assertNotIn("--path", command[:command.index("--")])
        kwargs = popen.call_args.kwargs
        self.assertEqual(kwargs["cwd"], debugctl.REPO)
        self.assertTrue(kwargs["start_new_session"])
        env = kwargs["env"]
        resolved_out = out.resolve()  # macOS maps /var to /private/var.
        self.assertEqual((env["OPENRC_DEBUG_BRIDGE"], env["OPENRC_DEBUG_TOKEN"]), ("43210", "session-secret"))
        self.assertEqual(env["OPENRC_DEBUG_LOG"], str(resolved_out / "log.jsonl"))
        self.assertEqual(env["OPENRC_DEBUG_OUT"], str(resolved_out))
        self.assertEqual(env["APPDATA"], str(resolved_out / "profile"))
        self.assertEqual(env["XDG_DATA_HOME"], str(resolved_out / "profile"))
        ready.assert_called_once_with(180.0, process, 43210, resolved_out / "engine.log")
        self.assertEqual(json.loads(output)["pid"], 12346)
        self.assertEqual(json.loads((out / "launch.json").read_text())["command"], command)
        self.assertEqual(debugctl.session_for(43210)["token"], "session-secret")

    def test_source_launch_keeps_project_path_and_import(self) -> None:
        os.environ["OPENRC_GODOT"] = "source-godot"
        process = SimpleNamespace(pid=12345)
        source_copy = Path(self.tmp.name) / "source copy"
        for extra, expected_project, imported in (
                ([], debugctl.REPO / "app", False),
                (["--app", str(source_copy), "--import"], source_copy, True)):
            with self.subTest(imported=imported):
                out = Path(self.tmp.name) / f"source-run-{imported}"
                with patch.object(debugctl, "reserve_port", return_value=43210), \
                        patch.object(debugctl.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
                        patch.object(debugctl.subprocess, "Popen", return_value=process) as popen, \
                        patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}):
                    status, _, err = self.run_cli("launch", "--headless", "--out", str(out), *extra,
                                                  "--", "--quick-flight")
                self.assertEqual((status, err), (0, ""))
                project = str(expected_project.resolve())
                self.assertEqual(popen.call_args.args[0], ["source-godot", "--path", project, "--headless",
                                                          "--audio-driver", "Dummy", "--", "--quick-flight"])
                self.assertIs(debugctl._OWNED_PROCESSES[process.pid], process)
                if imported:
                    self.assertEqual(run.call_args.args[0], ["source-godot", "--headless", "--path", project,
                                                             "--audio-driver", "Dummy", "--import"])
                else:
                    run.assert_not_called()

    def test_rendered_aqua_launch_does_not_require_xvfb_or_display_environment(self) -> None:
        os.environ["OPENRC_GODOT"] = "source-godot"
        os.environ.pop("DISPLAY", None)
        os.environ.pop("WAYLAND_DISPLAY", None)
        out = Path(self.tmp.name) / "aqua-run"
        process = SimpleNamespace(pid=12345)
        with patch.object(debugctl.sys, "platform", "darwin"), \
                patch.object(debugctl, "reserve_port", return_value=43210), \
                patch.object(debugctl.shutil, "which", side_effect=AssertionError("xvfb probed")), \
                patch.object(debugctl.subprocess, "Popen", return_value=process) as popen, \
                patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}):
            status, _, err = self.run_cli("launch", "--out", str(out), "--resolution", "1920x1080")
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(popen.call_args.args[0], ["source-godot", "--path", str(debugctl.REPO / "app"),
                                                   "--resolution", "1920x1080"])

    def test_aqua_rss_uses_resource_sampler(self) -> None:
        report = {"samples": [{"rss_bytes": 10485760, "field_status": {"rss_bytes": "ok"}}]}
        with patch.object(debugctl.sys, "platform", "darwin"), \
                patch("resource_samples.load_backend", return_value=object()) as backend, \
                patch("resource_samples.ResourceSampler") as sampler:
            sampler.return_value.finish.return_value = report
            self.assertEqual(debugctl.rss_mib(12345), 10.0)
        backend.assert_called_once()
        sampler.assert_called_once()

    def test_rendered_linux_without_display_keeps_xvfb_path(self) -> None:
        os.environ["OPENRC_GODOT"] = "source-godot"
        os.environ.pop("DISPLAY", None)
        os.environ.pop("WAYLAND_DISPLAY", None)
        out = Path(self.tmp.name) / "xvfb-run"
        with patch.object(debugctl.sys, "platform", "linux"), \
                patch.object(debugctl, "reserve_port", return_value=43210), \
                patch.object(debugctl.shutil, "which", return_value="/usr/bin/xvfb-run"), \
                patch.object(debugctl.subprocess, "Popen", return_value=SimpleNamespace(pid=12345)) as popen, \
                patch.object(debugctl, "wait_ready", return_value={"result": {"pid": 12346}}):
            status, _, err = self.run_cli("launch", "--out", str(out))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(popen.call_args.args[0][:4],
                         ["/usr/bin/xvfb-run", "-a", "-s", "-screen 0 1920x1080x24"])

    def test_exported_launch_rejects_invalid_options_before_claiming_port(self) -> None:
        exe = Path(self.tmp.name) / "packaged.exe"
        exe.touch()
        for override, args, message in (
                (None, [], "requires OPENRC_GODOT"),
                ("  ", [], "requires OPENRC_GODOT"),
                (str(exe.parent / "missing.exe"), [], "does not exist"),
                (str(exe.parent), [], "does not exist"),
                (str(exe), ["--import"], "--import cannot be used"),
                (str(exe), ["--app", "app"], "--app cannot be used")):
            with self.subTest(override=override, args=args):
                if override is None:
                    os.environ.pop("OPENRC_GODOT", None)
                else:
                    os.environ["OPENRC_GODOT"] = override
                with patch.object(debugctl, "reserve_port") as reserve, \
                        patch.object(debugctl.subprocess, "run") as run, \
                        patch.object(debugctl.subprocess, "Popen") as popen:
                    status, _, err = self.run_cli("launch", "--exported", "--headless", *args)
                self.assertEqual(status, 2)
                self.assertIn(message, err)
                reserve.assert_not_called()
                run.assert_not_called()
                popen.assert_not_called()
                self.assertFalse(debugctl.SESSIONS.exists())

    def test_failed_exported_launch_stops_only_its_own_process(self) -> None:
        exe = Path(self.tmp.name) / "packaged.exe"
        exe.touch()
        os.environ["OPENRC_GODOT"] = str(exe)
        out = Path(self.tmp.name) / "failed-run"
        process = SimpleNamespace(pid=12345)
        with patch.object(debugctl, "reserve_port", return_value=43210), \
                patch.object(debugctl.subprocess, "Popen", return_value=process), \
                patch.object(debugctl, "wait_ready", side_effect=RuntimeError("bridge unavailable")), \
                patch.object(debugctl, "kill_group") as kill:
            status, _, err = self.run_cli("launch", "--exported", "--headless", "--out", str(out))
        self.assertEqual(status, 2)
        self.assertIn("bridge unavailable", err)
        self.assertIn("require a debug template", err)
        kill.assert_called_once_with(12345)
        self.assertFalse((debugctl.SESSIONS / "43210.json").exists())
        self.assertFalse(debugctl.CURRENT.exists())

    def test_key_values_are_json_when_possible(self) -> None:
        status, out, _ = self.run_cli("sticks", "roll=0.4", "release=true", "text=Fly", 'expr=flight.session.sim.tick > 3')
        self.assertEqual(status, 0)
        sent = self.bridge.requests[-1]
        self.assertEqual((sent["cmd"], sent["roll"], sent["release"], sent["text"]), ("sticks", 0.4, True, "Fly"))
        self.assertEqual(sent["expr"], "flight.session.sim.tick > 3")
        self.assertEqual(json.loads(out)["echo"]["cmd"], "sticks")

    def test_token_is_sent_from_the_environment(self) -> None:
        os.environ["OPENRC_DEBUG_TOKEN"] = "s3cret"
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "s3cret")

    def test_bridge_errors_exit_one(self) -> None:
        status, out, err = self.run_cli("nope")
        self.assertEqual((status, out), (1, ""))
        self.assertIn("unknown command", err)

    def test_usage_and_connection_errors_exit_two(self) -> None:
        self.assertEqual(self.run_cli("press", "Fly")[0], 2)
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free_port = unused.getsockname()[1]
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(free_port)  # nothing listens there now
        status, _, err = self.run_cli("ping")
        self.assertEqual(status, 2)
        self.assertIn("debugctl:", err)

    def test_ui_prints_a_table_and_json_on_request(self) -> None:
        status, out, _ = self.run_cli("ui")
        lines = out.splitlines()
        self.assertEqual(status, 0)
        self.assertTrue(lines[0].startswith("# scope AppRoot/Home"))
        self.assertTrue(lines[1].startswith("* Button") and lines[1].endswith(" Fly"), lines[1])
        self.assertTrue(self.run_cli("ui", "--paths")[1].splitlines()[1].endswith("AppRoot/Home/Fly"))
        self.assertIn("value=2.5 [0..10]", lines[2])
        self.assertEqual(json.loads(self.run_cli("ui", "--json")[1])["focus"], "AppRoot/Home/Fly")

    def test_last_launch_supplies_the_port(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        self.assertEqual(debugctl.port(), debugctl.DEFAULT_PORT)
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port, "pid": os.getpid()}))
        status, out, _ = self.run_cli("status")
        report = json.loads(out)
        self.assertEqual((status, report["port"], report["alive"], report["bridge"]), (0, self.bridge.port, True, True))

    def test_run_script_stops_at_the_first_failure(self) -> None:
        script = Path(self.tmp.name) / "repro.txt"
        script.write_text("# comment\nping\nassert expr=true\n\nassert expr=false\nping note='after failure'\n")
        status, out, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 5: assertion failed", err)
        self.assertNotIn("after failure", out)
        self.assertEqual([r["cmd"] for r in self.bridge.requests], ["ping", "assert", "assert"])
        status, out, _ = self.run_cli("run", str(script), "--keep-going")
        self.assertEqual(status, 1)
        self.assertEqual(self.bridge.requests[-1]["note"], "after failure")

    def test_run_executes_sibling_cleanup_after_success(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("ping note=main\n")
        script.with_suffix(".cleanup").write_text("ping note=cleanup\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual([r.get("note") for r in self.bridge.requests], ["main", "cleanup"])

    def test_run_executes_cleanup_after_assertion_and_keeps_original_failure(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\nping note=unreached\n")
        script.with_suffix(".cleanup").write_text("ping note=cleanup\n")
        status, out, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 1: assertion failed", err)
        self.assertNotIn("unreached", out)
        self.assertEqual([r["cmd"] for r in self.bridge.requests], ["assert", "ping"])
        self.assertEqual(self.bridge.requests[-1]["note"], "cleanup")

    def test_cleanup_attempts_remaining_commands_and_reports_both_failures(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\n")
        script.with_suffix(".cleanup").write_text("nope\nping note=after_cleanup_error\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("line 1: assertion failed", err)
        self.assertIn("cleanup line 1:", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_cleanup_error")
        script.write_text("ping note=main\n")
        status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)
        self.assertIn("cleanup line 1:", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_cleanup_error")

    def test_cleanup_attempts_commands_after_connection_failure_and_keeps_main_status(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("assert expr=false\n")
        script.with_suffix(".cleanup").write_text("ping note=connection_error\nping note=after_connection_error\n")
        original = debugctl.execute_line
        def execute(line):
            if "connection_error" in line and "after_connection_error" not in line:
                raise OSError("simulated connection failure")
            return original(line)
        with patch.object(debugctl, "execute_line", side_effect=execute):
            status, _, err = self.run_cli("run", str(script))
        self.assertEqual(status, 1)  # Original assertion failure remains the result.
        self.assertIn("line 1: assertion failed", err)
        self.assertIn("cleanup line 1: simulated connection failure", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "after_connection_error")

    def test_cleanup_file_is_not_recursively_executed(self) -> None:
        script = Path(self.tmp.name) / "scenario.cleanup"
        script.write_text("ping note=once\n")
        status, _, _ = self.run_cli("run", str(script))
        self.assertEqual(status, 0)
        self.assertEqual([r.get("note") for r in self.bridge.requests], ["once"])

    def test_cleanup_reports_engine_errors_when_requested(self) -> None:
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text("ping note=main\n")
        script.with_suffix(".cleanup").write_text("state note=cleanup1\nstate note=cleanup2\n")
        original_result = debugctl.result_of
        def result(command, *args, **kwargs):
            if command == "ping":
                return {"log_seq": 1}
            return original_result(command, *args, **kwargs)
        with patch.object(debugctl, "result_of", side_effect=result), \
                patch.object(debugctl, "new_errors", side_effect=[[], [{"level": "script_error", "text": "cleanup failure"}], []]), \
                patch.object(debugctl, "format_record", return_value="cleanup engine failure"):
            status, _, err = self.run_cli("run", str(script), "--fail-on-error")
        self.assertEqual(status, 1)
        self.assertIn("cleanup line 1: new engine errors: cleanup engine failure", err)
        self.assertEqual(self.bridge.requests[-1]["note"], "cleanup2")

    def test_run_stdin_has_no_sibling_cleanup(self) -> None:
        (Path(self.tmp.name) / "-.cleanup").write_text("nope\n")
        with patch.object(sys, "stdin", io.StringIO("ping note=stdin\n")):
            status, _, err = self.run_cli("run", "-")
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(self.bridge.requests[-1]["note"], "stdin")

    def test_scenarios_cleanup_and_soak_read_utf8_with_a_non_utf8_locale(self) -> None:
        import builtins
        script = Path(self.tmp.name) / "scenario.txt"
        script.write_text('ping note="1920 × 1080"\n', encoding="utf-8")
        script.with_suffix(".cleanup").write_text('ping note="Statistics · Pilot total"\n', encoding="utf-8")
        real_path_open = Path.open

        def simulated_builtin_open(file, mode="r", encoding=None, **kwargs):
            return builtins.open(file, mode=mode, encoding=encoding or "cp1252", **kwargs)

        def simulated_path_open(path, mode="r", buffering=-1, encoding=None, errors=None, newline=None):
            if "b" not in mode and encoding in (None, "locale"):
                encoding = "cp1252"
            return real_path_open(path, mode=mode, buffering=buffering, encoding=encoding,
                                  errors=errors, newline=newline)

        with patch.object(debugctl, "open", simulated_builtin_open, create=True), \
                patch.object(Path, "open", simulated_path_open):
            status, _, err = self.run_cli("run", str(script))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual([r["note"] for r in self.bridge.requests], ["1920 × 1080", "Statistics · Pilot total"])

        seen = []
        def result(command, args=None, **_kwargs):
            if command == "ping":
                if args:
                    seen.append(args["note"])
                return {"log_seq": 0}
            if command == "objects":
                return {"totals": {"nodes": 0, "orphans": 0, "resources": 0, "static_memory_mib": 0}}
            if command == "logs":
                return {"records": []}
            return {}

        with patch.object(Path, "open", simulated_path_open), patch.object(debugctl, "result_of", side_effect=result):
            status, _, err = self.run_cli("soak", str(script), "--cycles", "1", "--warmup", "0")
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(seen, ["1920 × 1080"])

    def test_watch_streams_csv_in_chunks(self) -> None:
        target = Path(self.tmp.name) / "watch.csv"
        status, out, _ = self.run_cli("watch", "--every", "6", "--count", "13", "--csv", str(target), "height=-s[2]")
        self.assertEqual(status, 0)
        rows = list(csv.reader(io.StringIO(out)))
        self.assertEqual(rows[0], ["tick", "time_s", "height"])
        self.assertEqual(len(rows), 14)
        with target.open() as stream:
            self.assertEqual(rows, list(csv.reader(stream)))
        samples = [r for r in self.bridge.requests if r["cmd"] == "sample"]
        self.assertEqual([r["count"] for r in samples], [10, 3])
        self.assertEqual(samples[0]["exprs"], {"height": "-s[2]"})

    def test_crawl_opens_lists_and_closes_every_screen(self) -> None:
        status, out, _ = self.run_cli("crawl")
        self.assertEqual(status, 0, out)
        self.assertIn("pause           unavailable here", out)
        self.assertRegex(out, r"settings\s+ok\s+2 controls")
        self.assertTrue(out.rstrip().endswith("# 0 screen failures, 0 errors, 0 warnings"))

    def test_crawl_fails_on_a_screen_that_stays_open_or_new_errors(self) -> None:
        self.bridge.stuck = True
        status, out, _ = self.run_cli("crawl")
        self.assertEqual(status, 1)
        self.assertIn("help            did not return", out)
        self.assertIn("script_error", out)

    def test_clean_keeps_recent_runs_and_foreign_folders(self) -> None:
        saved = debugctl.RUNS
        debugctl.RUNS = Path(self.tmp.name) / "runs"
        try:
            for i in range(4):
                run = debugctl.RUNS / f"run-{i}"
                run.mkdir(parents=True)
                (run / "launch.json").write_text("{}")
                os.utime(run, (1000 + i, 1000 + i))
            (debugctl.RUNS / "notes").mkdir()
            os.utime(debugctl.RUNS / "notes", (1, 1))
            status, out, _ = self.run_cli("clean", "--keep", "2")
            self.assertEqual((status, json.loads(out)["removed"]), (0, 2))
            self.assertEqual(sorted(p.name for p in debugctl.RUNS.iterdir()), ["notes", "run-2", "run-3"])
        finally:
            debugctl.RUNS = saved

    def test_clean_protects_every_live_run_and_defers_for_an_unpublished_launch(self) -> None:
        runs = Path(self.tmp.name) / "runs"
        runs.mkdir()
        debugctl.SESSIONS.mkdir()
        live_runs = []
        for number in (40001, 40002):
            run = runs / f"run-{number}"
            run.mkdir()
            (run / "launch.json").write_text("{}")
            session = {"port": number, "pid": number, "launcher_pid": number, "out": str(run)}
            (debugctl.SESSIONS / f"{number}.json").write_text(json.dumps(session))
            live_runs.append(run)
        debugctl.CURRENT.write_text(json.dumps(session))
        old = runs / "old"
        old.mkdir()
        (old / "launch.json").write_text("{}")
        stale = debugctl.SESSIONS / "40003.json"
        stale.write_text(json.dumps({"port": 40003, "launcher_pid": 40003}))
        pending = debugctl.SESSIONS / "40004.json"
        pending.write_text(json.dumps({"port": 40004, "launcher_pid": 40004, "claimed": True}))
        with patch.object(debugctl, "RUNS", runs), patch.object(debugctl, "alive", side_effect=lambda p: p in (40001, 40002, 40004)):
            status, out, _ = self.run_cli("clean", "--keep", "0")
            self.assertEqual((status, json.loads(out)["removed"], json.loads(out)["stale_sessions"]), (0, 0, 1))
            self.assertTrue(old.exists())  # an unpublished launch could be preparing this folder
            self.assertTrue(all(run.exists() for run in live_runs))
            self.assertFalse(stale.exists())
            pending.unlink()  # the in-progress claim has ended
            status, out, _ = self.run_cli("clean", "--keep", "0")
            self.assertEqual((status, json.loads(out)["removed"]), (0, 1))
            self.assertFalse(old.exists())
            self.assertTrue(all(run.exists() for run in live_runs))

    def test_short_paths_drop_the_scope_and_generated_segments(self) -> None:
        path = "AppRoot/Settings/@Control@91/@CenterContainer@93/@VBoxContainer@95/@GridContainer@98/DisplayCategory"
        self.assertEqual(debugctl.short_path(path, "AppRoot/Settings"), "DisplayCategory")
        self.assertEqual(debugctl.short_path("AppRoot/Main/A/B/C/D", "AppRoot"), "B/C/D")

    def test_the_launch_token_is_sent_for_its_port_only(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port, "token": "abc123"}))
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "abc123")
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(self.bridge.port + 1)  # another session's port: no stray token
        self.assertEqual(debugctl.token(), "")

    def test_enable_value_one_is_not_a_port(self) -> None:
        os.environ["OPENRC_DEBUG_BRIDGE"] = "1"
        self.assertIsNone(debugctl.env_port())
        self.assertEqual(debugctl.port(), debugctl.DEFAULT_PORT)

    def test_stop_without_a_session_says_so(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        status, _, err = self.run_cli("stop")
        self.assertEqual(status, 1)
        self.assertIn("no launched session", err)

    def test_quoted_values_stay_strings_in_scripts(self) -> None:
        words = debugctl.split_line('key name="2" note=\'a b\' count=3 exprs={"h":"-s[2]"}')
        values = [debugctl.parse_value(w.split("=", 1)[1]) for w in words[1:]]
        self.assertEqual(values, ["2", "a b", 3, {"h": "-s[2]"}])

    def test_exit_report_reads_crashes_and_leaks(self) -> None:
        log = Path(self.tmp.name) / "engine.log"
        log.write_text(
            "ERROR: probe crash\n   at: crash (core/core_bind.cpp:349)\n\n"
            "================================================================\n"
            "handle_crash: Program crashed with signal 4\nEngine version: Godot Engine v4.7.2\n"
            "Dumping the backtrace.\n[1] 788d6aa45330 (libc.so.6+45330)\n-- END OF C++ BACKTRACE --\n"
            "================================================================\nGDScript backtrace (most recent call first):\n"
            "    [0] deep (res://crash.gd:3)\n    [1] _init (res://crash.gd:5)\n-- END OF GDSCRIPT BACKTRACE --\n"
            "WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
            "Leaked instance: Node:123\n")
        report = debugctl.exit_report(log)
        self.assertEqual(report["leaked_objects"], 2)
        self.assertEqual(report["leaked_instances"], ["Node:123"])
        self.assertEqual(report["crash"]["reason"], "Program crashed with signal 4")
        self.assertEqual(report["crash"]["gdscript_backtrace"], ["[0] deep (res://crash.gd:3)", "[1] _init (res://crash.gd:5)"])
        log.write_text("clean exit\n")
        self.assertEqual(debugctl.exit_report(log), {"crash": None, "leaked_objects": 0})  # explicit, not silent

    def test_hitches_are_attributed_to_the_last_action_before_them(self) -> None:
        saved = debugctl.result_of
        debugctl.result_of = lambda cmd, args=None, **kw: {"hitches": [{"frame": 15, "ms": 80.0}, {"frame": 31, "ms": 60.0},
                                                                        {"frame": 2, "ms": 900.0}]}
        try:
            slow = debugctl.slow_actions([(10, "key name=\"F5\""), (30, "press text=\"Fly\""), (40, "close")])
        finally:
            debugctl.result_of = saved
        self.assertEqual(slow, {'key name="F5"': [80.0], 'press text="Fly"': [60.0]})

    def test_monkey_actions_are_reproducible_from_the_seed(self) -> None:
        controls = [{"text": "Fly", "path": "A/Fly", "type": "Button"},
                    {"text": "×", "path": "A/X1", "type": "Button"}, {"text": "×", "path": "A/X2", "type": "Button"},
                    {"text": "Wind", "path": "A/Wind", "type": "HSlider", "value": 1, "min": 0, "max": 10}]
        first = [debugctl.monkey_action(random.Random(5), controls, ["Kp Enter"]) for _ in range(1)]
        runs = [[debugctl.monkey_action(rng, controls, ["Kp Enter"]) for _ in range(40)] for rng in (random.Random(5), random.Random(5))]
        self.assertEqual(runs[0], runs[1])
        self.assertTrue(first)
        joined = "\n".join(runs[0])
        self.assertNotIn("\\u", joined)  # labels stay literal UTF-8
        self.assertIn('key name="Kp Enter"', joined)
        self.assertIn('path="A/X', joined)  # ambiguous labels are addressed by path
        for line in runs[0]:
            debugctl.split_line(line)  # every generated line reads back

    def test_monkey_keeps_its_trail_when_the_bridge_disconnects(self) -> None:
        # Real TCP responses, including disconnects before and after an action. A healthy
        # bridge is the positive control for the report and its replayable trail.
        requests = ["ping", "ping", "ui", "ping", "close", "logs", "frames", "state"]
        stopped_at = {"initial_ping": 0, "route_ping": 1, "ui": 2, "action_ping": 3,
                      "close": 4, "logs": 5, "frames": 6, "state": 7}
        for stage in (None, "shortcuts", "initial_ping", "route_ping", "ui", "action_ping", "close", "logs", "frames", "state"):
            with self.subTest(stage=stage):
                listener = socket.create_server(("127.0.0.1", 0))
                number = listener.getsockname()[1]
                seen = []
                failures = []

                def serve():
                    try:
                        while True:
                            try:
                                conn, _ = listener.accept()
                            except OSError:
                                return
                            with conn, conn.makefile("rb") as stream:
                                request = json.loads(stream.readline())
                                command = request["cmd"]
                                seen.append(command)
                                ping_stage = {1: "initial_ping", 2: "route_ping", 3: "action_ping"}.get(seen.count("ping"))
                                if (command == "ping" and stage == ping_stage) or stage == command:
                                    # This thread is handling a connection, not blocked in accept.
                                    # Closing the listener refuses later requests; shutdown on a
                                    # listening socket raises WSAENOTCONN on Windows.
                                    listener.close()
                                    return
                                results = {
                                    "ping": {"log_seq": 0, "route": "home", "frame": 1},
                                    "shortcuts": {"shortcuts": []},
                                    "ui": {"scope": "AppRoot/Home", "controls": []},
                                    "close": {}, "logs": {"records": []},
                                    "frames": {"hitches": []}, "state": {"route": "home"},
                                }
                                reply = {"id": request["id"], "ok": True, "result": results[command]}
                                conn.sendall((json.dumps(reply) + "\n").encode())
                    except Exception as error:
                        failures.append(error)

                thread = threading.Thread(target=serve, daemon=True)
                thread.start()
                target = Path(self.tmp.name) / f"monkey-{stage}.txt"
                try:
                    with patch.dict(os.environ, {"OPENRC_DEBUG_BRIDGE": str(number)}):
                        args = ["monkey", "--steps", "1", "--seed", "9", "--out", str(target)]
                        status, out, err = self.run_cli(*(args + (["--keys"] if stage == "shortcuts" else [])))
                finally:
                    with contextlib.suppress(OSError):
                        listener.shutdown(socket.SHUT_RDWR)
                    listener.close()
                    thread.join(5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(failures, [])
                expected = (["shortcuts"] if stage == "shortcuts" else
                            requests[:stopped_at[stage] + 1] if stage else requests)
                self.assertEqual(seen, expected)  # every requested disconnect was reached
                self.assertEqual(err, "")
                report = json.loads(out)
                self.assertTrue(target.exists())
                self.assertEqual(report["trail"], str(target))
                if stage is None:
                    self.assertEqual(status, 0)
                    self.assertIsNone(report["failure"])
                    self.assertEqual(report["route"], "home")
                else:
                    self.assertEqual(status, 2)  # the CLI reserves 2 for connection failures
                    self.assertIn("stopped answering", report["failure"])
                    self.assertIsNone(report["route"])
                self.assertEqual("\nclose\n" in target.read_text(),
                                 stage not in ("shortcuts", "initial_ping", "route_ping", "ui", "action_ping"))

    def test_port_claims_are_exclusive_and_stale_claims_are_taken_over(self) -> None:
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free = unused.getsockname()[1]
        self.assertEqual(debugctl.reserve_port(free), free)  # claimed by this live process
        self.assertIsNone(debugctl.reserve_port(free))  # a second agent cannot take it
        claim = debugctl.SESSIONS / f"{free}.json"
        claim.write_text(json.dumps({"port": free, "launcher_pid": 999999999, "pid": 999999998}))
        self.assertEqual(debugctl.reserve_port(free), free)  # its processes are gone: taken over
        self.assertIsNone(debugctl.reserve_port(self.bridge.port))  # something already listens there

    def test_concurrent_claim_waits_for_initial_claim_contents(self) -> None:
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free = unused.getsockname()[1]
        opened, resume, waiting = threading.Event(), threading.Event(), threading.Event()
        real_open, real_lock = debugctl.os.open, debugctl._session_claim_lock
        answers, failures = {}, []

        def intercepted(path, flags, mode=0o777):
            fd = real_open(path, flags, mode)
            if threading.current_thread().name == "first" and str(path).endswith(f"{free}.json"):
                opened.set()
                if not resume.wait(5):
                    raise RuntimeError("first claim was not released")
            return fd

        @contextlib.contextmanager
        def marked_lock():
            if threading.current_thread().name == "second":
                waiting.set()
            with real_lock():
                yield

        def reserve(name):
            try:
                answers[name] = debugctl.reserve_port(free)
            except Exception as error:
                failures.append(error)

        with patch.object(debugctl.os, "open", side_effect=intercepted), \
                patch.object(debugctl, "_session_claim_lock", marked_lock), \
                patch.object(debugctl, "alive", side_effect=lambda p: p == os.getpid()):
            first = threading.Thread(target=reserve, args=("first",), name="first", daemon=True)
            second = threading.Thread(target=reserve, args=("second",), name="second", daemon=True)
            first.start()
            try:
                self.assertTrue(opened.wait(5))
                second.start()
                self.assertTrue(waiting.wait(5))
            finally:
                resume.set()
                first.join(5)
                if second.ident is not None:
                    second.join(5)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(answers, {"first": free, "second": None})
        self.assertEqual(debugctl.session_for(free)["launcher_pid"], os.getpid())

    def test_windows_claim_lock_uses_the_same_byte_and_unlocks(self) -> None:
        positions, attempts = [], 0
        msvcrt = SimpleNamespace(LK_NBLCK=1, LK_UNLCK=0)

        def locking(fd, mode, length):
            nonlocal attempts
            positions.append(os.lseek(fd, 0, os.SEEK_CUR))
            if mode == msvcrt.LK_NBLCK:
                attempts += 1
                if attempts <= 12:
                    os.lseek(fd, 1, os.SEEK_SET)  # each retry must seek back to byte zero
                    raise OSError(errno.EACCES, "locked")

        msvcrt.locking = Mock(side_effect=locking)
        with patch.object(debugctl.os, "name", "nt"), patch.dict(sys.modules, {"msvcrt": msvcrt}), \
                patch.object(debugctl.time, "sleep") as sleep:
            with debugctl._session_claim_lock():
                self.assertEqual(msvcrt.locking.call_count, 13)
        self.assertEqual(sleep.call_count, 12)  # contention may outlast LK_LOCK's ten attempts
        self.assertEqual(positions, [0] * 14)
        acquired, released = msvcrt.locking.call_args_list[-2:]
        self.assertEqual(acquired.args[0], released.args[0])
        self.assertEqual((acquired.args[1:], released.args[1:]), ((msvcrt.LK_NBLCK, 1), (msvcrt.LK_UNLCK, 1)))
        msvcrt.locking.reset_mock(side_effect=True)
        msvcrt.locking.side_effect = OSError(errno.EBADF, "lock unavailable")
        with patch.object(debugctl.os, "name", "nt"), patch.dict(sys.modules, {"msvcrt": msvcrt}), \
                patch.object(debugctl.time, "sleep") as sleep:
            with self.assertRaisesRegex(OSError, "lock unavailable"):
                with debugctl._session_claim_lock():
                    self.fail("a failed lock must not enter the protected section")
        self.assertEqual(msvcrt.locking.call_count, 1)
        sleep.assert_not_called()  # non-contention errors remain visible

    def test_claim_lock_and_incomplete_claim_recover_after_process_exit(self) -> None:
        import subprocess
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free = unused.getsockname()[1]
        code = (
            "import sys\n"
            "from pathlib import Path\n"
            "sys.path.insert(0, sys.argv[1])\n"
            "import debugctl\n"
            "debugctl.SESSIONS = Path(sys.argv[2])\n"
            "with debugctl._session_claim_lock():\n"
            "    (debugctl.SESSIONS / (sys.argv[3] + '.json')).write_text('')\n"
            "    print('locked', flush=True)\n"
            "    sys.stdin.read()\n"
        )
        child = subprocess.Popen([sys.executable, "-c", code, str(Path(debugctl.__file__).parent),
                                  str(debugctl.SESSIONS), str(free)],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready, lines = threading.Event(), []
        def read_ready():
            lines.append(child.stdout.readline())
            ready.set()
        reader = threading.Thread(target=read_ready, daemon=True)
        reader.start()
        try:
            self.assertTrue(ready.wait(5), "child did not acquire the claim lock")
            self.assertEqual(lines, ["locked\n"])
            self.assertEqual((debugctl.SESSIONS / f"{free}.json").read_text(), "")
            child.kill()
            child.wait(timeout=5)
            self.assertEqual(debugctl.reserve_port(free), free)
            self.assertEqual(debugctl.session_for(free)["launcher_pid"], os.getpid())
        finally:
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=5)
            reader.join(5)

    @unittest.skipUnless(os.name == "nt", "needs native Windows locking")
    def test_windows_contender_recovers_when_lock_owner_is_killed(self) -> None:
        import subprocess

        setup = (
            "import sys\n"
            "from pathlib import Path\n"
            "sys.path.insert(0, sys.argv[1])\n"
            "import debugctl\n"
            "debugctl.SESSIONS = Path(sys.argv[2])\n"
        )
        owner_code = setup + (
            "with debugctl._session_claim_lock():\n"
            "    print('locked', flush=True)\n"
            "    sys.stdin.read()\n"
        )
        waiter_code = setup + (
            "import msvcrt\n"
            "real_locking = msvcrt.locking\n"
            "reported = False\n"
            "def report_contention(fd, mode, length):\n"
            "    global reported\n"
            "    try:\n"
            "        return real_locking(fd, mode, length)\n"
            "    except OSError as error:\n"
            "        if mode == msvcrt.LK_NBLCK and not reported:\n"
            "            print('contended:' + str(error.errno), flush=True)\n"
            "            reported = True\n"
            "        raise\n"
            "msvcrt.locking = report_contention\n"
            "with debugctl._session_claim_lock():\n"
            "    print('acquired', flush=True)\n"
        )
        module_dir = str(Path(debugctl.__file__).parent)
        events = {name: threading.Event() for name in ("locked", "contended", "acquired")}
        lines, children, readers = [], [], []

        def start(code, stdin):
            child = subprocess.Popen([sys.executable, "-c", code, module_dir, str(debugctl.SESSIONS)],
                                     stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            children.append(child)

            def read_lines():
                for line in child.stdout:
                    message = line.rstrip("\r\n")
                    lines.append((child.pid, message))
                    event = events.get(message.partition(":")[0])
                    if event:
                        event.set()

            reader = threading.Thread(target=read_lines, daemon=True)
            readers.append(reader)
            reader.start()
            return child

        try:
            owner = start(owner_code, subprocess.PIPE)
            self.assertTrue(events["locked"].wait(10), "owner did not acquire the lock")
            waiter = start(waiter_code, subprocess.DEVNULL)
            self.assertTrue(events["contended"].wait(10), "waiter did not encounter the held lock")
            self.assertIn((waiter.pid, f"contended:{errno.EACCES}"), lines)
            self.assertFalse(events["acquired"].is_set())
            self.assertIsNone(waiter.poll())
            owner.kill()  # OS cleanup, without releasing the context manager
            owner.wait(timeout=5)
            self.assertTrue(events["acquired"].wait(5), "waiter did not recover the abandoned lock")
            self.assertEqual(waiter.wait(timeout=5), 0)
        finally:
            for child in children:
                if child.poll() is None:
                    with contextlib.suppress(OSError):
                        child.kill()
                child.wait(timeout=5)
            for reader in readers:
                reader.join(5)
            for child in children:
                for stream in (child.stdin, child.stdout, child.stderr):
                    if stream:
                        stream.close()

    def test_clean_waits_for_session_replacement_before_removing_a_live_run(self) -> None:
        runs = Path(self.tmp.name) / "runs"
        run = runs / "live"
        run.mkdir(parents=True)
        (run / "launch.json").write_text("{}")
        claim = debugctl.SESSIONS / "40001.json"
        session = {"port": 40001, "pid": 40001, "launcher_pid": 40001, "out": str(run)}
        debugctl.write_private(claim, session)
        opened, resume, waiting = threading.Event(), threading.Event(), threading.Event()
        real_open, real_lock = debugctl.os.open, debugctl._session_claim_lock
        failures = []

        def intercepted(path, flags, mode=0o777):
            fd = real_open(path, flags, mode)
            if threading.current_thread().name == "writer" and Path(path) == claim:
                opened.set()
                if not resume.wait(5):
                    raise RuntimeError("session replacement was not released")
            return fd

        @contextlib.contextmanager
        def marked_lock():
            if threading.current_thread().name == "cleaner":
                waiting.set()
            with real_lock():
                yield

        def writer():
            try:
                debugctl.write_private(claim, session)
            except Exception as error:
                failures.append(error)

        def cleaner():
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    debugctl.clean(["--keep", "0"])
            except Exception as error:
                failures.append(error)

        with patch.object(debugctl, "RUNS", runs), patch.object(debugctl.os, "open", side_effect=intercepted), \
                patch.object(debugctl, "_session_claim_lock", marked_lock), \
                patch.object(debugctl, "alive", side_effect=lambda p: p == 40001):
            first = threading.Thread(target=writer, name="writer", daemon=True)
            second = threading.Thread(target=cleaner, name="cleaner", daemon=True)
            first.start()
            try:
                self.assertTrue(opened.wait(5))
                second.start()
                self.assertTrue(waiting.wait(5))
            finally:
                resume.set()
                first.join(5)
                if second.ident is not None:
                    second.join(5)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(failures, [])
        self.assertTrue(run.exists())
        self.assertEqual(debugctl.session_for(40001), session)

    def test_forgetting_a_session_cannot_erase_a_concurrent_new_pointer(self) -> None:
        old = {"port": 40001, "launcher_pid": 100}
        new = {"port": 40002, "launcher_pid": 200}
        debugctl.write_private(debugctl.SESSIONS / "40001.json", old)
        debugctl.write_private(debugctl.CURRENT, old)
        seen, resume, waiting = threading.Event(), threading.Event(), threading.Event()
        real_pointer, real_lock = debugctl.current_pointer, debugctl._session_claim_lock
        failures = []

        def pointer():
            value = real_pointer()
            if threading.current_thread().name == "forgetter":
                seen.set()
                if not resume.wait(5):
                    raise RuntimeError("forgetting the session was not released")
            return value

        @contextlib.contextmanager
        def marked_lock():
            if threading.current_thread().name == "pointer-writer":
                waiting.set()
            with real_lock():
                yield

        def run(function):
            try:
                function()
            except Exception as error:
                failures.append(error)

        with patch.object(debugctl, "current_pointer", side_effect=pointer), \
                patch.object(debugctl, "_session_claim_lock", marked_lock):
            first = threading.Thread(target=run, args=(lambda: debugctl.forget_session(40001, 100),),
                                     name="forgetter", daemon=True)
            second = threading.Thread(target=run, args=(lambda: debugctl.write_private(debugctl.CURRENT, new),),
                                      name="pointer-writer", daemon=True)
            first.start()
            try:
                self.assertTrue(seen.wait(5))
                second.start()
                self.assertTrue(waiting.wait(5))
            finally:
                resume.set()
                first.join(5)
                if second.ident is not None:
                    second.join(5)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(failures, [])
        self.assertFalse((debugctl.SESSIONS / "40001.json").exists())
        self.assertEqual(debugctl.current_pointer(), new)

    def test_commands_follow_the_session_of_their_port(self) -> None:
        debugctl.SESSIONS.mkdir(parents=True)
        (debugctl.SESSIONS / f"{self.bridge.port}.json").write_text(json.dumps({"port": self.bridge.port, "token": "mine"}))
        debugctl.CURRENT.write_text(json.dumps({"port": self.bridge.port + 7, "token": "someone-else"}))  # another agent's launch
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "mine")

    def test_stop_refuses_to_guess_between_live_sessions(self) -> None:
        os.environ.pop("OPENRC_DEBUG_BRIDGE")
        debugctl.SESSIONS.mkdir(parents=True)
        for number in (40001, 40002):
            (debugctl.SESSIONS / f"{number}.json").write_text(json.dumps({"port": number, "pid": os.getpid()}))
        debugctl.CURRENT.write_text(json.dumps({"port": 40002}))
        status, _, err = self.run_cli("stop")
        self.assertEqual(status, 2)
        self.assertIn("OPENRC_DEBUG_BRIDGE", err)

    def test_smoke_recovers_after_failed_scenario_and_skips_when_home_is_unavailable(self) -> None:
        scenarios = Path(self.tmp.name) / "scenarios"
        scenarios.mkdir()
        for name in ("a_broken", "b_next"):
            (scenarios / f"{name}.txt").write_text("# fixture\n")
        for recovery_available in (True, False):
            with self.subTest(recovery_available=recovery_available):
                state = {"home": True, "ran": []}

                def fake_launch(_args):
                    print(json.dumps({"port": self.bridge.port, "out": self.tmp.name}))
                    return 0

                def fake_stop(_args):
                    print(json.dumps({"stopped": True, "launcher_exit_code": 0, "crash": None, "leaked_objects": 0}))
                    return 0

                def reset(_args=None):
                    if not state["home"] and not recovery_available:
                        return 1
                    state["home"] = True
                    return 0

                def scenario(args):
                    self.assertTrue(state["home"], "scenario inherited a failed flight")
                    name = Path(args[0]).stem
                    state["ran"].append(name)
                    if name == "a_broken":
                        state["home"] = False
                        raise debugctl.Refused("intentional failed flight")
                    return 0

                output = io.StringIO()
                with patch.multiple(debugctl, SCENARIOS=scenarios, launch=fake_launch, stop=fake_stop,
                                    home_reset=reset, run_script=scenario, crawl=lambda _: 0,
                                    run_lines=lambda _: 0, monkey=lambda _: 0, soak=lambda _: 0,
                                    result_of=lambda _: {"hitch_total": 0}), contextlib.redirect_stdout(output):
                    status = debugctl.smoke([])
                report = json.loads(output.getvalue().strip().splitlines()[-1])
                self.assertEqual(status, 1)  # Recovery must never hide the original failure.
                self.assertFalse(report["ok"])
                self.assertIn("scenario a_broken", report["failed"])
                if recovery_available:
                    self.assertEqual(state["ran"], ["a_broken", "b_next"])
                    self.assertEqual(report["failed"], ["scenario a_broken"])
                else:
                    self.assertEqual(state["ran"], ["a_broken"])
                    self.assertIn("Home before scenario b_next", report["failed"])

    def test_smoke_settles_dead_weakrefs_but_still_rejects_live_growth(self) -> None:
        scenarios = Path(self.tmp.name) / "empty-scenarios"
        scenarios.mkdir()
        for growing in (False, True):
            with self.subTest(growing=growing):
                state = {"live": 100, "dead": {"shadow": 0, "cloud": 0}, "baseline": 0,
                         "sweeps": {"shadow": 0, "cloud": 0},
                         "home_pending": False, "settled": False}

                def fake_launch(_args):
                    print(json.dumps({"port": self.bridge.port, "out": self.tmp.name}))
                    return 0

                def fake_stop(_args):
                    print(json.dumps({"stopped": True, "launcher_exit_code": 0,
                                      "crash": None, "leaked_objects": 0}))
                    return 0

                def execute(line):
                    words = debugctl.split_line(line)
                    args = debugctl.parse_args(words[1:])
                    if words[0] == "fly":
                        state["dead"]["shadow"] += 16
                        state["dead"]["cloud"] += 4
                        state["live"] += int(growing)
                        state["settled"] = False
                    elif words[0] == "home":
                        state["home_pending"] = True
                    elif words[0] == "wait" and state["home_pending"]:
                        self.assertEqual(args.get("frames"), 5)
                        state["home_pending"] = False
                        state["settled"] = True
                    elif words[0] == "eval":
                        self.assertTrue(state["settled"], "teardown must settle before the sweep")
                        expressions = {
                            'ResourceLoader.load("res://render/atmosphere.gd")._prune_shadow_lighting()': "shadow",
                            'ResourceLoader.load("res://render/cloud_shadow_map.gd")._prune_consumers()': "cloud",
                        }
                        self.assertIn(args["expr"], expressions)
                        registry = expressions[args["expr"]]
                        state["sweeps"][registry] += 1
                        state["dead"][registry] = 0

                def result(command, args=None):
                    args = args or {}
                    if command == "ping": return {"log_seq": 0}
                    if command == "frames": return {"hitch_total": 0}
                    if command == "wait": return {}
                    if command == "objects":
                        self.assertEqual(state["dead"], {"shadow": 0, "cloud": 0})
                        objects = state["live"] + sum(state["dead"].values())
                        if args.get("baseline"): state["baseline"] = objects
                        return {"totals": {"objects": objects, "nodes": 1, "orphans": 0,
                                           "resources": 1, "static_memory_mib": 1},
                                "diff": {"totals": [["objects", objects - state["baseline"]]],
                                         "classes": [], "orphans": []}}
                    self.fail("unexpected bridge command: " + command)

                output = io.StringIO()
                with patch.multiple(debugctl, SCENARIOS=scenarios, launch=fake_launch, stop=fake_stop,
                                    home_reset=lambda _=None: 0, crawl=lambda _: 0, run_lines=lambda _: 0,
                                    monkey=lambda _: 0, execute_quiet=execute, result_of=result,
                                    new_errors=lambda _: [], current_session=lambda: {}, rss_mib=lambda _: None,
                                    refuse_ambiguous=lambda: False), contextlib.redirect_stdout(output):
                    status = debugctl.smoke([])
                report = json.loads(output.getvalue().strip().splitlines()[-1])
                self.assertEqual(state["sweeps"], {"shadow": 4, "cloud": 4}) # one warm-up and three measured cycles
                self.assertEqual(status, int(growing))
                self.assertEqual(report["ok"], not growing)
                self.assertIn("settle: sweep dead shadow-lighting and cloud-shadow WeakRefs", output.getvalue())
                if growing:
                    self.assertIn("GROWS totals: objects +2", output.getvalue())
                    self.assertIn("soak fly/Home x3", report["failed"])

    def test_home_reset_discards_only_workshop_guard_in_current_language(self) -> None:
        for guard in ("UnsavedBuildDialog", "StatisticsResetDialog"):
            with self.subTest(guard=guard):
                state = {"route": "home", "screens": ["home", "workshop"]}
                calls = []
                window = {"scope": f"AppRoot/Workshop/{guard}", "window": {"type": "ConfirmationDialog"}}

                def result(command, args=None):
                    calls.append((command, args))
                    if command == "state": return state
                    if command == "ui": return window
                    if command == "eval": return "Descartar cambios"
                    if command in ("press", "close"):
                        state["screens"] = ["home"]
                        window.clear()
                    return {}

                with patch.object(debugctl, "result_of", side_effect=result):
                    self.assertEqual(debugctl.home_reset(), 0)
                if guard == "UnsavedBuildDialog":
                    self.assertIn(("press", {"text": "Descartar cambios"}), calls)
                    self.assertFalse(any(command == "close" for command, _ in calls))
                else:
                    self.assertFalse(any(command == "press" for command, _ in calls))
                    self.assertIn(("close", {}), calls)

    def test_an_unreaped_exited_child_is_not_alive(self) -> None:
        if not Path("/proc/self/stat").exists():
            self.skipTest("needs /proc")
        import subprocess
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        deadline = time.monotonic() + 10
        while debugctl.alive(child.pid) and time.monotonic() < deadline:
            time.sleep(0.05)  # never reaped by wait() here: it stays a zombie
        self.assertFalse(debugctl.alive(child.pid))
        child.wait()

    def test_owned_child_is_reaped_without_proc_or_ps(self) -> None:
        import subprocess
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        debugctl._OWNED_PROCESSES[child.pid] = child
        try:
            with patch.object(debugctl.sys, "platform", "darwin"), \
                    patch.object(debugctl.subprocess, "run", side_effect=AssertionError("ps queried for own child")):
                deadline = time.monotonic() + 10
                while debugctl.alive(child.pid) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertFalse(debugctl.alive(child.pid))
                self.assertEqual(child.returncode, 0)
        finally:
            child.wait()

    def test_macos_unowned_zombie_and_unavailable_state(self) -> None:
        for result, expected in ((SimpleNamespace(returncode=0, stdout=" Z+\n"), False),
                                 (SimpleNamespace(returncode=0, stdout=" S\n"), True),
                                 (SimpleNamespace(returncode=1, stdout=""), True)):
            with self.subTest(result=result), patch.object(debugctl.sys, "platform", "darwin"), \
                    patch.object(debugctl.os, "name", "posix"), patch.object(debugctl.os, "kill"), \
                    patch.object(debugctl.subprocess, "run", return_value=result) as ps:
                self.assertEqual(debugctl.alive(123456789), expected)
                ps.assert_called_once_with(["/bin/ps", "-p", "123456789", "-o", "stat="],
                                           capture_output=True, text=True, timeout=1.0)
        for failure in (OSError("ps unavailable"), debugctl.subprocess.TimeoutExpired("ps", 1.0)):
            with self.subTest(failure=failure), patch.object(debugctl.sys, "platform", "darwin"), \
                    patch.object(debugctl.os, "name", "posix"), patch.object(debugctl.os, "kill"), \
                    patch.object(debugctl.subprocess, "run", side_effect=failure):
                self.assertTrue(debugctl.alive(123456789))

    def test_windows_open_process_errors_fail_closed(self) -> None:
        import ctypes
        for error, expected in ((87, False), (5, True), (6, True), (0, True)):
            with self.subTest(error=error):
                kernel = SimpleNamespace(OpenProcess=Mock(return_value=None),
                                         GetExitCodeProcess=Mock(), CloseHandle=Mock())
                with patch.object(debugctl.os, "name", "nt"), \
                        patch.object(ctypes, "WinDLL", return_value=kernel, create=True) as dll, \
                        patch.object(ctypes, "get_last_error", return_value=error, create=True):
                    self.assertEqual(debugctl.alive(123456789), expected)
                dll.assert_called_once_with("kernel32", use_last_error=True)
                kernel.OpenProcess.assert_called_once_with(0x1000, False, 123456789)
                kernel.GetExitCodeProcess.assert_not_called()
                kernel.CloseHandle.assert_not_called()
        with patch.object(debugctl.os, "name", "nt"), \
                patch.object(ctypes, "WinDLL", side_effect=OSError("kernel32 unavailable"), create=True):
            self.assertTrue(debugctl.alive(123456789))

    def test_windows_process_query_status_and_handle_width(self) -> None:
        import ctypes
        from ctypes import wintypes
        handle = 0x100000010  # would be truncated by ctypes' default 32-bit result type
        for query_ok, exit_code, expected in ((False, 0, True), (True, 259, True),
                                              (True, 0, False), (True, 7, False)):
            with self.subTest(query_ok=query_ok, exit_code=exit_code):
                def query(_handle, output):
                    output._obj.value = exit_code
                    return int(query_ok)
                kernel = SimpleNamespace(OpenProcess=Mock(return_value=handle),
                                         GetExitCodeProcess=Mock(side_effect=query), CloseHandle=Mock())
                with patch.object(debugctl.os, "name", "nt"), \
                        patch.object(ctypes, "WinDLL", return_value=kernel, create=True):
                    self.assertEqual(debugctl.alive(123456789), expected)
                self.assertIs(kernel.OpenProcess.restype, wintypes.HANDLE)
                self.assertEqual(kernel.GetExitCodeProcess.argtypes[0], wintypes.HANDLE)
                self.assertEqual(kernel.CloseHandle.argtypes, [wintypes.HANDLE])
                self.assertEqual(kernel.GetExitCodeProcess.call_args.args[0], handle)
                kernel.CloseHandle.assert_called_once_with(handle)

    def test_windows_unknown_process_is_not_forgotten_on_stop(self) -> None:
        import ctypes
        session = {"port": self.bridge.port, "pid": 123456789, "launcher_pid": 123456789}
        kernel = SimpleNamespace(OpenProcess=Mock(return_value=None), GetExitCodeProcess=Mock(), CloseHandle=Mock())
        with patch.object(debugctl.os, "name", "nt"), \
                patch.object(ctypes, "WinDLL", return_value=kernel, create=True), \
                patch.object(ctypes, "get_last_error", return_value=5, create=True), \
                patch.object(debugctl, "ambiguous_target", return_value=[]), \
                patch.object(debugctl, "current_session", return_value=session), \
                patch.object(debugctl, "result_of", side_effect=OSError("bridge unavailable")), \
                patch.object(debugctl, "forget_session") as forget:
            status, output, error = self.run_cli("stop")
        self.assertEqual(status, 2)
        self.assertEqual(output, "")
        self.assertIn("no bridge answered", error)
        forget.assert_not_called()

    def test_stop_reports_and_reaps_already_exited_owned_child(self) -> None:
        import subprocess
        for exit_code in (0, 7):
            with self.subTest(exit_code=exit_code):
                child = subprocess.Popen([sys.executable, "-c", f"raise SystemExit({exit_code})"])
                debugctl._OWNED_PROCESSES[child.pid] = child
                try:
                    deadline = time.monotonic() + 10
                    while debugctl.alive(child.pid) and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertIsNotNone(child.returncode)
                    session = {"port": self.bridge.port, "pid": child.pid, "launcher_pid": child.pid,
                               "out": self.tmp.name}
                    debugctl.write_private(debugctl.SESSIONS / f"{self.bridge.port}.json", session)
                    (Path(self.tmp.name) / "engine.log").write_text("engine exited\n")
                    with patch.object(debugctl, "result_of", side_effect=AssertionError("contacted reused bridge")), \
                            patch.object(debugctl, "kill_group", side_effect=AssertionError("killed exited child")):
                        status, output, _err = self.run_cli("stop")
                    self.assertEqual(status, 0 if exit_code == 0 else 1)
                    report = json.loads(output)
                    self.assertTrue(report["stopped"])
                    self.assertEqual(report["launcher_exit_code"], exit_code)
                    self.assertNotIn(child.pid, debugctl._OWNED_PROCESSES)
                finally:
                    child.wait()

    def test_stop_keeps_unowned_live_launcher_after_engine_exit(self) -> None:
        session = {"port": self.bridge.port, "pid": 111, "launcher_pid": 222, "out": self.tmp.name}
        claim = debugctl.SESSIONS / f"{self.bridge.port}.json"
        for bridge_missing in (True, False):
            with self.subTest(bridge_missing=bridge_missing):
                debugctl.write_private(claim, session)
                quit_result = OSError("bridge unavailable") if bridge_missing else None
                with patch.object(debugctl, "alive", side_effect=lambda pid: pid == 222), \
                        patch.object(debugctl, "result_of", side_effect=quit_result) as quit_request, \
                        patch.object(debugctl, "kill_group", side_effect=AssertionError("unexpected force")), \
                        patch.object(debugctl.time, "monotonic", side_effect=[0.0, 61.0]):
                    status, output, error = self.run_cli("stop")
                self.assertEqual(status, 2 if bridge_missing else 1)
                self.assertEqual(output, "")
                self.assertIn("no bridge answered" if bridge_missing else "still running", error)
                self.assertTrue(claim.exists(), "a live launcher must retain its session claim")
                quit_request.assert_called_once_with("quit", timeout=5.0)

    def test_force_stop_succeeds_after_killing_owned_child(self) -> None:
        import subprocess
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        debugctl._OWNED_PROCESSES[child.pid] = child
        try:
            session = {"port": self.bridge.port, "pid": child.pid, "launcher_pid": child.pid,
                       "out": self.tmp.name}
            debugctl.write_private(debugctl.SESSIONS / f"{self.bridge.port}.json", session)
            (Path(self.tmp.name) / "engine.log").write_text("engine terminated\n")
            with patch.object(debugctl, "result_of", side_effect=OSError("bridge unavailable")), \
                    patch.object(debugctl, "kill_group", side_effect=lambda _pid: child.kill()) as kill, \
                    patch.object(debugctl.time, "monotonic", side_effect=[0.0, 61.0]):
                status, output, _err = self.run_cli("stop", "--force")
            report = json.loads(output)
            self.assertEqual(status, 0)
            self.assertTrue(report["stopped"])
            self.assertTrue(report["forced"])
            self.assertNotIn(report["launcher_exit_code"], (None, 0))
            kill.assert_called_once_with(child.pid)
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()

    def test_smoke_reports_shutdown_failure_after_forced_cleanup(self) -> None:
        scenarios = Path(self.tmp.name) / "empty-scenarios"
        scenarios.mkdir()
        calls = []

        def fake_launch(_args):
            print(json.dumps({"port": self.bridge.port, "out": self.tmp.name, "launcher_pid": 12345}))
            return 0

        def fake_stop(args):
            calls.append(args)
            if args:
                print(json.dumps({"stopped": True, "launcher_exit_code": -9, "crash": None, "leaked_objects": 0}))
            return 1

        output = io.StringIO()
        with patch.multiple(debugctl, SCENARIOS=scenarios, launch=fake_launch, stop=fake_stop,
                            alive=lambda _pid: True, home_reset=lambda *_: 0, crawl=lambda _: 0,
                            run_lines=lambda _: 0, monkey=lambda _: 0, soak=lambda _: 0,
                            result_of=lambda _: {"hitch_total": 0}), contextlib.redirect_stdout(output):
            status = debugctl.smoke([])
        report = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(status, 1)
        self.assertFalse(report["ok"])
        self.assertIn("engine exit (shutdown)", report["failed"])
        self.assertEqual(report["launcher_exit_code"], -9)
        self.assertEqual(calls, [[], ["--force"]])

    def test_smoke_does_not_invent_exit_or_leak_data_when_both_stops_fail(self) -> None:
        scenarios = Path(self.tmp.name) / "empty-scenarios"
        scenarios.mkdir()
        calls = []

        def fake_launch(_args):
            print(json.dumps({"port": self.bridge.port, "out": self.tmp.name, "launcher_pid": 12345}))
            return 0

        def fake_stop(args):
            calls.append(args)
            return 1

        output = io.StringIO()
        with patch.multiple(debugctl, SCENARIOS=scenarios, launch=fake_launch, stop=fake_stop,
                            alive=lambda _pid: True, home_reset=lambda *_: 0, crawl=lambda _: 0,
                            run_lines=lambda _: 0, monkey=lambda _: 0, soak=lambda _: 0,
                            result_of=lambda _: {"hitch_total": 0}), contextlib.redirect_stdout(output):
            status = debugctl.smoke([])
        report = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(status, 1)
        self.assertFalse(report["ok"])
        self.assertIn("engine exit (shutdown)", report["failed"])
        self.assertIsNone(report["launcher_exit_code"])
        self.assertIsNone(report["leaked_objects_at_exit"])
        self.assertEqual(calls, [[], ["--force"]])


if __name__ == "__main__":
    unittest.main()
