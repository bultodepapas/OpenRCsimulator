#!/usr/bin/env python3
"""VQ-01c-R1: within-process A/B of the presentation cadence in one live headless flight.

One debug-bridge session (OPENRC_APP_DIR selects a frozen app copy) flies the app_cpu_per_sim.py
scenario, then switches every presentation-cadence gate between the listed modes (0 = per tick)
in rounds of fixed windows. Reversals balance pairwise order and rotations balance positions over a
complete cycle, using the same schedule as observer_cadence_bench.py. Each window reports main-thread
CPU and process frames per simulated second. Drift between windows can remain; a saturated main
thread still trades CPU for frames.
Usage: observer_cadence_ab.py <out.jsonl> airborne|runway <modes,…> [rounds=4] [window_s=8]
       [settle_s=2] [max_fps=60] [time_scale=0.5]
Research-only; see research/performance/README.md#observer-cadence-vq-01c-r1."""
import json, os, subprocess, sys, time

from observer_cadence_bench import role_order

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
D = [sys.executable, f"{REPO}/tools/debug/debugctl.py"]
GATES = ["_windsock_cadence", "_profile_smoke_cadence", "_soundscape_audio._mechanical_cadence",
         "_soundscape_audio._ground_cadence", "_airplane[\"root\"].get_node(\"GroundGearMotion\")._cadence"]


def ctl(port, *args, timeout=300):
    env = dict(os.environ, OPENRC_DEBUG_BRIDGE=str(port))
    out = subprocess.run(D + list(args), cwd=REPO, env=env, capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise SystemExit(f"{args}: {out.stdout}{out.stderr}")
    return out.stdout.strip()


def cpu_s(path):
    fields = open(path).read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")


def set_mode(port, mode):
    # Wheel spin never runs less often than once per frame (ground_gear.gd).
    for gate in GATES:
        value = min(mode, 1) if "GroundGearMotion" in gate else mode
        ctl(port, "eval", "node=AppRoot/Main", f"expr={gate}.set(\"every_frames\", {value})")
    readback = [ctl(port, "eval", "node=AppRoot/Main", f"expr={gate}.every_frames") for gate in GATES]
    return readback


def sample(port, pid, seconds):
    top0 = json.loads(ctl(port, "state", "--json"))
    m0, w0 = cpu_s(f"/proc/{pid}/task/{pid}/stat"), time.monotonic()
    time.sleep(seconds)
    m1, w1 = cpu_s(f"/proc/{pid}/task/{pid}/stat"), time.monotonic()
    top1 = json.loads(ctl(port, "state", "--json"))
    sim_s = top1["flight"]["time_s"] - top0["flight"]["time_s"]
    if sim_s <= 0.0 or top1["flight"]["crashed"] or top1["flight"]["paused"]:
        raise SystemExit(f"invalid window: sim {sim_s} s, crashed={top1['flight']['crashed']}")
    return {"main_ms_per_sim_s": round(1000 * (m1 - m0) / sim_s, 2), "realtime": round(sim_s / (w1 - w0), 4),
            "frames_per_sim_s": round((top1["frame"] - top0["frame"]) / sim_s, 2),
            "height_m": round(top1["flight"]["height_m"], 1)}


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    path, scenario, modes = args[0], args[1], [int(m) for m in args[2].split(",")]
    rounds, window, settle, max_fps, scale = (args[3:8] + ["4", "8", "2", "60", "0.5"][len(args[3:8]):])
    rounds, window, settle, max_fps, scale = int(rounds), float(window), float(settle), int(max_fps), float(scale)
    app_dir = os.environ.get("OPENRC_APP_DIR", "")
    launch = json.loads(ctl(0, "launch", "--headless", *(["--app", app_dir] if app_dir else [])).splitlines()[-1])
    port, pid = launch["port"], launch["pid"]
    total = 30 + 10 + rounds * len(modes) * (window + settle + 4)
    try:
        ctl(port, "eval", f"expr=Engine.set_max_fps({max_fps})")
        ctl(port, "eval", f"expr=Engine.set_time_scale({scale})")
        if scenario == "airborne":
            ctl(port, "fly", "start=airborne")
            ctl(port, "sticks", "throttle=0.62", "pitch=0.02", f"for_s={total}")
        elif scenario == "runway":
            ctl(port, "fly", "start=runway")
            ctl(port, "sticks", "throttle=0.0", f"for_s={total}")
        else:
            raise SystemExit("scenario: airborne|runway")
        time.sleep(10)
        for r in range(rounds):
            for mode in role_order(modes, r):
                readback = set_mode(port, mode)
                time.sleep(settle)
                row = sample(port, pid, window)
                row.update({"scenario": scenario, "round": r + 1, "mode": mode, "max_fps": max_fps,
                            "time_scale": scale, "app_dir": app_dir or "app", "gates": readback})
                with open(path, "a") as handle:
                    handle.write(json.dumps(row) + "\n")
                print(json.dumps(row), flush=True)
    finally:
        ctl(port, "stop")


if __name__ == "__main__":
    main()
