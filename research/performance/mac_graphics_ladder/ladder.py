#!/usr/bin/env python3
"""Graphics-option ladder on a real Mac display (DT-MAC-03b; README.md beside this file).

Each run seeds the player's display settings (`user://settings.cfg.display`) in the isolated user
directory of a renamed project snapshot, starts the real app through the debug bridge (Home -> Fly),
flies circle_pilot.py's wide orbit over the clubhouse, measures frames, GPU/CPU/memory and macOS
thermal state, then dives at the pilot station and measures the crash. Python 3.9 compatible.

Usage: ladder.py --work <task dir> --plan plan.json --out <new or resumable dir> [--start-at N]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
import traceback
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from circle_pilot import CirclePilot, import_debugctl  # noqa: E402

PILOT_STATION = (0.0, 0.0, 1.0)  # dive target: the player's station, NED origin, 1 m above ground
SETTINGS_CFG = """[meta]

schema=1

[ui]

language="en"
first_flight_hint_seen=true

[updates]

check=false
"""
# Removed before every run so each starts from the same state; shader_cache stays warm.
RESET_FILES = ("settings.cfg", "settings.cfg.display", "settings.cfg.renderer", "display.cfg",
               "graphics_calibration.cfg", "last_accident.json")

# Every display key written explicitly (DisplayPreferences.save_to layout). Floor = each optional feature at minimum.
FLOOR = {
    "window_mode": "borderless", "window_resolution": "1920x1080", "ui_scale": 1.0,
    "max_fps": 0, "vsync_mode": "disabled", "msaa_3d": 0, "reconstruction": "native", "nvidia_reflex": "on",
    "fsr2_sharpness": 0.9, "scene_detail": "low", "flag_animation": "static", "birds": "off",
    "runway_meadow": "off", "rc_track": "off", "opaque_panels": False, "reduced_motion": False,
    "menu_volume": 0.35, "master_volume": 1.0,
    "aircraft_lighting_quality": "low", "aircraft_lighting_reduced_flashes": False, "aircraft_lighting_show_vfx": False,
    "shadow_quality": "low", "shadow_technique": "off", "shadow_aircraft_cue": "off", "shadow_distance": "near",
    "shadow_softness": "hard", "shadow_cloud": "off",
    "lens_effects": "off", "impact_effects": "off", "impact_colour": "red", "lens_rain": "off",
    "lens_glasses": "off", "lens_grime": "off", "lens_clear_centre": "off",
}
SECTIONS = [
    ("display", [("window_mode", "window_mode"), ("window_resolution", "window_resolution"), ("ui_scale", "ui_scale")]),
    ("graphics", [(k, k) for k in ("max_fps", "vsync_mode", "msaa_3d", "reconstruction", "nvidia_reflex",
                                   "fsr2_sharpness", "scene_detail", "flag_animation", "birds", "runway_meadow",
                                   "rc_track")]),
    ("accessibility", [("opaque_panels", "opaque_panels"), ("reduced_motion", "reduced_motion")]),
    ("audio", [("menu_volume", "menu_volume"), ("master_volume", "master_volume")]),
    ("aircraft_lighting", [("aircraft_lighting_quality", "quality"), ("aircraft_lighting_reduced_flashes", "reduced_flashes"),
                           ("aircraft_lighting_show_vfx", "show_vfx")]),
    ("shadows", [("shadow_quality", "quality"), ("shadow_technique", "technique"), ("shadow_aircraft_cue", "aircraft_cue"),
                 ("shadow_distance", "distance"), ("shadow_softness", "softness"), ("shadow_cloud", "clouds")]),
    ("lens", [("lens_effects", "quality"), ("impact_effects", "impact"), ("impact_colour", "impact_colour"),
              ("lens_rain", "rain"), ("lens_glasses", "glasses"), ("lens_grime", "grime"),
              ("lens_clear_centre", "clear_centre")]),
]


def godot_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return json.dumps(value)


def display_cfg(settings: dict) -> str:
    lines = ["[meta]", "", "schema=1", "reconstruction_auto=true", ""]
    for section, keys in SECTIONS:
        lines += ["[%s]" % section, ""]
        lines += ["%s=%s" % (file_key, godot_value(settings[key])) for key, file_key in keys]
        lines.append("")
    return "\n".join(lines)


def isolated_user_dir(src: Path) -> Path:
    text = (src / "app" / "project.godot").read_text()
    match = re.search(r'^config/name="([^"]+)"$', text, re.M)
    if not match or match.group(1) == "OpenRC Simulator":
        raise SystemExit("rename config/name in the snapshot's app/project.godot first: the player's profile "
                         "(~/Library/.../OpenRC Simulator) must never be touched")
    return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / match.group(1)


def sh(command: list, timeout: float = 300.0) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def gpu_stats() -> dict:
    """AGX PerformanceStatistics from ioreg (no root): device/renderer/tiler utilisation and GPU memory."""
    out = sh(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "AGXAccelerator"], 10).stdout
    match = re.search(r'"PerformanceStatistics" = \{([^}]*)\}', out)
    return {k: int(v) for k, v in re.findall(r'"([^"]+)"=(\d+)', match.group(1))} if match else {}


def cputime_s(pid: int) -> float | None:
    """Accumulated CPU seconds of the process (`ps -o cputime`, [[h:]m:]s.ss); differences give window CPU."""
    try:
        text = sh(["ps", "-o", "cputime=", "-p", str(pid)], 5).stdout.strip()
        seconds = 0.0
        for part in text.split(":"):
            seconds = seconds * 60.0 + float(part)
        return seconds
    except Exception:
        return None


def thermal_now(helper: Path) -> str:
    """macOS ProcessInfo.thermalState through the host-state helper's initial read (stdin closed at once)."""
    if not helper.exists():
        return "unknown"
    try:
        done = subprocess.run([str(helper), str(uuid.uuid4()).upper(), str(os.getpid()), "5"], input="",
                              capture_output=True, text=True, timeout=15)
        for line in done.stdout.splitlines():
            record = json.loads(line)
            if record.get("type") == "initial":
                return str(((record.get("after") or {}).get("thermal") or {}).get("value", "unknown"))
    except Exception:
        pass
    return "unknown"


