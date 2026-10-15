"""Apply or verify the three D11g rate derivatives without reserializing aircraft JSON.

Create `report.json` from derive_rate_derivatives.gd's `--json` output, then use
`--check` or `--write`. The updater changes only the value/source leaves for
Cmq, CLq and Cnr; units, kinds, and every other input byte remain unchanged.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_AIRCRAFT = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
RATE_KEYS = ("Cmq", "CLq", "Cnr")
EXPECTED_SCHEMA = "d11g-rate-derivatives-v2"
EXPECTED_LAW = "section-plane-source-weighted-wake-velocity-v2"
FINGERPRINT_SCHEME = "utf8-source-text-v1"
SOURCE_IDENTITY_SCHEME = "sha256-source-files-v1"
EXCLUDED_OUTPUT_LEAVES = tuple(
    f"aero.coefficients.{key}.{leaf}"
    for key in RATE_KEYS
    for leaf in ("value", "source")
)
SOLVER_SOURCE_PATHS = (
    "app/physics/aero.gd",
    "app/physics/air_data.gd",
    "app/physics/aircraft_contract.gd",
    "app/physics/aircraft_data.gd",
    "app/physics/control_surfaces.gd",
    "app/physics/dynamics.gd",
    "app/physics/electric_motor.gd",
    "app/physics/electric_supply.gd",
    "app/physics/glow/installation.gd",
    "app/physics/ground_effect.gd",
    "app/physics/math3d.gd",
    "app/physics/physical_identity.gd",
    "app/physics/propulsion.gd",
    "app/physics/rigid_body.gd",
    "app/physics/trim.gd",
    "app/physics/wheel_profiles.gd",
    "app/physics/wing_polar.gd",
    "research/aero/d11g/derive_rate_derivatives.gd",
)


def object_end(text: str, open_index: int) -> int:
    if open_index >= len(text) or text[open_index] != "{":
        raise ValueError("expected an object opening brace")
    depth = 0
    in_string = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unterminated JSON object")


def member_object_span(text: str, object_open: int, object_close: int, key: str) -> tuple[int, int]:
    body = text[object_open + 1 : object_close]
    matches = list(re.finditer(r'"' + re.escape(key) + r'"\s*:\s*\{', body))
    if len(matches) != 1:
        raise ValueError(f"expected one JSON object member {key!r}, found {len(matches)}")
    open_index = object_open + 1 + matches[0].end() - 1
    return open_index, object_end(text, open_index)


def validated_report(path: Path) -> dict:
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("schema") != EXPECTED_SCHEMA:
        raise ValueError(f"unexpected report schema: {report.get('schema')!r}")
    if report.get("law") != EXPECTED_LAW:
        raise ValueError(f"report law is not the current D11g law: {report.get('law')!r}")
    values = report.get("rounded_4_significant_digits")
    sources = report.get("provenance")
    if not isinstance(values, dict) or not isinstance(sources, dict):
        raise ValueError("report must contain rounded values and provenance objects")
    for key in RATE_KEYS:
        value = values.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise ValueError(f"report has no finite rounded value for {key}")
        if not isinstance(sources.get(key), str) or not sources[key]:
            raise ValueError(f"report has no source provenance for {key}")
    about_arp = report.get("about_arp")
    if not isinstance(about_arp, dict):
        raise ValueError("report has no about_arp derivative object")
    for key in RATE_KEYS:
        value = about_arp.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise ValueError(f"report has no finite about-ARP derivative for {key}")
        rounded = float(format(float(value), ".4g"))
        if float(values[key]) != rounded:
            raise ValueError(f"report rounded value for {key} does not match four-significant-digit about_arp output")
    condition = report.get("condition")
    if not isinstance(condition, dict):
        raise ValueError("report has no condition object")
    expected_conditions = {
        "speed_mps": 15.0,
        "density_kg_m3": 1.225,
        "central_difference_step_rad_s": 0.05,
        "controls": "neutral",
        "wake": "settled instantaneous Aero.wing_wake_velocity output; no ground effect",
    }
    for key, expected in expected_conditions.items():
        actual = condition.get(key)
        if isinstance(expected, (int, float)):
            if isinstance(actual, bool) or not isinstance(actual, (int, float)) or float(actual) != expected:
                raise ValueError(f"report condition {key} is not the expected D11g setting")
        elif actual != expected:
            raise ValueError(f"report condition {key} is not the expected D11g setting")
    derivation_identity = report.get("derivation_identity")
    if not isinstance(derivation_identity, dict):
        raise ValueError("report has no derivation_identity")
    normalized_input = derivation_identity.get("normalized_input")
    if not isinstance(normalized_input, dict) or normalized_input.get("scheme") != FINGERPRINT_SCHEME:
        raise ValueError("report has no supported normalized input fingerprint")
    if normalized_input.get("excluded_leaves") != list(EXCLUDED_OUTPUT_LEAVES):
        raise ValueError("report normalized input fingerprint excludes an unexpected set of leaves")
    if not isinstance(normalized_input.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", normalized_input["sha256"]):
        raise ValueError("report normalized input fingerprint is not a SHA-256 hex digest")
    if derivation_identity.get("solver_source_scheme") != SOURCE_IDENTITY_SCHEME:
        raise ValueError("report solver source identity scheme is unsupported")
    solver_sources = derivation_identity.get("solver_sources")
    if not isinstance(solver_sources, list) or len(solver_sources) != len(SOLVER_SOURCE_PATHS):
        raise ValueError("report solver source identity has an unexpected file inventory")
    for expected_path, entry in zip(SOLVER_SOURCE_PATHS, solver_sources, strict=True):
        if not isinstance(entry, dict) or entry.get("path") != expected_path:
            raise ValueError("report solver source identity has an unexpected file inventory/order")
        if not isinstance(entry.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise ValueError(f"report solver source hash is invalid for {expected_path}")
        current_path = ROOT / expected_path
        try:
            current_hash = hashlib.sha256(current_path.read_bytes()).hexdigest()
        except OSError as exc:
            raise ValueError(f"cannot read solver source {expected_path}: {exc}") from exc
        if current_hash != entry["sha256"]:
            raise ValueError(f"solver source changed since report generation: {expected_path}")
    return report


def normalized_input_fingerprint(text: str) -> str:
    normalized = text
    for key in RATE_KEYS:
        root_open = normalized.find("{")
        if root_open < 0:
            raise ValueError("target JSON has no root object")
        root_close = object_end(normalized, root_open)
        aero_open, aero_close = member_object_span(normalized, root_open, root_close, "aero")
        coefficients_open, coefficients_close = member_object_span(normalized, aero_open, aero_close, "coefficients")
        record_open, record_close = member_object_span(normalized, coefficients_open, coefficients_close, key)
        record_text = normalized[record_open : record_close + 1]
        value_pattern = re.compile(r'("value"\s*:\s*)(-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)')
        source_pattern = re.compile(r'("source"\s*:\s*)("(?:\\.|[^"\\])*")')
        record_text, value_count = value_pattern.subn(r'\1"__D11G_OUTPUT_VALUE__"', record_text, count=1)
        record_text, source_count = source_pattern.subn(r'\1"__D11G_OUTPUT_SOURCE__"', record_text, count=1)
        if value_count != 1 or source_count != 1:
            raise ValueError(f"expected one value/source token in aero.coefficients.{key}")
        normalized = normalized[:record_open] + record_text + normalized[record_close + 1 :]
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def verify_target_identity(data: dict, text: str, report: dict) -> None:
    if data.get("id") != report.get("aircraft_id") or data.get("id") != "jensen-das-ugly-stik-60":
        raise ValueError("report aircraft id does not match the Jensen Ugly Stik 60 target")
    expected = report["derivation_identity"]["normalized_input"]["sha256"]
    actual = normalized_input_fingerprint(text)
    if actual != expected:
        raise ValueError(f"normalized derivation input differs from report (expected {expected}, got {actual})")


def load_target(data: dict) -> dict:
    if data.get("id") != "jensen-das-ugly-stik-60":
        raise ValueError("target is not the Jensen Ugly Stik 60")
    try:
        records = data["aero"]["coefficients"]
        selected = {key: records[key] for key in RATE_KEYS}
    except (KeyError, TypeError) as exc:
        raise ValueError("target lacks the three D11g coefficient records") from exc
    for key, record in selected.items():
        if record.get("unit") != "1/rad" or record.get("kind") != "derived":
            raise ValueError(f"{key} must remain a derived 1/rad coefficient")
        value = record.get("value")
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise ValueError(f"{key} must keep a finite numeric value")
    return selected


def leaf_differences(selected: dict, report: dict) -> list[str]:
    differences: list[str] = []
    values = report["rounded_4_significant_digits"]
    sources = report["provenance"]
    for key in RATE_KEYS:
        record = selected[key]
        if float(record.get("value", math.nan)) != float(values[key]):
            differences.append(f"aero.coefficients.{key}.value: {record.get('value')!r} -> {values[key]!r}")
        if record.get("source") != sources[key]:
            differences.append(f"aero.coefficients.{key}.source: stale -> current-law provenance")
    return differences


def replace_target_leaves(text: str, report: dict) -> tuple[str, list[str]]:
    data = json.loads(text)
    original = copy.deepcopy(data)
    selected = load_target(data)
    aero_match = re.search(r'"aero"\s*:\s*\{', text)
    if aero_match is None:
        raise ValueError("cannot locate the aero object in source bytes")
    changed: list[str] = []
    values = report["rounded_4_significant_digits"]
    sources = report["provenance"]
    for key in RATE_KEYS:
        # Re-find the nesting spans after each replacement; source strings have different lengths.
        aero_match = re.search(r'"aero"\s*:\s*\{', text)
        if aero_match is None:
            raise ValueError("cannot relocate the aero object after a prior replacement")
        aero_open = aero_match.end() - 1
        aero_close = object_end(text, aero_open)
        coefficients_open, coefficients_close = member_object_span(text, aero_open, aero_close, "coefficients")
        record_open, record_close = member_object_span(text, coefficients_open, coefficients_close, key)
        record_text = text[record_open : record_close + 1]
        value_pattern = re.compile(r'("value"\s*:\s*)(-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)')
        source_pattern = re.compile(r'("source"\s*:\s*)"(?:\\.|[^"\\])*"')
        value_matches = list(value_pattern.finditer(record_text))
        source_matches = list(source_pattern.finditer(record_text))
        if len(value_matches) != 1 or len(source_matches) != 1:
            raise ValueError(f"expected one value and source leaf in {key}")
        new_value = json.dumps(float(values[key]), allow_nan=False, separators=(",", ":"))
        new_source = json.dumps(sources[key], ensure_ascii=False)
        new_record, value_count = value_pattern.subn(lambda match: match.group(1) + new_value, record_text, count=1)
        new_record, source_count = source_pattern.subn(lambda match: match.group(1) + new_source, new_record, count=1)
        if value_count != 1 or source_count != 1:
            raise ValueError(f"failed to replace only the requested {key} leaves")
        if new_record != record_text:
            changed.append(key)
            text = text[:record_open] + new_record + text[record_close + 1 :]
    updated = json.loads(text)
    updated_selected = load_target(updated)
    differences = leaf_differences(updated_selected, report)
    if differences:
        raise ValueError("update did not produce requested leaves: " + "; ".join(differences))
    for key in RATE_KEYS:
        for leaf in ("value", "source"):
            del original["aero"]["coefficients"][key][leaf]
            del updated["aero"]["coefficients"][key][leaf]
    if updated != original:
        raise ValueError("update changed a JSON leaf outside the three requested value/source pairs")
    return text, changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True, help="machine JSON from the D11g GDScript generator")
    parser.add_argument("--aircraft", type=Path, default=DEFAULT_AIRCRAFT, help="target Stik aircraft JSON")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="fail if any of the three value/source leaves differ")
    mode.add_argument("--write", action="store_true", help="write only the three value/source leaf pairs")
    args = parser.parse_args()
    try:
        report = validated_report(args.report)
        raw_bytes = args.aircraft.read_bytes()
        text = raw_bytes.decode("utf-8")
        data = json.loads(text)
        selected = load_target(data)
        verify_target_identity(data, text, report)
        differences = leaf_differences(selected, report)
        if args.check:
            if differences:
                print("stale D11g data:")
                for difference in differences:
                    print("  " + difference)
                return 1
            print("D11g values and provenance match the current-law report.")
            return 0
        updated_text, changed = replace_target_leaves(text, report)
        updated_bytes = updated_text.encode("utf-8")
        if updated_bytes != raw_bytes:
            args.aircraft.write_bytes(updated_bytes)
        print("updated leaves: " + (", ".join(changed) if changed else "already current"))
        print(f"bytes: {len(raw_bytes)} -> {len(updated_bytes)}; only value/source leaves are eligible")
        return 0
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
