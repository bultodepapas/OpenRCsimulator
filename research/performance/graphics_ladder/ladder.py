#!/usr/bin/env python3
"""Graphics-option ladder on a real display, macOS or Windows/NVIDIA (README.md beside this file).

Each run seeds the player's display settings (`user://settings.cfg.display`) in the isolated user
directory of a renamed project snapshot, starts the real app through the debug bridge (Home -> Fly),
flies circle_pilot.py's wide orbit over the clubhouse, measures frames, GPU/CPU/memory and thermal
state, then dives at the pilot station and measures the crash. Python 3.9 compatible.

macOS: GPU utilisation from ioreg AGX statistics, thermal state from the host-state helper.
Windows: GPU utilisation, clocks, power and temperature from `nvidia-smi`, process CPU/RSS from psutil,
user:// redirected to <work>/profile (debugctl --profile); OPENRC_TESTQUEUE_ROOT must name an unenrolled root.

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
from circle_pilot import CirclePilot, import_debugctl, request_with_retry  # noqa: E402

WINDOWS = sys.platform == "win32"
NO_WINDOW = subprocess.CREATE_NO_WINDOW if WINDOWS else 0
DEFAULT_RENDERER = "forward_plus" if WINDOWS else "mobile"
# Windows passes method and driver explicitly; macOS keeps the DT-MAC-03b launch (Metal only for Forward+).
DEFAULT_DRIVER = ({"forward_plus": "vulkan", "mobile": "vulkan", "gl_compatibility": "opengl3"} if WINDOWS
                  else {"forward_plus": "metal"})
GPU_TEMP_NOMINAL_C = 55.0  # Windows idle gate: "nominal" when the GPU is at or below this temperature
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


def isolated_user_dir(src: Path, profile: Path | None = None) -> Path:
    text = (src / "app" / "project.godot").read_text()
    match = re.search(r'^config/name="([^"]+)"$', text, re.M)
    if not match or match.group(1) == "OpenRC Simulator":
        raise SystemExit("rename config/name in the snapshot's app/project.godot first: the player's profile "
                         "(~/Library/.../OpenRC Simulator) must never be touched")
    if profile is not None:  # Windows: debugctl --profile sets APPDATA, Godot adds Godot/app_userdata/<name>
        return profile / "Godot" / "app_userdata" / match.group(1)
    return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / match.group(1)


def sh(command: list, timeout: float = 300.0) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout, creationflags=NO_WINDOW)


NV_FIELDS = ["utilization.gpu", "utilization.memory", "clocks.gr", "clocks.mem", "power.draw", "temperature.gpu",
             "memory.used", "clocks_event_reasons.active", "pstate"]


def nv_parse(line: str) -> dict:
    row = {}
    for key, value in zip(NV_FIELDS, [v.strip() for v in line.split(",")]):
        try:
            row[key] = float(value)
        except ValueError:
            row[key] = value
    return row


def gpu_stats() -> dict:
    """macOS: AGX PerformanceStatistics from ioreg (no root). Windows: one nvidia-smi query."""
    if WINDOWS:
        out = sh(["nvidia-smi", "--query-gpu=" + ",".join(NV_FIELDS), "--format=csv,noheader,nounits"], 15).stdout
        return nv_parse(out.strip().splitlines()[0]) if out.strip() else {}
    out = sh(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "AGXAccelerator"], 10).stdout
    match = re.search(r'"PerformanceStatistics" = \{([^}]*)\}', out)
    return {k: int(v) for k, v in re.findall(r'"([^"]+)"=(\d+)', match.group(1))} if match else {}


class NvidiaLog(threading.Thread):
    """Windows: one `nvidia-smi -lms 1000` stream per run, logged to JSON lines and sliced per window."""

    def __init__(self, path: Path):
        super().__init__(daemon=True)
        self.path, self.rows = path, []
        self.proc = subprocess.Popen(["nvidia-smi", "--query-gpu=" + ",".join(NV_FIELDS), "--format=csv,noheader,nounits",
                                      "-lms", "1000"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                     creationflags=NO_WINDOW)

    def run(self):
        with open(str(self.path), "w") as out:
            for line in self.proc.stdout:
                if not line.strip():
                    continue
                row = dict(nv_parse(line), t=time.monotonic())
                self.rows.append(row)
                out.write(json.dumps(row) + "\n")
                out.flush()

    def stop(self) -> None:
        try:
            self.proc.terminate()
            self.proc.wait(10)
        except Exception:
            self.proc.kill()

    def window(self, t0: float, t1: float) -> dict:
        rows = [r for r in list(self.rows) if t0 <= r["t"] <= t1]
        out = {"gpu_samples": len(rows)}
        for key, name in (("utilization.gpu", "gpu_device_pct"), ("utilization.memory", "gpu_memctl_pct"),
                          ("clocks.gr", "gpu_clock_mhz"), ("clocks.mem", "gpu_mem_clock_mhz"),
                          ("power.draw", "gpu_power_w"), ("temperature.gpu", "gpu_temp_c"),
                          ("memory.used", "gpu_inuse_mib")):
            values = [r[key] for r in rows if isinstance(r.get(key), float)]
            if values:
                out[name + "_mean"] = round(statistics.mean(values), 1)
                out[name + "_max"] = round(max(values), 1)
                out[name + "_min"] = round(min(values), 1)
        out["gpu_event_reasons"] = sorted({str(r.get("clocks_event_reasons.active")) for r in rows})
        out["gpu_pstates"] = sorted({str(r.get("pstate")) for r in rows})
        return out


def cputime_s(pid: int) -> float | None:
    """Accumulated CPU seconds of the process; differences give window CPU. macOS: `ps -o cputime`."""
    try:
        if WINDOWS:
            import psutil
            times = psutil.Process(pid).cpu_times()
            return float(times.user + times.system)
        text = sh(["ps", "-o", "cputime=", "-p", str(pid)], 5).stdout.strip()
        seconds = 0.0
        for part in text.split(":"):
            seconds = seconds * 60.0 + float(part)
        return seconds
    except Exception:
        return None


def thread_times(pid: int) -> dict:
    """Windows: accumulated CPU seconds per thread id (psutil)."""
    try:
        import psutil
        return {t.id: t.user_time + t.system_time for t in psutil.Process(pid).threads()}
    except Exception:
        return {}


def rss_mib(pid: int) -> float | None:
    try:
        if WINDOWS:
            import psutil
            return psutil.Process(pid).memory_info().rss / 1048576.0
        return int(sh(["ps", "-o", "rss=", "-p", str(pid)], 5).stdout.split()[0]) / 1024.0
    except Exception:
        return None


def thermal_now(helper: Path) -> str:
    """macOS ProcessInfo.thermalState through the host-state helper's initial read (stdin closed at once).
    Windows: "nominal" when the GPU is at or below GPU_TEMP_NOMINAL_C, else its temperature."""
    if WINDOWS:
        try:
            temp = gpu_stats().get("temperature.gpu")
        except Exception:  # a hung or failing nvidia-smi must not end an unattended campaign
            return "unknown"
        if not isinstance(temp, float):
            return "unknown"
        return "nominal" if temp <= GPU_TEMP_NOMINAL_C else "gpu %.0fC" % temp
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

    def __init__(self, pid: int, period: float = 2.0, gpu_log: NvidiaLog | None = None):
        super().__init__(daemon=True)
        self.pid, self.period, self.gpu_log = pid, period, gpu_log
        self.stop_event = threading.Event()
        self.rows = []

    def run(self):
        while not self.stop_event.is_set():
            row = {"t": time.monotonic(), "cputime_s": cputime_s(self.pid), "rss_mib": rss_mib(self.pid)}
            if WINDOWS:
                row["threads"] = thread_times(self.pid)
            if self.gpu_log is None:
                stats = gpu_stats()
                row["gpu_device_pct"] = stats.get("Device Utilization %")
                row["gpu_renderer_pct"] = stats.get("Renderer Utilization %")
                row["gpu_tiler_pct"] = stats.get("Tiler Utilization %")
                row["gpu_inuse_mib"] = round(stats.get("In use system memory", 0) / 1048576.0, 1)
            self.rows.append(row)
            self.stop_event.wait(self.period)

    def summary(self) -> dict:
        out = {"samples": len(self.rows)}
        if self.gpu_log is not None and self.rows:
            out.update(self.gpu_log.window(self.rows[0]["t"], self.rows[-1]["t"]))
        first, last = (self.rows[0], self.rows[-1]) if len(self.rows) > 1 else ({}, {})
        if first.get("threads") and last.get("threads") and last["t"] > first["t"]:
            # Busiest threads over the window, percent of one core: a ~100 % thread is the CPU limit.
            busy = sorted(((100.0 * (last["threads"][tid] - first["threads"].get(tid, 0.0)) / (last["t"] - first["t"]))
                           for tid in last["threads"]), reverse=True)
            out["thread_cpu_pct_top"] = [round(v, 1) for v in busy[:4]]
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


def packed_values(text: str) -> list:
    """Values of a var_to_str'd packed array, e.g. 'PackedFloat64Array(16.6, 17.1)'."""
    inner = str(text)[str(text).index("(") + 1:str(text).rindex(")")].strip()
    return [v for v in inner.split(",") if v.strip()] if inner else []


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
            # One var_to_str string per array: the bridge's per-element JSON conversion of a ~1,000-frame slice
            # costs milliseconds on the main thread, which would land as a spike in a CPU-bound window.
            ms, ticks = self.bridge("eval", expr="[var_to_str(bridge._frame_ms.slice(%d, %d)), "
                                    "var_to_str(bridge._frame_ticks.slice(%d, %d))]" % (start, end, start, end))
            self.ms += [float(v) for v in packed_values(ms)]
            self.ticks += [int(v) for v in packed_values(ticks)]
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
                "over_8_33ms_pct": round(100.0 * sum(1 for v in self.ms if v > 1000.0 / 120.0) / n, 2),
                # With 120 Hz VSync, >12.5 ms marks a missed refresh (the 60 Hz analogue is >20 ms).
                "over_12_5ms_pct": round(100.0 * sum(1 for v in self.ms if v > 12.5) / n, 2),
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
        self.profile = (work / "profile") if WINDOWS else None
        self.expect_screen, self.expect_refresh = None, None  # set by main() on Windows
        self.user_dir = isolated_user_dir(src, self.profile)
        self.helper = work / "host-build" / "host-state"
        self.debugctl = import_debugctl(str(src))
        if WINDOWS:
            root = os.environ.get("OPENRC_TESTQUEUE_ROOT")
            if not root or (Path(root) / "enrollment.json").exists():
                raise SystemExit("set OPENRC_TESTQUEUE_ROOT to an unenrolled root (e.g. U:\\OpenRC\\testqueue): an "
                                 "enrolled queue would stage a multi-GB snapshot per launch on C:")

    def cli(self, args: list, port: int | None = None, timeout: float = 300.0) -> dict:
        env = dict(os.environ, OPENRC_GODOT=self.godot)
        if port:
            env["OPENRC_DEBUG_BRIDGE"] = str(port)
        done = subprocess.run([sys.executable, str(self.src / "tools/debug/debugctl.py")] + args, capture_output=True,
                              text=True, timeout=timeout, cwd=str(self.src), env=env, creationflags=NO_WINDOW)
        for line in reversed(done.stdout.strip().splitlines()):
            if line.strip().startswith("{"):
                try:
                    return json.loads(line)
                except ValueError:
                    pass
        return {"ok": False, "stdout": done.stdout[-2000:], "stderr": done.stderr[-2000:], "code": done.returncode}

    def bridge(self, port: int):
        def call(cmd: str, timeout: float = 120.0, **args):
            reply = request_with_retry(self.debugctl, cmd, args, timeout, port)
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
        if not WINDOWS:
            result["pmset_therm_before"] = sh(["pmset", "-g", "therm"], 10).stdout.strip()
        result["gpu_idle_before"] = gpu_stats()
        # A config may run a sibling copy of the snapshot (same project name, so the same user dir and caches),
        # e.g. one without app/native so the Home -> Fly route falls back to the GDScript reference physics.
        app = (self.src.parent / spec["app_dir"] / "app") if spec.get("app_dir") else self.app
        launch_args = ["launch", "--app", str(app), "--resolution", resolution, "--mute", "--timeout", "180"]
        method = spec.get("renderer", DEFAULT_RENDERER)
        driver = spec.get("driver", DEFAULT_DRIVER.get(method))
        if WINDOWS:
            launch_args += ["--profile", str(self.profile), "--rendering-method", method, "--rendering-driver", driver]
        elif method == "forward_plus":
            launch_args += ["--rendering-method", "forward_plus", "--rendering-driver", "metal"]
        gpu_log = NvidiaLog(out_dir / "gpu.jsonl") if WINDOWS else None
        if gpu_log is not None:
            gpu_log.start()
        result["host_activity"] = {"start": host_activity(app)}
        began = time.monotonic()
        try:
            launch = self.cli(launch_args, timeout=240)
        except Exception as exc:  # e.g. a hung launcher: stop the stream, record, let the campaign continue
            launch = {"ok": False, "exception": "%s: %s" % (type(exc).__name__, exc)}
        result["launch_s"] = round(time.monotonic() - began, 2)
        result["launch"] = {k: launch.get(k) for k in ("ok", "port", "pid", "out", "godot", "display", "route")}
        if not launch.get("ok"):
            result["error"] = "launch failed: %s" % json.dumps(launch)[:1500]
            if gpu_log is not None:
                gpu_log.stop()
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
            actual = (result["graphics_auto"].get("inputs") or {}).get("rendering_method")
            if actual != method:
                raise RuntimeError("renderer %s instead of %s" % (actual, method))
            if WINDOWS:
                names = ["driver", "adapter", "user_dir", "screen_size", "refresh_hz", "screen_scale", "engine"]
                values = bridge("eval", expr="[RenderingServer.get_current_rendering_driver_name(), "
                                "RenderingServer.get_video_adapter_name(), OS.get_user_data_dir(), "
                                "str(DisplayServer.screen_get_size()), DisplayServer.screen_get_refresh_rate(), "
                                "DisplayServer.screen_get_scale(), Engine.get_version_info().string]")
                result["identity"] = identity = dict(zip(names, values))
                if identity["driver"] != driver:
                    raise RuntimeError("rendering driver %s instead of %s" % (identity["driver"], driver))
                # A sleeping or re-linked display changes mode silently: every run must see the expected desktop.
                if self.expect_screen and identity["screen_size"] != self.expect_screen:
                    raise RuntimeError("screen %s instead of %s" % (identity["screen_size"], self.expect_screen))
                if self.expect_refresh and abs(float(identity["refresh_hz"]) - self.expect_refresh) > 1.5:
                    raise RuntimeError("refresh %s Hz instead of %s" % (identity["refresh_hz"], self.expect_refresh))
                if Path(str(identity["user_dir"])).resolve() != self.user_dir.resolve():
                    raise RuntimeError("user dir %s instead of %s" % (identity["user_dir"], self.user_dir))
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
                sampler = Sampler(pid, gpu_log=gpu_log)
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
            crash_sampler = Sampler(pid, 1.0, gpu_log=gpu_log)
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
            result.setdefault("host_activity", {})["end"] = host_activity(app)
            try:
                stop = self.cli(["stop"], port=port, timeout=120)
                if not stop.get("stopped"):
                    stop = self.cli(["stop", "--force"], port=port, timeout=120)
            except Exception as exc:
                stop = {"stopped": False, "exception": "%s: %s" % (type(exc).__name__, exc)}
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
            result["physics_backend"] = physics_backend(out_dir / "engine.log")
            if WINDOWS:
                result["stray_engines_killed"] = kill_stray_engines(self.godot, app)
            if gpu_log is not None:
                gpu_log.stop()
                whole = gpu_log.window(float("-inf"), float("inf"))
                result["thermal"] = {k: whole.get(k) for k in ("gpu_temp_c_max", "gpu_temp_c_mean", "gpu_power_w_max",
                                                               "gpu_clock_mhz_min", "gpu_event_reasons", "gpu_pstates")}
            else:
                result["thermal"] = thermal_summary(out_dir / "host-state.jsonl")
            result["finished_unix"] = time.time()
            self._write(out_dir, result)
        return result

    @staticmethod
    def _write(out_dir: Path, result: dict) -> None:
        with open(str(out_dir / "result.json"), "w") as handle:
            json.dump(result, handle, indent=1, default=str)