class Sampler(threading.Thread):
    """Samples game CPU time/RSS and GPU utilisation every `period` seconds until stopped."""

    def __init__(self, pid: int, period: float = 2.0):
        super().__init__(daemon=True)
        self.pid, self.period = pid, period
        self.stop_event = threading.Event()
        self.rows = []

    def run(self):
        while not self.stop_event.is_set():
            row = {"t": time.monotonic(), "cputime_s": cputime_s(self.pid)}
            try:
                row["rss_mib"] = int(sh(["ps", "-o", "rss=", "-p", str(self.pid)], 5).stdout.split()[0]) / 1024.0
            except Exception:
                pass
            stats = gpu_stats()
            row["gpu_device_pct"] = stats.get("Device Utilization %")
            row["gpu_renderer_pct"] = stats.get("Renderer Utilization %")
            row["gpu_tiler_pct"] = stats.get("Tiler Utilization %")
            row["gpu_inuse_mib"] = round(stats.get("In use system memory", 0) / 1048576.0, 1)
            self.rows.append(row)
            self.stop_event.wait(self.period)

    def summary(self) -> dict:
        out = {"samples": len(self.rows)}
        for key in ("rss_mib", "gpu_device_pct", "gpu_renderer_pct", "gpu_tiler_pct", "gpu_inuse_mib"):
            values = [r[key] for r in self.rows if isinstance(r.get(key), (int, float))]
            if values:
                out[key + "_mean"] = round(statistics.mean(values), 1)
                out[key + "_max"] = round(max(values), 1)
        timed = [r for r in self.rows if isinstance(r.get("cputime_s"), float)]
        if len(timed) > 1 and timed[-1]["t"] > timed[0]["t"]:
            # Percent of one core over the sampled interval (100 = one core busy).
            out["cpu_pct_mean"] = round(100.0 * (timed[-1]["cputime_s"] - timed[0]["cputime_s"])
                                        / (timed[-1]["t"] - timed[0]["t"]), 1)
        return out


