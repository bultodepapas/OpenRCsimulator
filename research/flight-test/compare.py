#!/usr/bin/env python3
"""FT-02: compare two flight-test battery outputs (baseline, candidate) case by case.

Usage: python research/flight-test/compare.py <baseline dir> <candidate dir> [--rel 0.01] [--abs 0.01]
          [--out report.md] [--fail-on-change] [--allow-card-change] [--shared-tests]
          [--aircraft-scope union|baseline]

Lists validity changes and values that move by more than max(--abs, --rel × |baseline|), plus changed strings/flags.
The default aircraft roster is the union; baseline scope explicitly excludes candidate-only aircraft. Shared-test
mode names excluded tests. Empty shared aircraft/test coverage and ambiguous or malformed evidence exit 2.
An eligible comparison exits 1 on differences with --fail-on-change, otherwise 0. Validity-only comparisons are
allowed and labeled; null is unavailable, not zero. A difference is not a physical-validity verdict.
"""
import argparse
import json
import math
import sys
from pathlib import Path

from profile_io import finite_number, read_json, read_profile, validate_profile

IGNORED = {"wall_s", "notes"}


def flatten(profile):
    """Keep semantic paths as tuples; punctuation in names cannot alias a path."""
    validate_profile(profile)
    flat, validity = {}, {}

    def add(identity, value):
        if identity in flat:
            raise ValueError(f"duplicate field identity: {identity!r}")
        flat[identity] = value

    for test, result in profile["results"].items():
        validity[test] = "skipped" if result.get("skipped") else ("valid" if result["valid"] else "not valid")
        for key, value in result.get("metrics", {}).items():
            if key in IGNORED:
                continue
            if isinstance(value, dict):
                for sub, v in value.items():
                    add((test, "metrics", key, sub), v)
            else:
                add((test, "metrics", key), value)
        for row in result.get("table", []):
            for field, value in row.items():
                if field != "case":
                    add((test, "table", row["case"], field), value)
    return flat, validity


def field_label(key):
    return key[0] + "." + key[1] + "".join("[" + json.dumps(part, ensure_ascii=False) + "]" for part in key[2:])


def check_receipt(record, aircraft, profile):
    """Use declared receipts when available; legacy missing checks stay unknown."""
    if "aircraft" in profile and profile["aircraft"] != aircraft:
        raise ValueError(f"profile aircraft {profile['aircraft']!r} disagrees with directory {aircraft!r}")
    unknown = [] if "aircraft" in profile else ["profile aircraft identity"]
    if record is None:
        return unknown + ["run receipt"]
    runs = record.get("aircraft")
    receipt = runs.get(aircraft) if isinstance(runs, dict) else None
    if not isinstance(receipt, dict):
        raise ValueError("run manifest has no matching aircraft receipt")
    if type(receipt.get("exit")) is not int or receipt["exit"] != 0:
        raise ValueError(f"aircraft run did not complete successfully: exit={receipt.get('exit')!r}")
    if type(receipt.get("script_errors")) is not int or receipt["script_errors"] != 0:
        raise ValueError("aircraft run has errors or an unknown error count")
    for field in ("child_exit",):
        if field in receipt and (type(receipt[field]) is not int or receipt[field] != 0):
            raise ValueError(f"aircraft receipt has unsuccessful {field}")
    for field in ("launch_error", "profile_error", "data_error"):
        if receipt.get(field) is not None:
            raise ValueError(f"aircraft receipt reports {field}: {receipt[field]}")
    for field in ("data_identity_matches", "test_roster_matches", "capture_complete"):
        if field not in receipt:
            unknown.append(field)
        elif receipt[field] is not True:
            raise ValueError(f"aircraft receipt does not establish {field}")
    if "tests" in receipt and (type(receipt["tests"]) is not int or receipt["tests"] != len(profile["results"])):
        raise ValueError("receipt test count disagrees with profile")
    if "expected_tests" in record:
        expected = record["expected_tests"]
        if (not isinstance(expected, list) or any(not isinstance(t, str) for t in expected)
                or len(set(expected)) != len(expected) or set(expected) != set(profile["results"])):
            raise ValueError("run manifest's expected test roster disagrees with profile")
    if receipt.get("data_identity_matches") is True:
        loaded = profile.get("aircraft_input_sha256")
        if not isinstance(loaded, str) or len(loaded) != 64 or loaded != receipt.get("data_sha256"):
            raise ValueError("receipt loaded identity disagrees with profile")
    return unknown


