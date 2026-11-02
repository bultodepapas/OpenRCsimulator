#!/usr/bin/env python3
"""VQ-01c: whole-process CPU per simulated second for one scripted headless flight.

Launches its own debug-bridge session, so every accepted-tick observer, audio and the
simulation are included. Through the bridge it caps the frame rate (Engine.max_fps):
uncapped headless frames absorb any saved time. It also halves Engine.time_scale; Godot
still runs 240 physics ticks per wall second, but delta-driven presentation work shrinks,
so a slow host's main thread stops saturating (a saturated thread hides a gain as drift).
The workload is therefore not normal play; compare roles only under identical settings.
Reports main-thread and whole-process CPU per simulated second on Linux. On macOS,
the direct process CPU is sampled with the pinned psutil resource backend and the
unsupported main-thread measurement is null. OPENRC_APP_DIR must name a validated,
isolated research app on macOS. Child processes are excluded.
Usage: app_cpu_per_sim.py <label> airborne|runway (idle) <warmup_s> <sample_s> [max_fps] [time_scale].
With OPENRC_DETACH_PRESENTATION=1 it disconnects the presentation observers from
Simulation.stepped after the flight starts (windsock/people, ground gear, profile smoke,
flight audio, crash director, statistics), keeping the session commit and the recorder;
it refuses if the connections differ from that expected set.
OPENRC_PRESENTATION_CADENCE=<0..4> reaches the app unchanged (VQ-01c-R1) and is echoed in the result.
Research-only; see research/performance/README.md#whole-app-tick-cpu-vq-01c."""
import importlib.util, json, math, os, subprocess, sys, time
from collections import namedtuple
from pathlib import Path

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
D = [sys.executable, f"{REPO}/tools/debug/debugctl.py"]
AIRCRAFT_ID = "jensen-das-ugly-stik-60"
sys.path.insert(0, f"{REPO}/tools/godot")
from resource_samples import PSUTIL_VERSION, ResourceSampler, load_backend


class MeasurementError(Exception):
    """A CPU or timing observation could not support a comparison."""


CpuReading = namedtuple("CpuReading", "user system main_user main_system")