class FrameCollector:
    """Copies the bridge's raw frame ring (wall ms and physics ticks per frame) incrementally, so a window is
    never truncated by the ring's 7,200-frame capacity. Call poll() at least every few seconds."""

    def __init__(self, bridge):
        self.bridge = bridge
        self.ms, self.ticks = [], []
        bridge("frames", reset=True)
        self.capacity = int(bridge("eval", expr="bridge.FRAME_CAPACITY"))
        self.seen = int(bridge("eval", expr="bridge._frame_count"))
        self.lost = 0

    def poll(self) -> None:
        count = int(self.bridge("eval", expr="bridge._frame_count"))
        if count - self.seen > self.capacity:
            self.lost += count - self.seen - self.capacity
            self.seen = count - self.capacity
        while self.seen < count:
            start = self.seen % self.capacity
            end = min(start + (count - self.seen), self.capacity)
            ms, ticks = self.bridge("eval", expr="[bridge._frame_ms.slice(%d, %d), bridge._frame_ticks.slice(%d, %d)]"
                                    % (start, end, start, end))
            self.ms += [float(v) for v in ms]
            self.ticks += [int(v) for v in ticks]
            self.seen += end - start

    def summary(self) -> dict:
        """Same definitions as the bridge's `frames` (percentile = ceil(q*n)-1; 1 % low = mean of the worst n/100)."""
        n = len(self.ms)
        if n == 0:
            return {"frames": 0, "lost_frames": self.lost}
        ordered = sorted(self.ms)

        def pct(q: float) -> float:
            return round(ordered[min(max(int(-(-q * n // 1)) - 1, 0), n - 1)], 2)
        mean = sum(self.ms) / n
        worst = ordered[n - max(1, n // 100):]
        median = ordered[n // 2]
        threshold = max(50.0, 3.0 * median)
        return {"frames": n, "lost_frames": self.lost, "duration_s": round(sum(self.ms) / 1000.0, 2),
                "mean_ms": round(mean, 2), "p50_ms": pct(0.5), "p95_ms": pct(0.95), "p99_ms": pct(0.99),
                "max_ms": round(ordered[-1], 2), "fps_mean": round(1000.0 / mean, 1),
                "fps_1pct_low": round(1000.0 / (sum(worst) / len(worst)), 1),
                # Uncapped: >16.7 ms frames could not hold 60 Hz. With VSync, >20 ms marks a missed refresh.
                "over_16_7ms_pct": round(100.0 * sum(1 for v in self.ms if v > 1000.0 / 60.0) / n, 2),
                "over_20ms_pct": round(100.0 * sum(1 for v in self.ms if v > 20.0) / n, 2),
                "over_25ms_pct": round(100.0 * sum(1 for v in self.ms if v > 25.0) / n, 2),
                "over_33_3ms_pct": round(100.0 * sum(1 for v in self.ms if v > 1000.0 / 30.0) / n, 2),
                "hitch_threshold_ms": round(threshold, 2), "hitches": sum(1 for v in self.ms if v > threshold),
                "physics_catch_up_frames": sum(1 for t in self.ticks if t >= 12)}

    def bridge_hitches(self) -> list:
        """The bridge's own hitch records since the collector's reset (causes, counters), at most 20."""
        result = self.bridge("frames", window=1)
        return [{k: h.get(k) for k in ("frame", "ms", "physics_ticks", "causes", "deltas", "process_ms")}
                for h in (result.get("hitches") or [])[:20]] + [{"hitch_total": result.get("hitch_total")}]


def collect(collector: FrameCollector, until, timeout: float, poll_s: float = 3.0) -> bool:
    """Checks `until()` every 50 ms and copies frames every `poll_s`, until it is true or the timeout passes."""
    deadline = time.monotonic() + timeout
    next_poll = time.monotonic() + poll_s
    met = False
    while time.monotonic() < deadline:
        if until():
            met = True
            break
        if time.monotonic() >= next_poll:
            collector.poll()
            next_poll += poll_s
        time.sleep(0.05)
    collector.poll()
    return met


class LapCounter:
    """Counts clockwise crossings of one orbit angle (degrees from the orbit centre, 0 = north, 90 = east)."""

    def __init__(self, pilot: CirclePilot, angle: float):
        self.pilot, self.angle = pilot, angle
        self.previous = pilot.angle_on_circle()
        self.crossings = 0

    def update(self) -> int:
        current = self.pilot.angle_on_circle()
        if current is not None and self.previous is not None:
            before = (self.previous - self.angle) % 360.0
            after = (current - self.angle) % 360.0
            if before > 270.0 and after < 90.0:  # wrapped past the reference angle while turning clockwise
                self.crossings += 1
        self.previous = current
        return self.crossings


def wait_for(predicate, timeout: float, period: float = 0.1) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(period)
    return False


class Campaign:
    def __init__(self, work: Path, src: Path, godot: str):
        self.work, self.src, self.godot = work, src, godot
        self.app = src / "app"
        self.user_dir = isolated_user_dir(src)
        self.helper = work / "host-build" / "host-state"
        self.debugctl = import_debugctl(str(src))

    def cli(self, args: list, port: int | None = None, timeout: float = 300.0) -> dict:
        env = dict(os.environ, OPENRC_GODOT=self.godot)
        if port:
            env["OPENRC_DEBUG_BRIDGE"] = str(port)
        done = subprocess.run([sys.executable, str(self.src / "tools/debug/debugctl.py")] + args, capture_output=True,
                              text=True, timeout=timeout, cwd=str(self.src), env=env)
        for line in reversed(done.stdout.strip().splitlines()):
            if line.strip().startswith("{"):
                try:
                    return json.loads(line)
                except ValueError:
                    pass
        return {"ok": False, "stdout": done.stdout[-2000:], "stderr": done.stderr[-2000:], "code": done.returncode}

    def bridge(self, port: int):
        def call(cmd: str, timeout: float = 120.0, **args):
            reply = self.debugctl.request(cmd, args, timeout=timeout, to_port=port)
            if not reply.get("ok"):
                raise RuntimeError("%s refused: %s" % (cmd, reply.get("error")))
            return reply.get("result")
        return call

    def seed(self, settings: dict, out_dir: Path) -> None:
        self.user_dir.mkdir(parents=True, exist_ok=True)
        for name in RESET_FILES:
            if (self.user_dir / name).exists():
                (self.user_dir / name).unlink()
        (self.user_dir / "settings.cfg").write_text(SETTINGS_CFG)
        (self.user_dir / "settings.cfg.display").write_text(display_cfg(settings))
        shutil.copy(str(self.user_dir / "settings.cfg.display"), str(out_dir / "settings.cfg.display"))

    def run_one(self, spec: dict, out_dir: Path, log) -> dict:
        out_dir.mkdir(parents=True)
        result = {"id": out_dir.name, "spec": spec, "started_unix": time.time(), "ok": False}
        settings = dict(FLOOR)
        resolution = spec.get("resolution", "1920x1080")
        settings["window_resolution"] = resolution
        if spec.get("windowed"):
            settings["window_mode"] = "windowed"
        settings.update(spec.get("display", {}))  # an explicit display value (e.g. "auto" size) wins
        self.seed(settings, out_dir)
        result["thermal_at_start"] = thermal_now(self.helper)
        result["pmset_therm_before"] = sh(["pmset", "-g", "therm"], 10).stdout.strip()
        result["gpu_idle_before"] = gpu_stats()
        launch_args = ["launch", "--app", str(self.app), "--resolution", resolution, "--mute", "--timeout", "180"]
        if spec.get("renderer", "mobile") == "forward_plus":
            launch_args += ["--rendering-method", "forward_plus", "--rendering-driver", "metal"]
        began = time.monotonic()
        launch = self.cli(launch_args, timeout=240)
        result["launch_s"] = round(time.monotonic() - began, 2)
        result["launch"] = {k: launch.get(k) for k in ("ok", "port", "pid", "out", "godot", "display", "route")}
        if not launch.get("ok"):
            result["error"] = "launch failed: %s" % json.dumps(launch)[:1500]
            self._write(out_dir, result)
            return result
        port, pid = int(launch["port"]), int(launch["pid"])
        bridge = self.bridge(port)
        helper = sampler = pilot = pilot_thread = None
        try:
            if self.helper.exists():
                # The helper stops at stdin EOF: keep a pipe open and close it at the end.
                helper = subprocess.Popen([str(self.helper), str(uuid.uuid4()).upper(), str(pid), "3600"],
                                          stdin=subprocess.PIPE, stdout=open(str(out_dir / "host-state.jsonl"), "w"),
                                          stderr=subprocess.DEVNULL)
            applied = bridge("prefs").get("display", {})
            mismatched = {k: [settings[k], applied.get(k)] for k in settings
                          if k in applied and applied.get(k) != settings[k]
                          and not (isinstance(settings[k], float) and abs(float(applied.get(k)) - settings[k]) < 1e-9)}
            result["prefs_mismatch"] = mismatched
            if mismatched:
                raise RuntimeError("display settings were not applied: %s" % mismatched)
            result["graphics_auto"] = bridge("graphics_auto")
            method = (result["graphics_auto"].get("inputs") or {}).get("rendering_method")
            if method != spec.get("renderer", "mobile"):
                raise RuntimeError("renderer %s instead of %s" % (method, spec.get("renderer", "mobile")))
            time.sleep(4.0)
            home = FrameCollector(bridge)
            collect(home, lambda: False, 8.0)
            result["home_frames"] = home.summary()

            aircraft = spec.get("aircraft", "jensen-das-ugly-stik-60")
            bridge("setup", aircraft=aircraft, start="airborne", landscape=spec.get("landscape", "club_field"),
                   time_of_day=spec.get("time", "day"))
            began = time.monotonic()
            flown = bridge("fly", timeout=300, aircraft=aircraft, start="airborne")
            result["fly_load_s"] = round(time.monotonic() - began, 2)
            result["fly_start"] = {k: flown.get(k) for k in ("aircraft", "tick", "height_m", "speed_mps", "selection")}

            pilot = CirclePilot(self.debugctl, port, rate_hz=float(spec.get("pilot_hz", 12.0)),
                                log_path=str(out_dir / "pilot.csv"))
            pilot_thread = threading.Thread(target=pilot.run, args=(7200.0,), daemon=True)
            pilot_thread.start()
            converge_s = float(spec.get("converge_s", 32.0))
            if not wait_for(lambda: pilot.failure or (pilot.last and pilot.last["t"] >= converge_s), converge_s + 60):
                raise RuntimeError("pilot did not reach the measurement window")
            if pilot.failure:
                raise RuntimeError("pilot failure before measurement: " + pilot.failure)
            result["render_config"] = config = bridge("render", frames=5).get("config", {})
            bridge("render", measure=False)  # release the bridge's GPU-timestamp lease: windows run without it
            expected = {"msaa_3d": int(settings["msaa_3d"])}
            if settings["window_mode"] == "borderless" or settings["window_resolution"] != "auto":
                expected["size"] = [int(v) for v in settings["window_resolution"].split("x")] \
                    if settings["window_resolution"] != "auto" else None
            effective = {"size": config.get("size"), "msaa_3d": config.get("msaa_3d"),
                         "scaling_3d_mode": config.get("scaling_3d_mode"), "scaling_3d_scale": config.get("scaling_3d_scale")}
            result["effective_mismatch"] = {k: [v, effective.get(k)] for k, v in expected.items()
                                            if v is not None and effective.get(k) != v}

            windows = []
            laps = int(spec.get("laps", 2))
            for index in range(int(spec.get("windows", 1))):
                # Each window starts at the orbit's west point and lasts exactly `laps` laps: the same scene content.
                counter = LapCounter(pilot, 270.0)
                if not wait_for(lambda: pilot.failure or counter.update() >= 1, 60, 0.05) or pilot.failure:
                    raise RuntimeError("pilot did not reach the window start: " + pilot.failure)
                sampler = Sampler(pid)
                collector = FrameCollector(bridge)
                t0 = pilot.last["t"]
                sampler.start()
                done = collect(collector, lambda: bool(pilot.failure) or counter.update() >= 1 + laps,
                               35.0 * laps + 10.0)
                sampler.stop_event.set()
                sampler.join(10)
                frames = collector.summary()
                frames["bridge_hitches"] = collector.bridge_hitches()
                window = {"index": index, "flight_t0": round(t0, 2), "flight_t1": round(pilot.last["t"], 2),
                          "laps": laps, "frames": frames, "process_gpu": sampler.summary(),
                          "pilot": pilot.stats_since(t0)}
                windows.append(window)
                log("    window %d: %.1fs p50 %.2f ms p95 %.2f fps %.1f low1 %.1f gpu %s%% cpu %s%% hitches %s" % (
                    index, frames.get("duration_s") or -1, frames.get("p50_ms") or -1, frames.get("p95_ms") or -1,
                    frames.get("fps_mean") or -1, frames.get("fps_1pct_low") or -1,
                    window["process_gpu"].get("gpu_device_pct_mean"), window["process_gpu"].get("cpu_pct_mean"),
                    frames.get("hitches")))
                if not done or pilot.failure:
                    raise RuntimeError("window did not complete its laps: " + pilot.failure)
            result["windows"] = windows
            result["perf"] = bridge("perf")
            render = bridge("render", frames=60, measure=True)
            result["render"] = {k: render.get(k) for k in ("gpu_ms", "root_gpu_ms", "sub_gpu_ms", "root_cpu_ms",
                                                           "draw_calls", "shadow_draw_calls", "canvas_draw_calls",
                                                           "primitives", "objects", "frame_ms", "fps")}
            result["render"]["viewports"] = len(render.get("viewports") or [])
            if spec.get("screenshots", False):
                if wait_for(lambda: 175 < (pilot.angle_on_circle() or 0) < 190, 40):
                    bridge("screenshot", path=str(out_dir / "clubhouse.jpg"), format="jpg", max_width=1280)
            # Crash: from the east point of the orbit (heading south), dive at the pilot station.
            if not wait_for(lambda: pilot.failure or 80 < (pilot.angle_on_circle() or 0) < 95, 45) or pilot.failure:
                raise RuntimeError("did not reach the dive entry point: " + pilot.failure)
            entry = dict(pilot.last)
            crash_sampler = Sampler(pid, 1.0)
            crash_collector = FrameCollector(bridge)
            crash_sampler.start()
            dive_began = time.monotonic()
            pilot.target = PILOT_STATION
            collect(crash_collector, lambda: not pilot_thread.is_alive(), 30.0)
            impact_s = round(time.monotonic() - dive_began, 2)
            hit = bool(pilot.ended)
            collect(crash_collector, lambda: False, 4.0)
            crash_frames = crash_collector.summary()
            crash_frames["bridge_hitches"] = crash_collector.bridge_hitches()
            crash_sampler.stop_event.set()
            crash_sampler.join(5)
            ended = pilot.ended
            events = bridge("logs", since=0, limit=400)
            texts = [str(r.get("text", "")) for r in (events.get("records") if isinstance(events, dict) else events) or []]
            result["crash"] = {"entry": entry, "impacted": hit, "dive_to_impact_s": impact_s,
                               "impact_state": {k: ended.get(k) for k in ("time_s", "position_ned_m", "speed_mps",
                                                                          "crashed", "paused", "pause_reason")},
                               "log_lines": [t for t in texts if t.startswith(("PROP STRIKE", "CRASH", "PERSON"))
                                             or "strike" in t.lower()][-8:],
                               "frames_dive_impact_plus4s": crash_frames, "process_gpu": crash_sampler.summary()}
            log("    crash: impacted=%s after %.1fs at %s, max %.1f ms, hitches %s" % (
                hit, impact_s, [round(x, 1) for x in (ended.get("position_ned_m") or [])],
                crash_frames.get("max_ms") or -1, crash_frames.get("hitches")))
            if spec.get("screenshots", False):
                bridge("screenshot", path=str(out_dir / "crash.jpg"), format="jpg", max_width=1280)
            result["crash"]["screens_after"] = bridge("state").get("screens")
            if spec.get("restart_timing", False):
                began = time.monotonic()
                bridge("restart", timeout=300)
                ready = wait_for(lambda: ((bridge("state").get("flight") or {}).get("tick") or 0) > 240, 120, 0.2)
                result["restart_after_crash_s"] = round(time.monotonic() - began, 2) if ready else None
            result["logs_summary"] = bridge("logs", summary=True, level="error,warning")
            result["ok"] = True
        except Exception as exc:
            result["error"] = "%s: %s" % (type(exc).__name__, exc)
            result["traceback"] = traceback.format_exc()[-3000:]
        finally:
            if pilot is not None:
                pilot.stop_event.set()
            if sampler is not None:
                sampler.stop_event.set()
            stop = self.cli(["stop"], port=port, timeout=120)
            if not stop.get("stopped"):
                stop = self.cli(["stop", "--force"], port=port, timeout=120)
            result["stop"] = stop
            if helper is not None:
                try:
                    helper.stdin.close()
                    helper.wait(10)
                except Exception:
                    helper.kill()
            launch_out = launch.get("out")
            if launch_out and os.path.isdir(launch_out):
                for name in ("engine.log", "log.jsonl", "launch.json"):
                    if os.path.exists(os.path.join(launch_out, name)):
                        shutil.copy(os.path.join(launch_out, name), str(out_dir / name))
            result["thermal"] = thermal_summary(out_dir / "host-state.jsonl")
            result["finished_unix"] = time.time()
            self._write(out_dir, result)
        return result

    @staticmethod
    def _write(out_dir: Path, result: dict) -> None:
        with open(str(out_dir / "result.json"), "w") as handle:
            json.dump(result, handle, indent=1, default=str)


def thermal_summary(path: Path) -> dict:
    """Counts of macOS ProcessInfo.thermalState snapshots (one per second) and the helper's end reason."""
    counts = {}
    try:
        for line in open(str(path)):
            record = json.loads(line)
            if record.get("type") == "snapshot":
                value = (record.get("thermal") or {}).get("value")
                counts[value] = counts.get(value, 0) + 1
            elif record.get("type") == "trailer":
                counts["_end"] = record.get("reason")
    except Exception as exc:
        return {"error": str(exc)}
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path, help="task directory holding src/ and host-build/")
    parser.add_argument("--src", type=Path, help="renamed source snapshot (default: <work>/src)")
    parser.add_argument("--godot", help="engine executable (default: contents of <work>/engine-path.txt)")
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--start-at", type=int, default=0)
    parser.add_argument("--cooldown", type=float, default=45.0, help="minimum idle seconds between runs")
    parser.add_argument("--thermal-wait", type=float, default=240.0,
                        help="after the cooldown, wait up to this long for thermalState nominal")
    args = parser.parse_args()
    work = args.work.resolve()
    src = (args.src or work / "src").resolve()
    godot = args.godot or (work / "engine-path.txt").read_text().strip()
    campaign = Campaign(work, src, godot)
    plan = json.loads(args.plan.read_text())
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    progress = open(str(out / "progress.log"), "a")

    def log(text: str) -> None:
        line = time.strftime("%H:%M:%S ") + text
        print(line, flush=True)
        progress.write(line + "\n")
        progress.flush()

    log("campaign: %d runs, start at %d, user dir %s" % (len(plan["runs"]), args.start_at, campaign.user_dir))
    for index, run in enumerate(plan["runs"]):
        if index < args.start_at:
            continue
        spec = dict(plan["configs"][run["config"]])
        spec.update(run.get("overrides", {}))
        spec["config"], spec["pass"] = run["config"], run.get("pass", 1)
        out_dir = out / ("%03d-%s-p%d" % (index, run["config"], spec["pass"]))
        if (out_dir / "result.json").exists() and json.loads((out_dir / "result.json").read_text()).get("ok"):
            log("skip %s (done)" % out_dir.name)
            continue
        if out_dir.exists():
            shutil.move(str(out_dir), str(out_dir) + ".failed-%d" % int(time.time()))
        idle_began = time.monotonic()
        time.sleep(args.cooldown)
        state = thermal_now(campaign.helper)
        while state not in ("nominal", "unknown") and time.monotonic() - idle_began < args.cooldown + args.thermal_wait:
            time.sleep(10.0)
            state = thermal_now(campaign.helper)
        spec["idle_before_s"] = round(time.monotonic() - idle_began, 1)
        log("run %s (idle %.0fs, thermal %s)" % (out_dir.name, spec["idle_before_s"], state))
        result = campaign.run_one(spec, out_dir, log)
        window = (result.get("windows") or [{}])[0]
        frames = window.get("frames", {})
        log("  -> ok=%s fps=%s p95=%s gpu=%s%% thermal=%s err=%s" % (
            result.get("ok"), frames.get("fps_mean"), frames.get("p95_ms"),
            (window.get("process_gpu") or {}).get("gpu_device_pct_mean"), result.get("thermal"),
            str(result.get("error", ""))[:300]))
    log("campaign complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