def physics_backend(engine_log: Path) -> str | None:
    """The flight's `physics backend:` line (native kernel or GDScript reference, with the refusal reason)."""
    try:
        for line in open(str(engine_log), errors="replace"):
            if "physics backend:" in line:
                return line.split("physics backend:", 1)[1].strip()[:400]
    except OSError:
        pass
    return None


FOREIGN_HEAVY = ("blender", "obs64", "obs32", "ffmpeg", "handbrakecli", "parsecd", "sunshine")  # stems; "godot*" too


def host_activity(app: Path) -> dict:
    """Other work that competes for the CPU/GPU (engines not running this snapshot, encoders, renderers) and
    incoming remote-desktop sessions (RustDesk's connection manager `--cm`, Windows RDP). An attached remote
    session cost the M1 8 % (DT-MAC-03b); these are recorded, not stopped."""
    out = {"foreign": [], "remote": []}
    try:
        import psutil
        app_key = os.path.normcase(str(app.resolve()))
        for proc in psutil.process_iter(["pid", "name", "cmdline"]):
            name = (proc.info.get("name") or "").lower()
            command = " ".join(proc.info.get("cmdline") or [])
            stem = name[:-4] if name.endswith(".exe") else name
            if (stem.startswith("godot") or stem in FOREIGN_HEAVY) and app_key not in os.path.normcase(command):
                out["foreign"].append("%s:%s" % (proc.info["pid"], name))
            if ("rustdesk" in name and "--cm" in command) or name == "rdpclip.exe":
                out["remote"].append("%s:%s %s" % (proc.info["pid"], name, command[:60]))
    except Exception as exc:
        out["error"] = "%s: %s" % (type(exc).__name__, exc)
    if not WINDOWS:
        try:
            text = subprocess.run(["/usr/bin/pmset", "-g", "assertions"], capture_output=True, text=True, timeout=10).stdout
            out["remote"] += [line.strip()[:120] for line in text.splitlines()
                              if any(key in line for key in ("RustDesk", "AnyDesk", "screensharingd", "TeamViewer"))]
        except Exception as exc:
            out["error"] = "%s: %s" % (type(exc).__name__, exc)
    return out


