"""IAQ-00: fly the flight-test card on every exported Phoenix Creator record and tabulate the results.

Input is the `trials/` folder written by `creator_corpus.gd --export-trials` (local, never committed). Each record
is flown by `research/flight-test/flight_test.gd --record=` with a fixed test selection; the summary keeps one row
per model with the card's own validity flags. Software evidence of what OpenRC does with the derived packages, not a
comparison with Phoenix or a physical validation.

    python3 research/aircraft-creator/phoenix/flight_cards.py --godot <godot> --trials <out>/trials \\
        --out <new folder> [--jobs 4] [--only name,name]
Writes <out>/<model>/profile.{json,md} (the card's own files), <out>/cards.json and <out>/cards.md.
"""
import argparse
import concurrent.futures
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
CARD = ROOT / "research" / "flight-test" / "flight_test.gd"
TESTS = "trim_sweep,stall_power_off,vmax,hands_off,climb,glide,roll_rate"
FORMAT = "openrc-phoenix-flight-cards-v1"


def metric(profile, test, key):
    result = profile.get("results", {}).get(test, {})
    return result.get("metrics", {}).get(key) if result.get("valid") else None


def best(profile, test, key):
    result = profile.get("results", {}).get(test, {})
    if not result.get("valid"):
        return None
    return (result.get("metrics", {}).get("best") or {}).get(key)


def roll_rate(profile):
    result = profile.get("results", {}).get("roll_rate", {})
    if not result.get("valid"):
        return None
    rates = [abs(row.get("max_roll_rate_dps", 0.0)) for row in result.get("table", []) if str(row.get("case", "")).startswith("start_")]
    return round(max(rates), 1) if rates else None


def summarize(model, profile):
    results = profile.get("results", {})
    return {
        "model": model,
        "mass_kg": profile.get("mass_kg"),
        "span_m": profile.get("span_m"),
        "valid_tests": sum(1 for r in results.values() if r.get("valid")),
        "tests": len(results),
        "stall_speed_mps": metric(profile, "stall_power_off", "stall_speed_mps"),
        "max_level_speed_mps": metric(profile, "vmax", "max_level_speed_mps"),
        "cruise_throttle_at_start": metric(profile, "trim_sweep", "cruise_throttle_at_start_speed"),
        "best_climb_mps": best(profile, "climb", "vertical_speed_mps"),
        "best_glide_ratio": best(profile, "glide", "glide_ratio"),
        "roll_rate_dps": roll_rate(profile),
        "hands_off_heading_30_s_deg": metric(profile, "hands_off", "heading_change_30_s_deg"),
        "hands_off_height_30_s_m": metric(profile, "hands_off", "height_change_30_s_m"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", required=True)
    parser.add_argument("--trials", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument("--only", default="")
    parser.add_argument("--tests", default=TESTS)
    parser.add_argument("--timeout", type=float, default=1800.0)
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    if out.exists() and any(out.iterdir()):
        parser.error("--out must be a new or empty folder")
    out.mkdir(parents=True, exist_ok=True)
    wanted = {n for n in args.only.split(",") if n}
    records = sorted(p for p in pathlib.Path(args.trials).glob("*.json") if not wanted or p.stem in wanted)
    if not records:
        sys.exit("no exported records under " + args.trials)

    def fly(record):
        command = [args.godot, "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy", "--script", str(CARD), "--",
                   "--aircraft=" + record.stem, "--record=" + str(record), "--out=" + str(out), "--only=" + args.tests]
        try:
            run = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=args.timeout)
            code = run.returncode
            errors = run.stdout.count("SCRIPT ERROR") + run.stderr.count("SCRIPT ERROR")
        except subprocess.TimeoutExpired:
            code, errors = "timeout", 0
        profile_path = out / record.stem / "profile.json"
        profile = json.loads(profile_path.read_text(encoding="utf-8")) if profile_path.exists() else {}
        row = summarize(record.stem, profile)
        row["exit"] = code
        row["script_errors"] = errors
        return row

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        rows = list(pool.map(fly, records))
    rows.sort(key=lambda r: r["model"])
    (out / "cards.json").write_text(json.dumps({"format": FORMAT, "tests": args.tests, "models": rows}, indent=1) + "\n", encoding="utf-8")
    columns = ["model", "mass_kg", "valid_tests", "stall_speed_mps", "max_level_speed_mps", "cruise_throttle_at_start",
               "best_climb_mps", "best_glide_ratio", "roll_rate_dps", "hands_off_heading_30_s_deg", "hands_off_height_30_s_m"]
    lines = ["# Phoenix Creator flight cards", "", "Card tests: `%s`. Software evidence, not physical validation." % args.tests, "",
             "| " + " | ".join(columns) + " |", "|" + " --- |" * len(columns)]
    for row in rows:
        lines.append("| " + " | ".join("" if row.get(c) is None else str(row.get(c)) for c in columns) + " |")
    (out / "cards.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    failed = [r["model"] for r in rows if r["exit"] != 0 or r["script_errors"]]
    print("flew %d records, %d with a non-zero exit or script errors%s" % (len(rows), len(failed), (": " + ", ".join(failed)) if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
