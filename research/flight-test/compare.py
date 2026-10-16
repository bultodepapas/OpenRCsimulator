#!/usr/bin/env python3
"""FT-02: compare two flight-test battery outputs (baseline, candidate) case by case.

Usage: python research/flight-test/compare.py <baseline dir> <candidate dir> [--rel 0.01] [--abs 0.01]
                                              [--out report.md] [--fail-on-change]

Flattens every profile into keys `test.metric` and `test[case].field`, then lists each test whose validity changed and
each value that moved by more than max(--abs, --rel × |baseline|), plus strings and flags that differ. Speeds, rates
and angles share one tolerance pair: tighten or loosen it for the question being asked. Profiles from different card
versions are refused (their cases differ) unless --allow-card-change. A listed change is a difference to explain, not a
verdict: the battery measures the model, it does not validate it.
"""
import argparse
import json
import sys
from pathlib import Path

IGNORED = {"wall_s", "notes"}


def flatten(profile):
    flat = {}
    validity = {}
    for test, result in profile["results"].items():
        validity[test] = "skipped" if result.get("skipped") else ("valid" if result.get("valid") else "not valid")
        for key, value in result.get("metrics", {}).items():
            if isinstance(value, dict):
                for sub, v in value.items():
                    flat[f"{test}.{key}.{sub}"] = v
            elif key not in IGNORED:
                flat[f"{test}.{key}"] = value
        for row in result.get("table", []):
            name = row.get("case")
            if name is None:
                continue
            for field, value in row.items():
                if field != "case":
                    flat[f"{test}[{name}].{field}"] = value
    return flat, validity


def changed(a, b, rel, absolute):
    if isinstance(a, bool) or isinstance(b, bool) or not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
        return a != b, None
    delta = b - a
    return abs(delta) > max(absolute, rel * abs(a)), delta


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("--rel", type=float, default=0.01)
    parser.add_argument("--abs", type=float, default=0.01)
    parser.add_argument("--out")
    parser.add_argument("--fail-on-change", action="store_true")
    parser.add_argument("--allow-card-change", action="store_true")
    args = parser.parse_args()
    base_dir, cand_dir = Path(args.baseline), Path(args.candidate)
    lines = [f"# Flight-test comparison", "", f"Baseline `{base_dir}`, candidate `{cand_dir}`; tolerance max({args.abs}, {args.rel} × |baseline|).", ""]
    total = 0
    for run_file in ("run.json",):
        if (base_dir / run_file).is_file() and (cand_dir / run_file).is_file():
            a = json.loads((base_dir / run_file).read_text(encoding="utf-8"))
            b = json.loads((cand_dir / run_file).read_text(encoding="utf-8"))
            lines.append(f"Card {a.get('card')} → {b.get('card')}; commit {str(a.get('commit'))[:10]} → {str(b.get('commit'))[:10]}"
                         f"{' (candidate dirty)' if b.get('dirty_paths') else ''}.")
            lines.append("")
    aircraft = sorted(p.name for p in base_dir.iterdir() if (p / "profile.json").is_file())
    for name in aircraft:
        cand_profile = cand_dir / name / "profile.json"
        if not cand_profile.is_file():
            lines.append(f"## {name}\n\nMissing from the candidate.\n")
            total += 1
            continue
        a = json.loads((base_dir / name / "profile.json").read_text(encoding="utf-8"))
        b = json.loads(cand_profile.read_text(encoding="utf-8"))
        if a.get("format") != b.get("format") and not args.allow_card_change:
            sys.exit(f"{name}: card {a.get('format')} vs {b.get('format')}: cases differ (use --allow-card-change to compare anyway)")
        fa, va = flatten(a)
        fb, vb = flatten(b)
        rows = []
        for test in sorted(set(va) | set(vb)):
            if va.get(test) != vb.get(test):
                rows.append(f"| {test} | validity | {va.get(test, '–')} | {vb.get(test, '–')} | |")
        for key in sorted(set(fa) | set(fb)):
            if key not in fa or key not in fb:
                rows.append(f"| {key.split('.')[0].split('[')[0]} | {key} | {fa.get(key, '–')} | {fb.get(key, '–')} | added/removed |")
                continue
            moved, delta = changed(fa[key], fb[key], args.rel, args.abs)
            if moved:
                relative = f"{delta:+.4g} ({100.0 * delta / abs(fa[key]):+.1f} %)" if delta is not None and fa[key] not in (0, 0.0) else (f"{delta:+.4g}" if delta is not None else "")
                rows.append(f"| {key.split('.')[0].split('[')[0]} | {key} | {fa[key]} | {fb[key]} | {relative} |")
        total += len(rows)
        lines.append(f"## {b.get('name', name)} — {len(rows)} change(s)")
        lines.append("")
        if a.get("data_sha256") != b.get("data_sha256"):
            lines.append("Aircraft data changed between the runs.")
            lines.append("")
        if rows:
            lines.append("| Test | Value | Baseline | Candidate | Change |")
            lines.append("| --- | --- | --- | --- | --- |")
            lines.extend(rows)
            lines.append("")
    lines.append(f"**{total} change(s) beyond tolerance.**")
    report = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(report, encoding="utf-8")
    print(report)
    sys.exit(1 if args.fail_on_change and total else 0)


if __name__ == "__main__":
    main()
