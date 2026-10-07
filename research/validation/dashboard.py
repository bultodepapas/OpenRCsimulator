#!/usr/bin/env python3
"""VAL-3: offline modal comparisons. Scientific mismatches are report rows, not exit failures."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
UNITS = {"sp_wn": "rad/s", "sp_zeta": "1", "roll_rate": "1/s", "dr_wn": "rad/s", "dr_zeta": "1"}
LABELS = {"sp_wn": "Short-period frequency", "sp_zeta": "Short-period damping", "roll_rate": "Roll decay rate", "dr_wn": "Dutch-roll frequency", "dr_zeta": "Dutch-roll damping"}
RHO, G = 1.225, 9.80665


def require(ok, message):
    if not ok:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def strict_load(path):
    def pairs(items):
        out = {}
        for key, value in items:
            require(key not in out, f"duplicate key: {key}")
            out[key] = value
        return out
    def invalid(value):
        raise ValueError(f"non-finite JSON constant: {value}")
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=pairs, parse_constant=invalid)


def keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected.split()), f"{label}: missing or unknown fields")


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def validate_reference(ref):
    keys(ref, "format id title source conditions comparison rows", "reference")
    require(ref["format"] == "openrc-reference v1", "unsupported reference format")
    require(isinstance(ref["id"], str) and re.fullmatch(r"[a-z0-9-]+", ref["id"]), "invalid reference id")
    require(nonempty(ref["title"]), "missing title")
    source = ref["source"]
    keys(source, "url locator status note", "source")
    require(all(nonempty(source[k]) for k in source), "empty source field")
    require(source["url"].startswith("https://"), "source needs an HTTPS locator")
    require(source["status"] in ("source_checked", "inherited_derivation"), "unsupported provenance status")
    c = ref["conditions"]
    keys(c, "speed_mps mass_kg span_m chord_m area_m2 cg_m throttle wind_mps note", "conditions")
    for key in ("speed_mps", "mass_kg", "span_m", "chord_m", "area_m2"):
        require(number(c[key]) and c[key] > 0, f"invalid condition: {key}")
    for key in ("cg_m", "throttle", "wind_mps"):
        require(c[key] is None or number(c[key]), f"invalid/unknown condition: {key}")
    require(c["throttle"] is None or 0 <= c["throttle"] <= 1, "invalid throttle")
    require(c["wind_mps"] is None or c["wind_mps"] >= 0, "invalid wind")
    require(nonempty(c["note"]), "conditions need their limitations")
    comp = ref["comparison"]
    require(isinstance(comp, dict), "invalid comparison")
    if comp.get("method") == "legacy_scaled":
        keys(comp, "method speed_mps target_span_m note", "comparison")
        require(all(number(comp[k]) and comp[k] > 0 for k in ("speed_mps", "target_span_m")), "invalid legacy condition")
    else:
        keys(comp, "method note", "comparison")
        require(comp["method"] == "same_cl_reduced", "unsupported comparison method")
    require(nonempty(comp["note"]), "comparison needs its limitations")
    require(isinstance(ref["rows"], list) and ref["rows"], "empty reference rows")
    seen = set()
    for row in ref["rows"]:
        keys(row, "metric value unit kind source_locator uncertainty band used_for_tuning tuning_note", "row")
        metric = row["metric"]
        require(isinstance(metric, str) and metric in UNITS and metric not in seen, "duplicate/unsupported metric")
        seen.add(metric)
        require(number(row["value"]) and row["value"] > 0, "reference values must be finite and positive")
        require(row["unit"] == UNITS[metric], "metric/unit mismatch")
        require(row["kind"] in ("measured", "derived", "borrowed"), "invalid reference kind")
        require(nonempty(row["source_locator"]) and nonempty(row["tuning_note"]), "missing row provenance")
        require(row["uncertainty"] is None, "v1 modal imports have unknown uncertainty; do not substitute a screening band")
        require(row["used_for_tuning"] is None or type(row["used_for_tuning"]) is bool, "used_for_tuning must be true, false or null")
        if row["band"] is not None:
            b = row["band"]
            keys(b, "relative kind source", "band")
            require(number(b["relative"]) and 0 < b["relative"] < 1 and b["kind"] == "estimated" and nonempty(b["source"]), "invalid diagnostic band")
    require(seen == set(UNITS), "modal reference requires all five metrics")
    return ref


def references():
    refs = [validate_reference(strict_load(p)) for p in sorted((HERE / "references").glob("*.json"))]
    require(refs and len({r["id"] for r in refs}) == len(refs), "missing or duplicate reference IDs")
    require({"us120", "us25e"} <= {r["id"] for r in refs}, "VAL-3 requires both US120 and 25e references")
    return refs


def fingerprint():
    paths = set()
    for folder in (ROOT / "app/physics", ROOT / "app/sim", ROOT / "app/aircraft", ROOT / "app/input"):
        paths.update(folder.rglob("*.gd"))
    paths.update(ROOT / p for p in ("app/spec.gd", "app/project.godot", "app/get-godot.sh", "app/tests/test_modes.gd", "app/data/aircraft/jensen_ugly_stik_60.json"))
    # Historical derivation cited by us120.json; edits require conscious regeneration.
    paths.update(ROOT / p for p in ("RESEARCH.md", "research/sensitivity/sensitivity.gd"))
    paths.update(HERE.glob("*.py"))
    paths.add(HERE / "collect.gd")
    paths.update((HERE / "references").glob("*.json"))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def collect(refs, clp_scale=1.0):
    require(number(clp_scale) and clp_scale > 0, "invalid Clp scale")
    cases = []
    for ref in refs:
        comp, c = ref["comparison"], ref["conditions"]
        case = {"id": ref["id"], "method": "fixed_speed", "speed_mps": comp.get("speed_mps", 0)}
        if comp["method"] == "same_cl_reduced":
            case.update(method="same_cl", reference_cl=2*c["mass_kg"]*G/(RHO*c["speed_mps"]**2*c["area_m2"]))
        cases.append(case)
    engine = subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True, timeout=300).strip()
    with tempfile.TemporaryDirectory(prefix="openrc-val3-") as directory:
        request, output = Path(directory)/"request.json", Path(directory)/"samples.json"
        request.write_text(json.dumps({"cases": cases, "clp_scale": clp_scale}, allow_nan=False), encoding="utf-8")
        result = subprocess.run([engine, "--headless", "--path", str(ROOT/"app"), "--script", str(HERE/"collect.gd"), "--", str(request), str(output)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
        require(result.returncode == 0 and not re.search(r"^(?:SCRIPT |SHADER )?ERROR:", result.stdout, re.M), "Godot collector failed:\n"+result.stdout)
        require(output.exists(), "collector produced no samples")
        samples = strict_load(output)
    require(samples.get("format") == "openrc-modal-samples v1" and samples.get("clp_scale") == clp_scale, "invalid sample identity")
    require(set(samples["cases"]) == {r["id"] for r in refs}, "sample cases do not match references")
    for key in ("mass_kg", "span_m", "chord_m", "area_m2"):
        require(number(samples[key]) and samples[key] > 0, "invalid model dimensions")
    for case in samples["cases"].values():
        require(all(number(case[k]) for k in UNITS), "non-finite mode sample")
        require(number(case["speed_mps"]) and case["speed_mps"] > 0, "invalid sampled speed")
    for ref in refs:
        if ref["comparison"]["method"] == "legacy_scaled":
            require(math.isclose(samples["span_m"], ref["comparison"]["target_span_m"], abs_tol=1e-9, rel_tol=0), "legacy scaled reference span changed: rederive before reuse")
    return samples


def comparisons(refs, samples):
    rows = []
    for ref in refs:
        case, c = samples["cases"][ref["id"]], ref["conditions"]
        for row in ref["rows"]:
            metric, value, sim, unit = row["metric"], row["value"], case[row["metric"]], row["unit"]
            if ref["comparison"]["method"] == "same_cl_reduced" and metric in ("sp_wn", "dr_wn", "roll_rate"):
                length = "chord_m" if metric == "sp_wn" else "span_m"
                value *= c[length]/(2*c["speed_mps"])
                sim *= samples[length]/(2*case["speed_mps"])
                unit = "1"
            require(number(sim) and number(value) and value > 0, "invalid comparison value")
            band = row["band"]
            limits = [value*(1-band["relative"]), value*(1+band["relative"])] if band else None
            status = "UNASSESSED" if limits is None else ("IN BAND" if limits[0] <= sim <= limits[1] else "OUTSIDE")
            rows.append(dict(reference_id=ref["id"], metric=metric, sim=sim, reference=value, unit=unit,
                             ratio=sim/value, limits=limits, status=status, kind=row["kind"],
                             used_for_tuning=row["used_for_tuning"], provenance=ref["source"]["status"]))
    return rows


def escape(text):
    return str(text).replace("|", "\\|").replace("\n", " ").replace("\r", " ")


def render(refs, document):
    digest = hashlib.sha256(json.dumps(document["input_sha256"], sort_keys=True).encode()).hexdigest()
    lines = ["# VAL-3 — Related-airframe comparison dashboard", "", "**Status:** generated, report-only. This does not validate the owner's Stik or close Gate 2.", "", f"Engine: `{document['samples']['godot']}`. Input inventory SHA-256: `{digest}`.", "", "Regenerate: `python3 research/validation/dashboard.py`; verify freshness: append `--check`.", "", "Ratios are simulation / reference. Bands are estimated class-comparison screens, not source uncertainty, statistical confidence or qualification tolerances. Red rows do not fail software checks. Damping has no invented band. Unknown tuning history is not held-out validation.", "", "| Reference | Metric | Sim | Reference | Unit | Ratio | Estimated band | Status | Kind | Used for tuning |", "| --- | --- | ---: | ---: | --- | ---: | --- | --- | --- | --- |"]
    for row in document["rows"]:
        band = "not assigned" if row["limits"] is None else "%.5g–%.5g" % tuple(row["limits"])
        tuning = {True: "yes", False: "no", None: "unknown"}[row["used_for_tuning"]]
        mark = {"IN BAND": "🟢", "OUTSIDE": "🔴", "UNASSESSED": "⚪"}[row["status"]]
        lines.append(f"| {row['reference_id']} | {LABELS[row['metric']]} | {row['sim']:.6g} | {row['reference']:.6g} | {row['unit']} | {row['ratio']:.4f} | {band} | {mark} {row['status']} | {row['kind']} | {tuning} |")
    for ref in refs:
        case = document["samples"]["cases"][ref["id"]]
        c = ref["conditions"]
        throttle = "unknown" if c["throttle"] is None else f"{100*c['throttle']:.6g}%"
        lines += ["", f"## {escape(ref['title'])}", "", f"Source: [primary document]({ref['source']['url']}); {escape(ref['source']['locator'])}. Provenance: **{ref['source']['status']}**.", "", escape(ref["source"]["note"]), "", escape(ref["comparison"]["note"]), "", f"Simulation: {case['speed_mps']:.6g} m/s, nominal CL {case['lift_coefficient']:.6g}. Reference: {c['speed_mps']:g} m/s; mass {c['mass_kg']:g} kg; span {c['span_m']:g} m; chord {c['chord_m']:g} m; area {c['area_m2']:g} m²; throttle {throttle}.", "", escape(c["note"]), "", escape(case["projection_note"])]
    lines += ["", "## Provenance and limits", "", "Exact input hashes, full-precision samples, estimated bands and tuning flags are in [snapshot.json](snapshot.json). The 15 m/s software regression matches the existing `test_modes.gd` bands; it is separate from the external comparisons. Controls/engine are frozen in this modal analysis; diagonal projections omit cross-axis coupling. The Stik's borrowed derivatives and differing mass, inertia, airfoil and actuation prevent treating another airframe's rows as acceptance targets.", ""]
    return "\n".join(lines)


def build(refs=None, clp_scale=1.0):
    before = fingerprint()
    refs = references() if refs is None else refs
    samples = collect(refs, clp_scale)
    require(fingerprint() == before, "inputs changed during collection; old report preserved")
    document = {"format": "openrc-validation-dashboard v1", "input_sha256": before, "samples": samples, "rows": comparisons(refs, samples)}
    return document, render(refs, document)


def atomic_write(path, text):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", dir=path.parent, delete=False) as file:
            temporary = Path(file.name)
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def publish(document, markdown, check=False, directory=HERE):
    outputs = {directory/"snapshot.json": json.dumps(document, indent=2, sort_keys=True, allow_nan=False)+"\n", directory/"dashboard.md": markdown}
    if check:
        require(all(p.exists() and p.read_text(encoding="utf-8") == text for p, text in outputs.items()), "dashboard is stale; regenerate with dashboard.py")
    else:
        for path, text in outputs.items():
            atomic_write(path, text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="recompute and fail on stale/missing output; never write")
    args = parser.parse_args()
    try:
        document, markdown = build()
        publish(document, markdown, args.check)
        print(f"VAL-3: {len(document['rows'])} rows; "+("fresh" if args.check else "generated")+"; outside-band results are report-only")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"VAL-3: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
