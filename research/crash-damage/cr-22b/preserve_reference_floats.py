#!/usr/bin/env python3
"""Keep a generated aircraft file's committed numbers while taking a regenerated file's new fields.

Use when a generator's --check already fails at HEAD on this platform (last-digit float drift, see LEARNINGS
2026-10-13 CR-01d). Every leaf that exists in the reference keeps the reference value; new keys come from the
regenerated file in its key order. Fails unless every changed reference leaf is a float within --rel of the
regenerated value, so a real change can never be hidden.

    python3 preserve_reference_floats.py <regenerated.json> <reference.json> [--rel 4e-16] [--write <out.json>]
"""
import argparse
import json


def merge(new, ref, path, drift, rel):
    if isinstance(new, dict):
        if not isinstance(ref, dict):
            raise SystemExit(f"{path}: type changed")
        missing = set(ref) - set(new)
        if missing:
            raise SystemExit(f"{path}: keys removed by the generator: {sorted(missing)}")
        return {k: merge(new[k], ref[k], f"{path}/{k}", drift, rel) if k in ref else new[k] for k in new}
    if isinstance(new, list):
        if not isinstance(ref, list) or len(ref) != len(new):
            raise SystemExit(f"{path}: list shape changed")
        return [merge(n, r, f"{path}/{i}", drift, rel) for i, (n, r) in enumerate(zip(new, ref))]
    if new != ref:
        if not (isinstance(new, float) and isinstance(ref, float) and abs(new - ref) <= rel * max(abs(ref), 1.0)):
            raise SystemExit(f"{path}: {ref!r} -> {new!r} is not platform drift")
        drift.append((path, ref, new))
    return ref


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("regenerated")
    parser.add_argument("reference")
    parser.add_argument("--rel", type=float, default=4e-16)
    parser.add_argument("--write")
    args = parser.parse_args()
    drift = []
    out = merge(json.load(open(args.regenerated)), json.load(open(args.reference)), "", drift, args.rel)
    for path, ref, new in drift:
        print(f"kept reference {path}: {ref!r} (regenerated {new!r})")
    if args.write:
        open(args.write, "w", encoding="utf-8").write(json.dumps(out, indent=2, ensure_ascii=False, allow_nan=False) + "\n")
        print(f"wrote {args.write}; {len(drift)} drifted leaves kept at reference values")


if __name__ == "__main__":
    main()
