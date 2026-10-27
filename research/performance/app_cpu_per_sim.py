#!/usr/bin/env python3
"""VQ-01c: whole-process CPU per simulated second for one scripted headless flight.

Launches its own debug-bridge session, so every accepted-tick observer, audio and the
simulation are included. Through the bridge it caps the frame rate (Engine.max_fps):
uncapped headless frames absorb any saved time. It also halves Engine.time_scale; Godot
still runs 240 physics ticks per wall second, but delta-driven presentation work shrinks,
so a slow host's main thread stops saturating (a saturated thread hides a gain as drift).
The workload is therefore not normal play; compare roles only under identical settings.
Reports main-thread and whole-process CPU per simulated second.
Usage: app_cpu_per_sim.py <label> airborne|runway (idle) <warmup_s> <sample_s> [max_fps] [time_scale].
With OPENRC_DETACH_PRESENTATION=1 it disconnects the presentation observers from
Simulation.stepped after the flight starts (windsock/people, ground gear, profile smoke,
flight audio, crash director, statistics), keeping the session commit and the recorder;
it refuses if the connections differ from that expected set.
OPENRC_PRESENTATION_CADENCE=<0..4> reaches the app unchanged (VQ-01c-R1) and is echoed in the result.
Research-only; see research/performance/README.md#whole-app-tick-cpu-vq-01c."""
import json, os, subprocess, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
D = [sys.executable, f"{REPO}/tools/debug/debugctl.py"]


def ctl(port, *args, timeout=300):
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(port))
    out = subprocess.run(D + list(args), cwd=REPO, env=env, capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise SystemExit(f"{args}: {out.stdout}{out.stderr}")
    return out.stdout.strip()


def cpu_s(path):
    fields = open(path).read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")


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


def main():
    label, scenario = sys.argv[1], sys.argv[2]
    warm_s, sample_s = float(sys.argv[3]), float(sys.argv[4])
    max_fps = int(sys.argv[5]) if len(sys.argv) > 5 else 30
    time_scale = float(sys.argv[6]) if len(sys.argv) > 6 else 0.5
    # OPENRC_APP_DIR runs a baseline app copy (for example a hard-linked snapshot) without touching app/.
    app_dir = os.environ.get("OPENRC_APP_DIR", "")
    launch = json.loads(ctl(0, "launch", "--headless", *(["--app", app_dir] if app_dir else [])).splitlines()[-1])
    port, pid = launch["port"], launch["pid"]
    try:
        # Headless routes keep display preferences in memory, so set the cap directly.
        ctl(port, "eval", f"expr=Engine.set_max_fps({max_fps})")
        ctl(port, "eval", f"expr=Engine.set_time_scale({time_scale})")
        if scenario == "airborne":
            ctl(port, "fly", "start=airborne")
            ctl(port, "sticks", "throttle=0.62", "pitch=0.02", f"for_s={warm_s + sample_s + 30}")
        elif scenario == "runway":
            # Idle on the runway: loaded wheels and contact observers, no taxi drift into obstacles.
            ctl(port, "fly", "start=runway")
            ctl(port, "sticks", "throttle=0.0", f"for_s={warm_s + sample_s + 30}")
        else:
            raise SystemExit("scenario: airborne|runway")
        if os.environ.get("OPENRC_DETACH_PRESENTATION") == "1":
            detach_presentation(port)
        time.sleep(warm_s)
        s0 = json.loads(ctl(port, "state", "--json"))["flight"]
        c0, m0, w0 = cpu_s(f"/proc/{pid}/stat"), cpu_s(f"/proc/{pid}/task/{pid}/stat"), time.monotonic()
        time.sleep(sample_s)
        c1, m1, w1 = cpu_s(f"/proc/{pid}/stat"), cpu_s(f"/proc/{pid}/task/{pid}/stat"), time.monotonic()
        s1 = json.loads(ctl(port, "state", "--json"))["flight"]
        perf = json.loads(ctl(port, "perf", "--json"))
        sim_s = s1["time_s"] - s0["time_s"]
        if sim_s <= 0.0 or s1["crashed"] or s1["paused"]:
            raise SystemExit(f"invalid sample: sim advanced {sim_s} s, crashed={s1['crashed']}, paused={s1['paused']}")
        print(json.dumps({"label": label, "scenario": scenario, "main_ms_per_sim_s": round(1000 * (m1 - m0) / sim_s, 2),
                          "cpu_ms_per_sim_s": round(1000 * (c1 - c0) / sim_s, 2),
                          "realtime": round(sim_s / (w1 - w0), 4), "sim_step_usec": round(perf["sim_step_usec"], 1),
                          "fps": perf["fps"], "max_fps": max_fps, "time_scale": time_scale,
                          "presentation_detached": os.environ.get("OPENRC_DETACH_PRESENTATION") == "1", "app_dir": app_dir or "app", "height_m": [round(s0["height_m"], 1), round(s1["height_m"], 1)],
                          "presentation_cadence": os.environ.get("OPENRC_PRESENTATION_CADENCE", ""),
                          "crashed": s1["crashed"], "tick": [s0["tick"], s1["tick"]]}))
    finally:
        ctl(port, "stop")


main()
