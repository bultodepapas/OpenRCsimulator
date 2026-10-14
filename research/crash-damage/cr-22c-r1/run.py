"""Native crash timing, serial processes; see the CR-22c-R1 evidence protocol."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

FLEET = [
    "jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t",
    "stik-glow-fs64v-4t", "gp-extra-300s-60", "p51d-mustang-120",
    "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution",
]


def impact_peak(result):
    index = result["impact_frame"]
    if index < 0 or not result["active"] or not result["unchanged"]:
        raise ValueError("Missing crash or presentation changed the simulation checkpoint")
    # process_frame runs before Node._process: retain the following rendered frame
    # and delayed releases too. Exclude unrelated first-motion initialization.
    return max(result["frames_ms"][max(0, index - 1):index + 8])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--aircraft", choices=FLEET, action="append")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    bench = Path(__file__).with_name("bench.gd").resolve()
    sources = [args.project / p for p in ["main.gd", "render/crash/director.gd",
        "render/crash/effects.gd", "render/crash/airframe_scuffs.gd", "render/crash/shader_warmup.gd", "render/crash/wreck.gd",
        "sim/flight_session.gd", "sim/simulation.gd", "physics/aircraft_data.gd"]]
    identities = {str(p.resolve()): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [bench, *sources] if p.is_file()}
    (args.out / "sources.json").write_text(json.dumps(identities, indent=2))
    summary = []
    for aircraft in args.aircraft or FLEET:
        target = args.out / (aircraft + ".json")
        command = [str(args.godot.resolve()), "--path", str(args.project.resolve()),
            "--rendering-driver", "opengl3", "--script", str(bench), "--",
            "--aircraft=" + aircraft, "--out=" + str(target.resolve()),
            "--audio-seed=123", "--flown"]
        log_path = target.with_suffix(".log")
        with log_path.open("w", encoding="utf-8") as log:
            completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        errors = [line for line in log_path.read_text(encoding="utf-8").splitlines()
                  if "ERROR" in line or "WARNING" in line]
        if completed.returncode or errors:
            raise RuntimeError(f"{aircraft}: exit {completed.returncode}; {errors}")
        results = json.loads(target.read_text(encoding="utf-8"))["results"]
        summary.append({"aircraft": aircraft, "impact_peak_ms": [impact_peak(r) for r in results],
                        "classes": [r["class_level"] for r in results]})
        print(summary[-1], flush=True)
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
