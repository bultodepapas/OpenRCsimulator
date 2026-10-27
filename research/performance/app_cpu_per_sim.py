#!/usr/bin/env python3
"""VQ-01c: whole-process CPU per simulated second for one scripted headless flight.

Launches its own debug-bridge session, so every accepted-tick observer, audio and the
simulation are included. Usage: app_cpu_per_sim.py <label> airborne|runway <warmup_s> <sample_s>.
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


def cpu_s(pid):
    fields = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")


def main():
    label, scenario = sys.argv[1], sys.argv[2]
    warm_s, sample_s = float(sys.argv[3]), float(sys.argv[4])
    launch = json.loads(ctl(0, "launch", "--headless").splitlines()[-1])
    port, pid = launch["port"], launch["pid"]
    try:
        if scenario == "airborne":
            ctl(port, "fly", "start=airborne")
            ctl(port, "sticks", "throttle=0.62", "pitch=0.02", f"for_s={warm_s + sample_s + 30}")
        elif scenario == "runway":
            ctl(port, "fly", "start=runway")
            ctl(port, "sticks", "throttle=0.25", f"for_s={warm_s + sample_s + 30}")
        else:
            raise SystemExit("scenario: airborne|runway")
        time.sleep(warm_s)
        s0 = json.loads(ctl(port, "state", "--json"))["flight"]
        c0, w0 = cpu_s(pid), time.monotonic()
        time.sleep(sample_s)
        c1, w1 = cpu_s(pid), time.monotonic()
        s1 = json.loads(ctl(port, "state", "--json"))["flight"]
        perf = json.loads(ctl(port, "perf", "--json"))
        sim_s = s1["time_s"] - s0["time_s"]
        print(json.dumps({"label": label, "scenario": scenario, "cpu_ms_per_sim_s": round(1000 * (c1 - c0) / sim_s, 2),
                          "realtime": round(sim_s / (w1 - w0), 4), "sim_step_usec": round(perf["sim_step_usec"], 1),
                          "fps": perf["fps"], "height_m": [round(s0["height_m"], 1), round(s1["height_m"], 1)],
                          "crashed": s1["crashed"], "tick": [s0["tick"], s1["tick"]]}))
    finally:
        ctl(port, "stop")


main()