def changed(a, b, rel, absolute):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is not type(b) or a != b, None
    if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
        return a != b, None
    delta = b - a
    # Finite endpoints can still overflow their difference; that is a difference,
    # never an unchanged result hidden by an infinite tolerance calculation.
    return not finite_number(delta) or abs(delta) > max(absolute, rel * abs(a)), delta


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("--rel", type=float, default=0.01)
    parser.add_argument("--abs", type=float, default=0.01)
    parser.add_argument("--out")
    parser.add_argument("--fail-on-change", action="store_true")
    parser.add_argument("--allow-card-change", action="store_true")
    parser.add_argument("--shared-tests", action="store_true", help="compare only the tests both profiles contain")
    parser.add_argument("--aircraft-scope", choices=("union", "baseline"), default="union",
                        help="union reports aircraft additions/removals; baseline explicitly excludes additions")
    args = parser.parse_args()
    if not all(math.isfinite(value) and value >= 0 for value in (args.rel, args.abs)):
        parser.error("--rel and --abs must be finite and nonnegative")
    base_dir, cand_dir = Path(args.baseline), Path(args.candidate)
    if not base_dir.is_dir() or not cand_dir.is_dir():
        parser.error("baseline and candidate must be existing directories")
    lines = ["# Flight-test comparison", "",
             f"Baseline `{base_dir}`, candidate `{cand_dir}`; tolerance max({args.abs}, {args.rel} × |baseline|).", "",
             f"Aircraft scope: **{args.aircraft_scope}**; test scope: **{'shared only' if args.shared_tests else 'union'}**.", ""]
    total, compared_aircraft, shared_tests, shared_values, available_pairs = 0, 0, 0, 0, 0
    issues = []
    manifests = []
    for folder in (base_dir, cand_dir):
        path = folder / "run.json"
        try:
            record = read_json(path) if path.is_file() else None
            if path.is_file() and not isinstance(record, dict):
                raise ValueError("run manifest must be an object")
            if record is not None:
                for field in ("summary_error", "godot_version_error"):
                    if record.get(field) is not None:
                        issues.append(f"{path}: run reports {field}: {record[field]}")
            manifests.append(record)
        except (OSError, UnicodeError, ValueError) as error:
            issues.append(f"{path}: {error}")
            manifests.append(None)
    if all(record is not None for record in manifests):
        a, b = manifests
        lines += [f"Card {a.get('card')} → {b.get('card')}; commit {str(a.get('commit'))[:10]} → {str(b.get('commit'))[:10]}"
                  f"{' (candidate dirty)' if b.get('dirty_paths') else ''}.", ""]
    else:
        lines += ["Run-level provenance is unavailable on at least one side; profiles are compared independently.", ""]
    baseline = {p.name for p in base_dir.iterdir() if (p / "profile.json").is_file()}
    candidate = {p.name for p in cand_dir.iterdir() if (p / "profile.json").is_file()}
    common = baseline & candidate
    lines += [f"Aircraft profiles: baseline {len(baseline)}, candidate {len(candidate)}, shared {len(common)}.", ""]
    if not common:
        issues.append("no shared aircraft profiles")
    aircraft = baseline | candidate if args.aircraft_scope == "union" else baseline
    if args.aircraft_scope == "baseline":
        lines += ["Excluded candidate-only aircraft: " + (", ".join(sorted(candidate - baseline)) or "none") + ".", ""]
    for name in sorted(aircraft):
        if name not in common:
            lines += [f"## {name}", "", "Missing from the candidate." if name in baseline else "Added in the candidate.", ""]
            total += 1
            continue
        try:
            a = read_profile(base_dir / name / "profile.json")
            b = read_profile(cand_dir / name / "profile.json")
            unknown_a = check_receipt(manifests[0], name, a)
            unknown_b = check_receipt(manifests[1], name, b)
            if any(not isinstance(p.get("format"), str) or not p["format"] for p in (a, b)):
                raise ValueError("both profiles need a nonempty card format")
            if a["format"] != b["format"] and not args.allow_card_change:
                raise ValueError(f"card {a['format']} vs {b['format']}: cases differ (use --allow-card-change)")
            # Validate and flatten the whole input before selecting a subset, so
            # excluded rows cannot conceal ambiguous identities in the evidence.
            fa, va = flatten(a)
            fb, vb = flatten(b)
        except (OSError, UnicodeError, ValueError) as error:
            issues.append(f"{name}: {error}")
            lines += [f"## {name} — ineligible", "", str(error), ""]
            continue
        shared = set(va) & set(vb)
        only = ([f"{t} (baseline only)" for t in sorted(set(va) - shared)]
                + [f"{t} (candidate only)" for t in sorted(set(vb) - shared)])
        if not shared:
            issues.append(f"{name}: no shared tests")
        if args.shared_tests:
            va = {t: v for t, v in va.items() if t in shared}
            vb = {t: v for t, v in vb.items() if t in shared}
            fa = {k: v for k, v in fa.items() if k[0] in shared}
            fb = {k: v for k, v in fb.items() if k[0] in shared}
        paired = set(fa) & set(fb)
        available = sum(fa[k] is not None and fb[k] is not None for k in paired)
        compared_aircraft += 1
        shared_tests += len(shared)
        shared_values += len(paired)
        available_pairs += available
        rows = []
        for test in sorted(set(va) | set(vb)):
            if va.get(test) != vb.get(test):
                rows.append(f"| {test} | validity | {va.get(test, '–')} | {vb.get(test, '–')} | |")
        for key in sorted(set(fa) | set(fb)):
            test, label = key[0], field_label(key)
            if key not in fa or key not in fb:
                rows.append(f"| {test} | {label} | {fa.get(key, '–')} | {fb.get(key, '–')} | added/removed |")
                continue
            moved, delta = changed(fa[key], fb[key], args.rel, args.abs)
            if moved:
                relative = ("difference exceeds float64 range" if delta is not None and not finite_number(delta) else
                            f"{delta:+.4g} ({100.0 * (delta / abs(fa[key])):+.1f} %)"
                            if delta is not None and fa[key] not in (0, 0.0)
                            else f"{delta:+.4g}" if delta is not None else "")
                rows.append(f"| {test} | {label} | {fa[key]} | {fb[key]} | {relative} |")
        total += len(rows)
        lines += [f"## {b.get('name', name)} — {len(rows)} change(s)", "",
                  f"Coverage: {len(shared)} shared tests; {len(paired)} shared value keys; {available} non-null value pairs.", ""]
        if unknown_a or unknown_b:
            lines += [f"Unverified provenance fields: baseline ({', '.join(unknown_a) or 'none'}); "
                      f"candidate ({', '.join(unknown_b) or 'none'}).", ""]
        if args.shared_tests:
            lines += ["Not compared: " + (", ".join(only) or "none") + ".", ""]
        if not available:
            lines += ["No shared non-null measurements: validity/availability comparison only.", ""]
        if a.get("data_sha256") != b.get("data_sha256"):
            lines += ["Aircraft data changed between the runs.", ""]
        if rows:
            lines += ["| Test | Value | Baseline | Candidate | Change |", "| --- | --- | --- | --- | --- |", *rows, ""]
    lines += [f"Total coverage: {compared_aircraft} parsed aircraft pairs, {shared_tests} shared tests, "
              f"{shared_values} shared value keys, {available_pairs} non-null value pairs.", ""]
    if issues:
        lines += ["## Comparison ineligible", "", *["- " + issue for issue in issues], "",
                  f"**{total} observed change(s); incomplete/invalid evidence is not an unchanged result.**"]
    else:
        lines.append(f"**{total} change(s) beyond tolerance.**")
    report = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(report, encoding="utf-8")
    print(report)
    sys.exit(2 if issues else 1 if args.fail_on_change and total else 0)


if __name__ == "__main__":
    main()