def ctl(port, *args, timeout=300):
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(port))
    out = subprocess.run(D + list(args), cwd=REPO, env=env, capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise SystemExit(f"{args}: {out.stdout}{out.stderr}")
    return out.stdout.strip()


def _proc_stat(path):
    """Read user/system ticks and start ticks; command names may contain ')'."""
    try:
        with open(path, encoding="utf-8") as handle:
            fields = handle.read().rsplit(")", 1)[1].split()
        user, system, started = (int(fields[index]) for index in (11, 12, 19))
    except (OSError, ValueError, IndexError) as error:
        raise MeasurementError(f"cannot read process CPU from {path}: {error}") from error
    if min(user, system, started) < 0:
        raise MeasurementError(f"invalid process CPU or identity in {path}")
    return user, system, started


class LinuxCpuSampler:
    """Keep the historical procfs process and main-thread counters."""

    cpu_backend = "linux_procfs"
    main_thread_cpu_scope = "main thread of the direct launched process"

    def __init__(self, pid, *, proc_root="/proc", ticks_per_second=None):
        self.process_stat = f"{proc_root}/{pid}/stat"
        self.main_stat = f"{proc_root}/{pid}/task/{pid}/stat"
        self.ticks_per_second = os.sysconf("SC_CLK_TCK") if ticks_per_second is None else ticks_per_second
        if self.ticks_per_second <= 0:
            raise MeasurementError("invalid procfs clock tick frequency")
        self.started = _proc_stat(self.process_stat)[2]

    def sample(self):
        user, system, started = _proc_stat(self.process_stat)
        main_user, main_system, main_started = _proc_stat(self.main_stat)
        # Check again after reading both files so a replacement cannot supply one
        # side of the sample. Creation ticks also identify the original launch.
        latest_started = _proc_stat(self.process_stat)[2]
        if started != self.started or main_started != self.started or latest_started != self.started:
            raise MeasurementError("process PID was reused during CPU measurement")
        ticks = self.ticks_per_second
        return CpuReading(user / ticks, system / ticks, main_user / ticks, main_system / ticks)


class DarwinCpuSampler:
    """Use the shared resource sampler for two independent direct-PID snapshots."""

    cpu_backend = f"psutil_{PSUTIL_VERSION}"
    main_thread_cpu_scope = "unsupported on darwin"

    def __init__(self, pid, *, backend, sampler_class=ResourceSampler):
        self.pid = pid
        self.backend = backend
        self.sampler_class = sampler_class
        # Capture the launch identity before the flight and warm-up, not only
        # after a potentially lengthy delay.
        self.sampler = self._new_sampler()
        self.started = None

    def _new_sampler(self):
        # One poll per sampler avoids imposing its 0.1 s polling interval on the
        # caller's sample window. Compare both creation times explicitly.
        return self.sampler_class(self.pid, backend=self.backend, interval=0.1, max_samples=2)

    def sample(self):
        sampler = self.sampler if self.sampler is not None else self._new_sampler()
        self.sampler = None
        captured = sampler.poll()
        report = sampler.finish()
        if (not captured or report["sample_count"] != 1 or report["identity_status"] != "verified"
                or report["stop_reason"] != "caller_finished"):
            raise MeasurementError(f"process CPU sample unavailable: {report['stop_reason']}; {report['errors']}")
        started = report["process_create_time"]
        if self.started is not None and started != self.started:
            raise MeasurementError("process PID was reused during CPU measurement")
        self.started = started

        # ResourceSampler verifies identity before each poll. Check it again
        # afterward with a fresh object, since psutil caches create_time().
        try:
            process = self.backend.Process(self.pid)
            if process.is_running() is not True or process.create_time() != self.started:
                raise MeasurementError("process exited or PID was reused during CPU measurement")
        except MeasurementError:
            raise
        except Exception as error:
            raise MeasurementError(f"cannot verify process identity after CPU sample: {error}") from error

        sample = report["samples"][0]
        fields = ("cpu_user_seconds", "cpu_system_seconds")
        statuses = sample["field_status"]
        if any(statuses.get(field) != "ok" for field in fields):
            raise MeasurementError(f"process CPU counters unavailable: "
                                   f"{ {field: statuses.get(field, 'missing') for field in fields} }")
        return CpuReading(sample[fields[0]], sample[fields[1]], None, None)


def cpu_sampler_factory(platform):
    if platform.startswith("linux"):
        return LinuxCpuSampler
    if platform == "darwin":
        # Refuse missing or wrong-version psutil before launching a game.
        backend = load_backend()
        return lambda pid: DarwinCpuSampler(pid, backend=backend)
    raise MeasurementError(f"CPU measurement is unsupported on {platform}")


def validated_app_dir(app_dir, platform):
    """Require the existing graphics research isolation contract on macOS."""
    if platform != "darwin":
        return app_dir, None
    if not app_dir.strip():
        raise MeasurementError("macOS requires OPENRC_APP_DIR naming an isolated research app; "
                               "prepare one with tools/graphics/prepare_research.py")
    try:
        spec = importlib.util.spec_from_file_location("openrc_graphics_launch", f"{REPO}/tools/graphics/launch.py")
        if spec is None or spec.loader is None:
            raise ValueError("cannot load the research project validator")
        graphics = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(graphics)
        project = graphics._research_project(app_dir, cwd=Path(REPO))
    except (ValueError, OSError, RuntimeError, ImportError) as error:
        raise MeasurementError(f"macOS research project refused: {error}; "
                               "prepare an isolated app with tools/graphics/prepare_research.py") from error
    return project["path"], project


def _counter_delta(start, end, label):
    values = (start, end)
    if any(type(value) not in (int, float) or not math.isfinite(value) or value < 0 for value in values):
        raise MeasurementError(f"invalid {label} CPU counter")
    if end < start:
        raise MeasurementError(f"{label} CPU counter decreased")
    return end - start


def cpu_deltas(start, end):
    user = _counter_delta(start.user, end.user, "process user")
    system = _counter_delta(start.system, end.system, "process system")
    if start.main_user is None and start.main_system is None and end.main_user is None and end.main_system is None:
        main = None
    else:
        main = (_counter_delta(start.main_user, end.main_user, "main-thread user")
                + _counter_delta(start.main_system, end.main_system, "main-thread system"))
    process = user + system
    if not math.isfinite(process) or (main is not None and not math.isfinite(main)):
        raise MeasurementError("CPU counter delta is not finite")
    return process, main


def boundary_timing(state_calls, cpu_calls, states):
    """Bound endpoint offsets in wall time; do not infer simulation-time error."""
    sequence = (*state_calls[0], *cpu_calls[0], *cpu_calls[1], *state_calls[1])
    if (any(type(value) not in (int, float) or not math.isfinite(value) or value <= 0 for value in sequence)
            or any(later < earlier for earlier, later in zip(sequence, sequence[1:]))):
        raise MeasurementError("invalid monotonic boundary timestamps")
    resolution = time.get_clock_info("monotonic").resolution
    if not math.isfinite(resolution) or resolution <= 0:
        raise MeasurementError("invalid monotonic clock resolution")

    ages, statuses = [], []
    for state in states:
        raw = state.get("snapshot_age_ms")
        if raw is None:
            ages.append(None)
            statuses.append("missing")
            continue
        try:
            value = float(raw) if type(raw) in (int, float) else math.nan
        except (OverflowError, TypeError, ValueError):
            value = math.nan
        if not math.isfinite(value) or value < 0:
            ages.append(None)
            statuses.append("invalid")
        else:
            ages.append(value)
            statuses.append("ok")

    # Godot records integer milliseconds immediately before building a cached
    # state. Its age is computed during the client call. Allow one millisecond
    # for that quantization and Python clock resolution at both endpoints.
    def snapshot_bounds(index):
        if ages[index] is None:
            return None
        start, end = state_calls[index]
        return start - (ages[index] + 1.0) / 1000.0, end

    state0, state1 = snapshot_bounds(0), snapshot_bounds(1)
    allowance = 2 * resolution
    start_bounds = None if state0 is None else [
        cpu_calls[0][0] - state0[1] - allowance,
        cpu_calls[0][1] - state0[0] + allowance,
    ]
    end_bounds = None if state1 is None else [
        state1[0] - cpu_calls[1][1] - allowance,
        state1[1] - cpu_calls[1][0] + allowance,
    ]
    return {
        "clock": "python_monotonic_seconds",
        "clock_resolution_seconds": resolution,
        "state_call_monotonic_seconds": [list(call) for call in state_calls],
        "cpu_call_monotonic_seconds": [list(call) for call in cpu_calls],
        "state_call_duration_seconds": [end - start for start, end in state_calls],
        "cpu_call_duration_seconds": [end - start for start, end in cpu_calls],
        "snapshot_age_ms": ages,
        "snapshot_age_status": statuses,
        "snapshot_age_quantization_ms": 1,
        "start_cpu_minus_state_wall_seconds_bounds": start_bounds,
        "end_state_minus_cpu_wall_seconds_bounds": end_bounds,
        "bounds_scope": "wall-time offsets only; assumes comparable clock rates and no discontinuity; "
                        "does not bound simulation-time error",
    }


PRESENTATION = ["_advance_windsock", "ground_gear.gd)::_stepped", "_sample_profile_smoke",
                "_on_accepted_mechanical_tick", "_on_accepted_hull_tick", "fixed_wing_adapter.gd)::_stepped"]


def detach_presentation(port):
    listing = "str(session.sim.stepped.get_connections())"
    text = ctl(port, "eval", "node=AppRoot/Main", f"expr={listing}").replace('\\"', '"')
    callables = [part.split('"callable": ')[1].split(",")[0] for part in text.split("{")[1:]]
    indices = [i for i, c in enumerate(callables) if any(name in c for name in PRESENTATION)]
    if len(indices) != len(PRESENTATION) or len(callables) != len(PRESENTATION) + 2:
        raise SystemExit(f"unexpected stepped connections: {callables}")
    for i in reversed(indices):
        ctl(port, "eval", "node=AppRoot/Main",
            f"expr=session.sim.stepped.disconnect(session.sim.stepped.get_connections()[{i}].callable)")
    remaining = ctl(port, "eval", "node=AppRoot/Main", f"expr={listing}")
    if any(name in remaining for name in PRESENTATION):
        raise SystemExit("presentation observers still connected")


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if not 4 <= len(args) <= 6:
        raise SystemExit("usage: app_cpu_per_sim.py <label> airborne|runway <warmup_s> <sample_s> [max_fps] [time_scale]")
    label, scenario = args[:2]
    try:
        warm_s, sample_s = float(args[2]), float(args[3])
        max_fps = int(args[4]) if len(args) > 4 else 30
        time_scale = float(args[5]) if len(args) > 5 else 0.5
        if not math.isfinite(warm_s) or warm_s < 0:
            raise ValueError("warm-up must be finite and nonnegative")
        if not math.isfinite(sample_s) or sample_s <= 0:
            raise ValueError("sample duration must be finite and positive")
        if not math.isfinite(time_scale) or time_scale <= 0:
            raise ValueError("time scale must be finite and positive")
        if scenario not in ("airborne", "runway"):
            raise ValueError("scenario: airborne|runway")
        app_dir, research_project = validated_app_dir(os.environ.get("OPENRC_APP_DIR", ""), sys.platform)
        make_sampler = cpu_sampler_factory(sys.platform)
    except (MeasurementError, ValueError) as error:
        raise SystemExit(str(error)) from error
    # OPENRC_APP_DIR runs a frozen baseline or candidate app copy without touching app/.
    launch = json.loads(ctl(0, "launch", "--headless", *(["--app", app_dir] if app_dir else [])).splitlines()[-1])
    port, pid = launch["port"], launch["pid"]
    try:
        sampler = make_sampler(pid)
        # Headless routes keep display preferences in memory, so set the cap directly.
        ctl(port, "eval", f"expr=Engine.set_max_fps({max_fps})")
        ctl(port, "eval", f"expr=Engine.set_time_scale({time_scale})")
        if scenario == "airborne":
            ctl(port, "fly", "start=airborne", f"aircraft={AIRCRAFT_ID}")
            ctl(port, "sticks", "throttle=0.62", "pitch=0.02", f"for_s={warm_s + sample_s + 30}")
        elif scenario == "runway":
            # Idle on the runway: loaded wheels and contact observers, no taxi drift into obstacles.
            ctl(port, "fly", "start=runway", f"aircraft={AIRCRAFT_ID}")
            ctl(port, "sticks", "throttle=0.0", f"for_s={warm_s + sample_s + 30}")
        if os.environ.get("OPENRC_DETACH_PRESENTATION") == "1":
            detach_presentation(port)
        time.sleep(warm_s)
        state0_start = time.monotonic()
        top0 = json.loads(ctl(port, "state", "--json"))
        state0_end = time.monotonic()
        s0 = top0["flight"]
        cpu0_start = time.monotonic()
        c0 = sampler.sample()
        w0 = time.monotonic()
        time.sleep(sample_s)
        cpu1_start = time.monotonic()
        c1 = sampler.sample()
        w1 = time.monotonic()
        state1_start = time.monotonic()
        top1 = json.loads(ctl(port, "state", "--json"))
        state1_end = time.monotonic()
        s1 = top1["flight"]
        perf = json.loads(ctl(port, "perf", "--json"))
        sim_s = s1["time_s"] - s0["time_s"]
        wall_s = w1 - w0
        if (not math.isfinite(sim_s) or sim_s <= 0 or not math.isfinite(wall_s) or wall_s <= 0
                or s1["crashed"] or s1["paused"]):
            raise MeasurementError(f"invalid sample: sim advanced {sim_s} s, wall {wall_s} s, "
                                   f"crashed={s1['crashed']}, paused={s1['paused']}")
        if s0.get("aircraft") != AIRCRAFT_ID or s1.get("aircraft") != AIRCRAFT_ID:
            raise MeasurementError(f"unexpected aircraft: {s0.get('aircraft')!r}, {s1.get('aircraft')!r}; "
                                   f"expected {AIRCRAFT_ID}")
        process_cpu, main_cpu = cpu_deltas(c0, c1)
        boundaries = boundary_timing(((state0_start, state0_end), (state1_start, state1_end)),
                                     ((cpu0_start, w0), (cpu1_start, w1)), (top0, top1))
        result = {
            "label": label, "scenario": scenario, "aircraft": AIRCRAFT_ID,
            "main_ms_per_sim_s": None if main_cpu is None else round(1000 * main_cpu / sim_s, 2),
            "cpu_ms_per_sim_s": round(1000 * process_cpu / sim_s, 2),
            "cpu_backend": sampler.cpu_backend,
            "cpu_scope": "direct launched process; descendants excluded",
            "main_thread_cpu_scope": sampler.main_thread_cpu_scope,
            "cpu_process_pid": pid,
            "warmup_s": warm_s, "sample_s": sample_s, "wall_seconds": wall_s, "simulated_seconds": sim_s,
            "boundary_timing": boundaries,
            "realtime": round(sim_s / wall_s, 4), "sim_step_usec": round(perf["sim_step_usec"], 1),
            "fps": perf["fps"], "max_fps": max_fps, "time_scale": time_scale,
            "presentation_detached": os.environ.get("OPENRC_DETACH_PRESENTATION") == "1",
            "app_dir": app_dir or "app", "height_m": [round(s0["height_m"], 1), round(s1["height_m"], 1)],
            "presentation_cadence": os.environ.get("OPENRC_PRESENTATION_CADENCE", ""),
            # Falling short of the frame cap can indicate saturation, so compare
            # frame and simulation progress as well as CPU per simulated second.
            "frames_per_sim_s": round((top1["frame"] - top0["frame"]) / sim_s, 2),
            "crashed": s1["crashed"], "tick": [s0["tick"], s1["tick"]],
        }
        if research_project is not None:
            result["research_project"] = {"validated_before_launch": True, **research_project}
        try:
            print(json.dumps(result, allow_nan=False))
        except ValueError as error:
            raise MeasurementError(f"non-finite result: {error}") from error
    except MeasurementError as error:
        raise SystemExit(str(error)) from error
    finally:
        ctl(port, "stop")


if __name__ == "__main__":
    main()
