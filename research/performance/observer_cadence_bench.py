#!/usr/bin/env python3
"""VQ-01c-R1: alternating whole-app CPU pairs for the presentation cadence.

Runs app_cpu_per_sim.py for a baseline app copy (per-tick observers) and a candidate app copy at
each requested cadence (OPENRC_PRESENTATION_CADENCE), rotating the role order every pair so drift
is shared. Appends one JSON line per run to <out.jsonl>. Freeze both app copies first (hard-linked
snapshots whose scripts are real copies), so later edits cannot change a run.
Usage: observer_cadence_bench.py <base_app> <cand_app> <out.jsonl> <scenario> <pairs> <cadences,…>
       [warmup_s=10] [sample_s=40] [max_fps=60] [time_scale=0.5] [pause_s=20]
Research-only; see research/performance/README.md#observer-cadence-vq-01c-r1."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def run(app_dir, cadence, label, scenario, warm, sample, fps, scale):
    env = dict(os.environ, OPENRC_APP_DIR=app_dir)
    env.pop("OPENRC_DETACH_PRESENTATION", None)
    if cadence is None:
        env.pop("OPENRC_PRESENTATION_CADENCE", None)
    else:
        env["OPENRC_PRESENTATION_CADENCE"] = str(cadence)
    out = subprocess.run([sys.executable, f"{HERE}/app_cpu_per_sim.py", label, scenario, warm, sample, fps, scale],
                         env=env, capture_output=True, text=True, timeout=600)
    lines = [line for line in out.stdout.splitlines() if line.startswith("{")]
    if out.returncode != 0 or not lines:
        return {"label": label, "scenario": scenario, "error": (out.stdout + out.stderr)[-600:]}
    return json.loads(lines[-1])


def main():
    base, cand, path, scenario, pairs, cadences = sys.argv[1:7]
    warm, sample, fps, scale, pause = (sys.argv[7:12] + ["10", "40", "60", "0.5", "20"][len(sys.argv[7:12]):])
    roles = [("base", base, None)] + [(f"cadence{c}", cand, int(c)) for c in cadences.split(",")]
    for pair in range(int(pairs)):
        # Rotate the order each pair (and reverse odd pairs) so no role always runs first or last.
        order = roles[pair % len(roles):] + roles[:pair % len(roles)]
        if pair % 2:
            order.reverse()
        for name, app_dir, cadence in order:
            result = run(app_dir, cadence, name, scenario, warm, sample, fps, scale)
            result["pair"] = pair + 1
            with open(path, "a") as handle:
                handle.write(json.dumps(result) + "\n")
            print(json.dumps(result), flush=True)
            time.sleep(float(pause))  # the bridge port may sit in TIME_WAIT after a stop


main()