def kill_stray_engines(godot: str, app: Path) -> list:
    """Windows: kill this engine's processes that run this snapshot's app (left by a failed stop or a tree-kill of
    a dead wrapper). Other sessions' engines, even of the same executable, never match the app path."""
    killed = []
    try:
        import psutil
        target = os.path.normcase(os.path.abspath(godot)).replace("_console", "")
        app_key = os.path.normcase(str(app.resolve()))
        for proc in psutil.process_iter(["pid", "exe", "cmdline"]):
            exe = proc.info.get("exe") or ""
            command = os.path.normcase(" ".join(proc.info.get("cmdline") or []))
            if exe and os.path.normcase(exe).replace("_console", "") == target and app_key in command:
                proc.kill()
                killed.append(proc.info["pid"])
    except Exception as exc:
        killed.append("error: %s" % exc)
    return killed


def keep_awake() -> None:
    """Windows: keep the system and display on for the campaign (ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED)."""
    if WINDOWS:
        import ctypes
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001 | 0x00000002)


def disk_low(paths: dict) -> str | None:
    for path, floor_gb in paths.items():
        free = shutil.disk_usage(path).free / 1e9
        if free < floor_gb:
            return "%s has %.1f GB free (floor %.1f GB)" % (path, free, floor_gb)
    return None


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
    parser.add_argument("--profile", type=Path, help="Windows: APPDATA for user:// (default: <work>/profile); keep it on "
                        "the system drive like a player's, since user:// file I/O runs on the main thread")
    parser.add_argument("--godot", help="engine executable (default: contents of <work>/engine-path.txt)")
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--start-at", type=int, default=0)
    parser.add_argument("--cooldown", type=float, default=45.0, help="minimum idle seconds between runs")
    parser.add_argument("--thermal-wait", type=float, default=240.0,
                        help="after the cooldown, wait up to this long for thermalState nominal")
    parser.add_argument("--max-failures", type=int, default=4, help="stop after this many consecutive failed runs")
    parser.add_argument("--expect-screen", help='Windows: required screen size as the bridge prints it, e.g. "(3840, 2160)"')
    parser.add_argument("--expect-refresh", type=float, help="Windows: required display refresh rate in Hz")
    args = parser.parse_args()
    work = args.work.resolve()
    src = (args.src or work / "src").resolve()
    godot = args.godot or (work / "engine-path.txt").read_text().strip()
    campaign = Campaign(work, src, godot)
    if args.profile and WINDOWS:
        campaign.profile = args.profile.resolve()
        campaign.user_dir = isolated_user_dir(src, campaign.profile)
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
    if WINDOWS:
        import psutil  # noqa: F401  (preflight: CPU/RSS sampling needs it)
        keep_awake()
        campaign.expect_screen, campaign.expect_refresh = args.expect_screen, args.expect_refresh
        log("stray engines killed at start: %s" % kill_stray_engines(godot, campaign.app))
    floors = {str(work): 5.0}
    if WINDOWS:
        floors["C:\\"] = 2.0  # NVIDIA shader caches live on C:
    failures_in_row = 0
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
        low = disk_low(floors)
        if low:
            log("campaign stopped: %s" % low)
            return 1
        log("run %s (idle %.0fs, thermal %s)" % (out_dir.name, spec["idle_before_s"], state))
        try:
            result = campaign.run_one(spec, out_dir, log)
        except Exception as exc:  # one broken run must not end an unattended campaign
            result = {"id": out_dir.name, "spec": spec, "ok": False, "error": "%s: %s" % (type(exc).__name__, exc),
                      "traceback": traceback.format_exc()[-3000:]}
            out_dir.mkdir(parents=True, exist_ok=True)
            Campaign._write(out_dir, result)
        window = (result.get("windows") or [{}])[0]
        frames = window.get("frames", {})
        log("  -> ok=%s fps=%s p95=%s gpu=%s%% thermal=%s err=%s" % (
            result.get("ok"), frames.get("fps_mean"), frames.get("p95_ms"),
            (window.get("process_gpu") or {}).get("gpu_device_pct_mean"), result.get("thermal"),
            str(result.get("error", ""))[:300]))
        failures_in_row = 0 if result.get("ok") else failures_in_row + 1
        if failures_in_row >= args.max_failures:
            log("campaign stopped: %d consecutive failures (resume with the same --out)" % failures_in_row)
            return 1
    log("campaign complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
