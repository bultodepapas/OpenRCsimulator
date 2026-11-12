"""Run crash_bench.gd per aircraft/scenario serially and summarise frame splits."""
import argparse, json, os, subprocess, statistics, sys
from pathlib import Path

GODOT = os.environ.get("OPENRC_GODOT", str(Path(__file__).resolve().parents[3] / ".tools/Godot_v4.8-beta2_win64_console.exe"))
HERE = Path(__file__).resolve().parent


def summarise(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    for r in data["results"]:
        f = r["frames"]
        i = r["impact_frame"]
        wall = [x[0] for x in f]
        line = f'{r["aircraft"]:30s} {r["scenario"]:5s} run{r["run"]} crashed={r["crashed"]} cls={r["class_level"]} impact_ms={r["impact_us"]/1000:.1f}'
        if i >= 0:
            win = f[max(0, i - 1):i + 8]
            peak = max(win, key=lambda x: x[0])
            line += f' | peak {peak[0]:.1f} ms (ticks {peak[1]}, phys {peak[2]:.1f}, proc {peak[3]:.1f})'
        tail = f[30:] if len(f) > 60 else f
        line += f' | med {statistics.median([x[0] for x in tail]):.1f} p95 {sorted(x[0] for x in tail)[int(len(tail)*0.95)-1]:.1f} max {max(wall):.1f}'
        phys_per_tick = [x[2] / x[1] for x in tail if x[1]]
        if phys_per_tick:
            line += f' | phys/tick med {statistics.median(phys_per_tick):.2f} ms; proc med {statistics.median([x[3] for x in tail]):.1f}'
        line += f' | h={r["height"]:.2f}'
        print(line)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--project", default=str(Path(__file__).resolve().parents[3] / "app"))
    p.add_argument("--out", required=True)
    p.add_argument("--aircraft", action="append", required=True)
    p.add_argument("--scenario", action="append", default=None)
    p.add_argument("--summary-only", action="store_true")
    p.add_argument("--flag", action="append", default=[])
    a = p.parse_args()
    out = Path(a.out).resolve(); out.mkdir(parents=True, exist_ok=True)
    for ac in a.aircraft:
        for sc in a.scenario or ["hard"]:
            target = out / f"{ac}-{sc}{'-'.join(['']+a.flag)}.json"
            if not a.summary_only:
                cmd = [GODOT, "--path", a.project, "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
                       "--script", str(HERE / "crash_bench.gd"), "--", f"--aircraft={ac}", f"--out={target}",
                       f"--scenario={sc}", *[f"--{x}" for x in a.flag]]
                with target.with_suffix(".log").open("w", encoding="utf-8") as log:
                    rc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=240).returncode
                if rc or not target.exists():
                    print(ac, sc, "FAILED rc", rc); continue
            summarise(target)
            sys.stdout.flush()


if __name__ == "__main__":
    main()
