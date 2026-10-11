#!/usr/bin/env python3
"""E0b7: reduce annotated field observations; never fit or enable propwash."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


UNITS = {"t": "s", "throttle": "1", "rpm": "rpm", "heading": "deg",
         "lateral": "m", "nose_clearance": "m", "nose_load": "N"}
CONFIG = "aircraft motor propeller mass_cg gear controls restraint surface wind heading_frame position_reference synchronization"
LIMITS = [
    "Declared absolute error bounds, not standard uncertainties or confidence intervals; no probability is assigned.",
    "Endpoint difference bounds add both input bounds, without assuming independence; shared errors may make this conservative.",
    "Only annotated samples are summarized; unsampled peaks, first lift time and continuous unloading are unknown.",
    "Heading must be independently unwrapped in the declared ground frame; heading change is not body yaw rate.",
    "Positive nose clearance supports separation at that sample; video alone does not measure normal load.",
    "Synchronization, calibration, geometry, bounds and independent-trial declarations remain observer responsibilities.",
    "Source hashes establish byte identity, not authenticity or physical validity; other campaigns are not searched for split leakage.",
    "No coefficients are inferred, no acceptance tolerance is chosen and no simulator configuration is changed.",
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fields(value, names, label):
    require(isinstance(value, dict) and set(value) == set(names.split()),
            f"{label}: missing/unknown fields")


def text(value, label):
    require(isinstance(value, str) and bool(value.strip()), f"{label}: nonempty text required")


def finite(value, label):
    require(type(value) in (int, float) and math.isfinite(value), f"{label}: finite number required")
    return float(value)


def load(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def bad(value):
        raise ValueError(f"nonfinite JSON constant: {value}")
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad)


def reading(q, channel, evidence):
    fields(q, "value bound unit kind source", channel)
    v, b = finite(q["value"], channel), finite(q["bound"], channel + ".bound")
    require(b >= 0, "negative error bound")
    require(q["unit"] == UNITS[channel], f"{channel}: wrong unit")
    allowed = ("measured", "derived") if evidence == "measured" else ("synthetic",)
    require(q["kind"] in allowed, f"{channel}: evidence kind disagrees with campaign")
    text(q["source"], channel + ".source")
    if channel == "throttle":
        require(0 <= v <= 1, "throttle outside [0,1]")
    if channel == "rpm":
        require(v >= 0, "negative RPM")
    require(math.isfinite(v - b) and math.isfinite(v + b), "reading bounds overflow")


def difference(first, last):
    v = last["value"] - first["value"]
    b = last["bound"] + first["bound"]
    require(all(math.isfinite(x) for x in (v, b, v - b, v + b)), "difference overflow")
    return {"value": v, "bound": b, "unit": first["unit"], "kind": "derived",
            "interval": [v - b, v + b]}


def summarize(samples, channel):
    qs = [s[channel] for s in samples]
    return {"unit": UNITS[channel], "delta": difference(qs[0], qs[-1]),
            "sampled_min": min(q["value"] for q in qs),
            "sampled_max": max(q["value"] for q in qs),
            "sampled_envelope": [min(q["value"] - q["bound"] for q in qs),
                                 max(q["value"] + q["bound"] for q in qs)]}


def reduce(campaign, base):
    """Validate and reduce, including original-file verification for measured campaigns."""
    fields(campaign, "format evidence configuration split_plan runs", "campaign")
    require(campaign["format"] == "openrc-propwash-field v1", "unsupported format")
    evidence = campaign["evidence"]
    require(evidence in ("synthetic", "measured"), "unsupported evidence")
    fields(campaign["configuration"], CONFIG, "configuration")
    for key, value in campaign["configuration"].items():
        text(value, "configuration." + key)
    text(campaign["split_plan"], "split_plan")
    require(isinstance(campaign["runs"], list) and campaign["runs"], "runs required")
    identities, partition, results, sources = set(), {}, [], {}
    coverage = {role: [] for role in ("calibration", "held_out")}

    def reserve(identity, role):
        require(identity not in partition or partition[identity] == role,
                "calibration/held-out leakage: shared trial or source bytes")
        partition[identity] = role

    for run in campaign["runs"]:
        fields(run, "id maneuver role independent_trial notes raw_sources samples", "run")
        name, role, maneuver = run["id"], run["role"], run["maneuver"]
        text(name, "run.id")
        require(name not in identities, "duplicate run ID")
        identities.add(name)
        require(role in coverage, "role must be calibration or held_out")
        require(maneuver in ("nose_unloading", "taxi_blip", "takeoff_swing"), "unknown maneuver")
        for key in ("independent_trial", "notes"):
            text(run[key], key)
        reserve("trial:" + run["independent_trial"], role)
        require(isinstance(run["raw_sources"], list), "raw_sources must be a list")
        require(evidence != "measured" or run["raw_sources"], "measured run needs original sources")
        for source in run["raw_sources"]:
            fields(source, "path sha256", "raw_source")
            text(source["path"], "source.path")
            relative = Path(source["path"])
            require(not relative.is_absolute() and ".." not in relative.parts,
                    "sources must be relative to campaign, without parent traversal")
            digest = source["sha256"]
            require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest), "invalid source SHA-256")
            path = (Path(base) / relative).resolve()
            require(path.is_file(), "missing original source: " + source["path"])
            actual = file_hash(path)
            require(actual == digest, "source SHA-256 mismatch: " + source["path"])
            reserve("sha256:" + digest, role)
            sources[source["path"]] = digest
        samples = run["samples"]
        require(isinstance(samples, list) and len(samples) >= 2, "at least two samples required")
        require(isinstance(samples[0], dict), "sample must be an object")
        channels = set(samples[0])
        require({"t", "throttle", "rpm"} <= channels <= set(UNITS), "missing/unknown sample channels")
        if maneuver == "nose_unloading":
            require(bool(channels & {"nose_load", "nose_clearance"}), "nose observation required")
        else:
            require({"heading", "lateral"} <= channels, "heading and lateral observations required")
        previous = None
        for sample in samples:
            require(isinstance(sample, dict) and set(sample) == channels, "channels must be complete at every sample")
            for channel, q in sample.items():
                reading(q, channel, evidence)
            now = sample["t"]
            if previous is not None:
                require(now["value"] - now["bound"] > previous["value"] + previous["bound"],
                        "sample order unresolved within time bounds")
            previous = now
        summary = {channel: summarize(samples, channel) for channel in sorted(channels)}
        result = {"id": name, "maneuver": maneuver, "role": role,
                  "sample_count": len(samples), "channels": summary}
        if "nose_clearance" in channels:
            result["resolved_clearance_sample_indices"] = [
                i for i, s in enumerate(samples)
                if s["nose_clearance"]["value"] - s["nose_clearance"]["bound"] > 0]
        if "nose_load" in channels:
            result["resolved_endpoint_load_decrease"] = summary["nose_load"]["delta"]["interval"][1] < 0
        results.append(result)
        if maneuver not in coverage[role]:
            coverage[role].append(maneuver)
    return {"format": "openrc-propwash-field-report v1", "evidence": evidence,
            "physical_acceptance": False, "inputs": campaign, "runs": results,
            "coverage": coverage, "verified_sources": sources, "limitations": LIMITS}


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def refuse_alias(output, inputs):
    for path in inputs:
        require(output.resolve() != path.resolve() and
                not (output.exists() and path.exists() and os.path.samefile(output, path)),
                "output aliases an input or reducer")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        raw = args.campaign.read_bytes()
        report = reduce(load(raw), args.campaign.parent)
        inputs = [args.campaign, Path(__file__)] + [args.campaign.parent / p for p in report["verified_sources"]]
        if args.output:
            refuse_alias(args.output, inputs)
        report["input_sha256"] = {"campaign": hashlib.sha256(raw).hexdigest(), "reducer": file_hash(__file__)}
        output = json.dumps(report, sort_keys=True, indent=2, allow_nan=False) + "\n"
        if args.output:
            # Replace only after every check; a failed reduction preserves the prior report.
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent,
                                                 delete=False) as stream:
                    temporary = Path(stream.name)
                    stream.write(output)
                os.replace(temporary, args.output)
            finally:
                if temporary and temporary.exists():
                    temporary.unlink()
        else:
            sys.stdout.write(output)
        return 0
    except (OSError, ValueError, TypeError, OverflowError) as error:
        print(f"E0b7: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
