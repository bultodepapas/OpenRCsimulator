#!/usr/bin/env python3
"""Build a narrowly scoped source-editor Mac default marker from retained proofs.

This is an artifact consistency check, not a signature, release approval, or
proof that the technical-circuit captures establish performance on every row.
No marker is written until every required input has been revalidated.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FORMAT = "openrc-macos-native-default v1"
SCOPE = "source-editor-macos-arm64"
SELECTION_FIELDS = ("aircraft", "battery", "start", "weather", "soft_hull", "trim_profile", "start_sha256")
# The fleet's ordinary "trim" case sets Session.START_AIRBORNE.
STARTS = {"trim": "airborne", "airborne_half_power": "airborne_half_power",
          "runway": "runway", "hand_launch": "hand_launch"}
MODEL = "MacBookAir10,1"
CPU = "Apple M1"


class AdmissionError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AdmissionError(message)


def module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"cannot load {path}")
    loaded = importlib.util.module_from_spec(spec)
    # native_summary also imports its sibling session_baseline when run as a
    # script; make that same sibling resolution available to this loader.
    sys.path.insert(0, str(path.parent))
    try:
        spec.loader.exec_module(loaded)
    finally:
        sys.path.pop(0)
    return loaded


def sha(path: Path) -> str:
    require(not path.is_symlink() and path.is_file(), f"missing or redirected file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> tuple[dict[str, Any], str]:
    before = sha(path)
    # A duplicate key can otherwise change the meaning seen by another parser.
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON key in {path}: {key}")
            result[key] = value
        return result
    def invalid_constant(value: str) -> None:
        raise AdmissionError(f"non-finite JSON value in {path}: {value}")
    with path.open("r", encoding="utf-8") as stream:
        value = json.load(stream, object_pairs_hook=unique, parse_constant=invalid_constant)
    require(isinstance(value, dict) and sha(path) == before, f"invalid or changing JSON: {path}")
    return value, before


def _sysctl(key: str) -> str:
    result = subprocess.run(["/usr/sbin/sysctl", "-n", key], check=True, capture_output=True,
                            text=True, timeout=10)
    return result.stdout.strip()


def validate_preflight(preflight: dict[str, Any], guard: dict[str, Any]) -> None:
    host, engine = preflight.get("host"), preflight.get("engine")
    require(preflight.get("format") == "openrc-macos-preflight-v1" and isinstance(host, dict)
            and isinstance(engine, dict), "invalid Mac preflight")
    receipt = guard["receipt"]
    require(host.get("model_identifier") == MODEL and host.get("cpu") == CPU
            and host.get("hardware_arm64") is True and host.get("python_process_native_arm64") is True
            and host.get("python_process_rosetta") is False
            and host.get("os_version") == receipt["runtime_os_version"]
            and host.get("os_build") == receipt["runtime_os_build"]
            and isinstance(engine.get("identity"), dict)
            and engine["identity"].get("sha256") == guard["engine_sha256"]
            and engine.get("identity_stable_across_version_checks") is True,
            "preflight does not match the qualified host and engine")
    require(_sysctl("hw.model") == MODEL and _sysctl("machdep.cpu.brand_string") == CPU,
            "current host differs from the preflight hardware")


def selection_rows(rows: Any) -> list[dict[str, Any]]:
    require(isinstance(rows, list), "fleet rows are missing")
    selected: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for row in rows:
        require(isinstance(row, dict), "malformed fleet row")
        if row.get("status") != "verified-flight":
            continue
        require(row.get("vehicle") == "fixed-wing" and row.get("case") in STARTS
                and all(isinstance(row.get(key), str) and row[key] for key in ("aircraft", "battery", "weather"))
                and type(row.get("soft_hull")) is bool and isinstance(row.get("start_sha256"), str)
                and re.fullmatch(r"[0-9a-f]{64}", row["start_sha256"]) is not None
                and type(row.get("automatic_domain_guarded")) is bool, "invalid verified selection")
        if not row["automatic_domain_guarded"]:
            continue
        item = {"aircraft": row["aircraft"], "battery": row["battery"], "start": STARTS[row["case"]],
                "weather": row["weather"], "soft_hull": row["soft_hull"], "trim_profile": "production",
                "start_sha256": row["start_sha256"]}
        key = tuple(item[field] for field in SELECTION_FIELDS if field != "start_sha256")
        require(key not in seen, "duplicate qualified selection")
        seen.add(key)
        selected.append(item)
    require(0 < len(selected) <= 1428, "no bounded independently verified production selections")
    return sorted(selected, key=lambda row: tuple(row[field] for field in SELECTION_FIELDS))


def validate_fleet(fleet: Any, campaign_path: Path, context: dict[str, str], guard: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    campaign, campaign_sha = read_json(campaign_path)
    require(campaign.get("format") == "openrc-nk3-fleet-campaign-macos-experimental v1"
            and campaign.get("trim_profile") == "production", "campaign is not a production-trim Mac fleet")
    expected_guard = campaign.get("guard")
    require(isinstance(expected_guard, dict)
            and {key: value for key, value in expected_guard.items() if key != "base_oracle_boundary"} == guard,
            "campaign host, install, sources, project or harness differ")
    manifest_path = campaign_path.parent / "manifest.json"
    manifest, manifest_sha = read_json(manifest_path)
    require(manifest_sha == campaign.get("manifest_sha256")
            and sha(campaign_path.parent / "manifest.gd") == campaign.get("manifest_script_sha256"),
            "campaign manifest changed")
    selected = campaign.get("selected_aircraft")
    records = campaign.get("reports")
    failures = campaign.get("shard_errors")
    require(isinstance(selected, list) and isinstance(records, dict) and isinstance(failures, dict),
            "campaign shard inventory is malformed")
    tool_root = Path(context["tool_root"]).resolve()
    reports: dict[str, dict[str, Any]] = {}
    paths: dict[str, Path] = {}
    hashes: dict[str, str] = {}
    for name, record in records.items():
        require(isinstance(name, str) and isinstance(record, dict)
                and isinstance(record.get("path"), str), "invalid shard citation")
        raw_path = Path(record["path"])
        require(not raw_path.is_symlink(), "redirected shard report")
        path = raw_path.resolve()
        require(path.is_relative_to(tool_root) and path.name.startswith("fleet-") and path.suffix == ".json",
                "shard report is outside the selected evidence root")
        reports[name], hashes[name] = read_json(path)
        require(hashes[name] == record.get("sha256"), "shard report changed")
        paths[name] = path
    original_errors = {name: error for name, error in failures.items() if name not in reports}
    checked = fleet.validate_macos_reports(manifest, reports, paths, selected, original_errors, guard,
                                           campaign.get("warmup"), campaign.get("samples"))
    require(all(campaign.get(key) == value for key, value in checked.items()), "fleet reduction differs from campaign")
    require(expected_guard.get("base_oracle_boundary") == checked["base_oracle_boundary"],
            "campaign base oracle identity changed")
    require(sha(campaign_path) == campaign_sha and sha(manifest_path) == manifest_sha
            and all(sha(paths[name]) == digest for name, digest in hashes.items()), "fleet evidence changed during validation")
    selections = selection_rows(checked["rows"])
    provenance = {"campaign": str(campaign_path), "campaign_sha256": campaign_sha,
                  "manifest_sha256": manifest_sha, "verified_rows": checked["verified_flight_rows"],
                  "open_rows": checked["open_rows"], "admitted_guarded_rows": len(selections)}
    return selections, provenance


def _live_install(run: dict[str, Any]) -> dict[str, Any]:
    health = run["benchmark_health"]
    return health["scenario"]["backend_proof"]["installation_before"]


def live_sources(project: Path) -> dict[str, str]:
    """Mirror sustained_flight.gd's visible source-tree inventory."""
    require(not project.is_symlink() and project.is_dir(), "live project is missing or redirected")
    sources: dict[str, str] = {}
    pending = [project]
    while pending:
        directory = pending.pop()
        for path in directory.iterdir():
            if path.name.startswith("."):
                continue
            require(not path.is_symlink(), f"linked live source: {path}")
            if path.is_dir():
                pending.append(path)
            else:
                require(path.is_file(), f"non-regular live source: {path}")
                sources["res://" + path.relative_to(project).as_posix()] = sha(path)
                require(len(sources) <= 8190, "live source inventory exceeds its capture limit")
    for name in ("sustained_input.gd", "sustained_flight.gd"):
        relative = "research/performance/" + name
        sources[relative] = sha(ROOT / relative)
    return sources


def validate_live(summary: Any, pairs: list[tuple[Path, Path]], guard: dict[str, Any], minimum_sample: int,
                  seen: set[str], work: Path, retained: list[tuple[Path, dict[str, Any]]],
                  sources: dict[str, str]) -> list[dict[str, Any]]:
    policy = dict(summary.DEFAULT_POLICY)
    policy.update(minimum_warmup_s=30.0, minimum_sample_s=float(minimum_sample))
    result: list[dict[str, Any]] = []
    identity = guard["receipt"]
    for index, (reference, native) in enumerate(pairs):
        require(not reference.is_symlink() and not native.is_symlink(), "redirected live report")
        reference, native = reference.resolve(), native.resolve()
        before = (sha(reference), sha(native))
        comparison, code = summary.compare_circuit(reference, native, work / f"{minimum_sample}-{index}.json", policy)
        require(code == 0 and comparison.get("complete") is True, "live circuit comparison failed")
        ref_run, nat_run = comparison["reference"], comparison["native"]
        for run in (ref_run, nat_run):
            capture = run.get("capture_id")
            require(isinstance(capture, str) and bool(capture) and capture not in seen,
                    "live capture is missing or reused")
            seen.add(capture)
            health = run["benchmark_health"]
            scenario = health.get("scenario")
            require(isinstance(scenario, dict) and scenario.get("selected_trim_throttle") == 0.5
                    and isinstance(scenario.get("solved_start_sha256"), str)
                    and re.fullmatch(r"[0-9a-f]{64}", scenario["solved_start_sha256"]) is not None,
                    "live capture lacks the 0.5 production trim selection")
            proof = scenario.get("backend_proof")
            require(isinstance(proof, dict) and proof.get("backend_domain_guard") is (run is nat_run),
                    "live capture lacks the validated production domain guard")
            health_name = health.get("receipt")
            require(isinstance(health_name, str) and bool(health_name)
                    and "/" not in health_name and "\\" not in health_name
                    and health_name not in (".", "..") and Path(health_name).name == health_name,
                    "invalid live health receipt path")
            health_data, health_sha = read_json((reference if run is ref_run else native).parent / health_name)
            require(health_sha == health.get("receipt_sha256") and health_data.get("source_sha256") == sources,
                    "live capture does not match the current complete application and benchmark source trees")
            installation = _live_install(run)
            installed_identity = installation.get("identity")
            require(isinstance(installed_identity, dict)
                    and installation.get("receipt_sha256") == guard["receipt_sha256"]
                    and installation.get("descriptor_sha256") == guard["descriptor_sha256"]
                    and installation.get("engine_sha256") == guard["engine_sha256"]
                    and installation.get("native_source_sha256") == identity["source_sha256"]
                    and installed_identity.get("binary_sha256") == guard["binary_sha256"]
                    and installed_identity.get("source_sha256") == identity["source_sha256"]
                    and installed_identity.get("lock_sha256") == identity["lock_sha256"],
                    "live capture is not bound to the selected native installation")
        require(before == (sha(reference), sha(native)), "live report changed during comparison")
        retained.extend(((reference, ref_run), (native, nat_run)))
        result.append({"reference": str(reference), "reference_sha256": before[0],
                       "native": str(native), "native_sha256": before[1],
                       "reference_capture_id": ref_run["capture_id"], "native_capture_id": nat_run["capture_id"],
                       "matched_windows": len(comparison["matched_windows"])})
    return result


def generate(args: argparse.Namespace) -> dict[str, Any]:
    require(len(args.short_pair) == 5 and len(args.long_pair) == 3,
            "exactly five short pairs and three 30-minute pairs are required")
    fleet = module("nk3_promotion_fleet", HERE / "fleet_campaign.py")
    package = module("nk3_promotion_package", HERE / "package.py")
    summary = module("nk3_promotion_summary", ROOT / "research/performance/native_summary.py")
    project, godot = args.project.expanduser().resolve(), args.godot.expanduser().resolve()
    tool_root = args.tool_root.expanduser().resolve()
    qualification_root = args.qualification_root.expanduser().resolve()
    context = {"project": str(project), "godot": str(godot), "tool_root": str(tool_root),
               "qualification_root": str(qualification_root), "trim_profile": "production"}
    installed = package.verified_mac_install(qualification_root, godot)
    guard = fleet.snapshot(context)
    canonical_receipt = ROOT / "app/native/kernel/build-receipt-macos.json"
    require(installed["platforms"]["macos"] == guard["receipt"]
            and sha(canonical_receipt) == guard["receipt_sha256"],
            "campaign project does not contain the verified canonical installation")
    preflight_path = args.preflight.expanduser().absolute()
    preflight, preflight_sha = read_json(preflight_path)
    validate_preflight(preflight, guard)
    domain_path = ROOT / "app/sim/native_macos_domain.gd"
    domain_sha = sha(domain_path)
    project_domain = project / "sim/native_macos_domain.gd"
    require(sha(project_domain) == domain_sha, "campaign and current domain modules differ")
    campaign_path = args.campaign.expanduser().absolute()
    rows, campaign = validate_fleet(fleet, campaign_path, context, guard)
    seen: set[str] = set()
    retained: list[tuple[Path, dict[str, Any]]] = []
    sources = live_sources(project)
    with tempfile.TemporaryDirectory(prefix="macos-promotion-", dir=ROOT / "tmp") as directory:
        work = Path(directory)
        short = validate_live(summary, args.short_pair, guard, 120, seen, work, retained, sources)
        long = validate_live(summary, args.long_pair, guard, 1800, seen, work, retained, sources)
    final_rows, final_campaign = validate_fleet(fleet, campaign_path, context, guard)
    require(fleet.snapshot(context) == guard and package.verified_mac_install(qualification_root, godot) == installed
            and sha(preflight_path) == preflight_sha and sha(domain_path) == domain_sha
            and sha(project_domain) == domain_sha and sha(canonical_receipt) == guard["receipt_sha256"]
            and final_rows == rows and final_campaign == campaign
            and sha(campaign_path) == campaign["campaign_sha256"]
            and live_sources(project) == sources
            and all(summary._checked_evidence_unchanged(path, run) for path, run in retained),
            "qualification inputs changed while generating the marker")
    receipt = guard["receipt"]
    return {"format": FORMAT, "scope": SCOPE, "receipt_sha256": guard["receipt_sha256"],
            "binary_sha256": guard["binary_sha256"], "source_sha256": receipt["source_sha256"],
            "lock_sha256": receipt["lock_sha256"], "domain_sha256": domain_sha,
            "engine_sha256": guard["engine_sha256"], "os_version": receipt["runtime_os_version"],
            "os_build": receipt["runtime_os_build"], "hardware_model": MODEL, "cpu": CPU,
            "allowed_selections": rows,
            "evidence": {"preflight": str(preflight_path), "preflight_sha256": preflight_sha,
                         "fleet": campaign, "short_pairs": short, "long_pairs": long,
                         "live_scope": "Matched technical circuits; not per-selection performance or physical validation.",
                         "host_scope": "Preflight describes this host; capture reports do not attest its physical model."}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("project", "godot", "tool-root", "qualification-root", "preflight", "campaign", "out"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--short-pair", nargs=2, type=Path, action="append", default=[], metavar=("REFERENCE", "NATIVE"))
    parser.add_argument("--long-pair", nargs=2, type=Path, action="append", default=[], metavar=("REFERENCE", "NATIVE"))
    args = parser.parse_args()
    out = args.out.expanduser().absolute()
    try:
        require(not out.exists() and not out.is_symlink(), "output already exists")
        resolved = out.resolve()
        temp_root = (ROOT / "tmp").resolve()
        require(resolved.is_relative_to(temp_root) and resolved != temp_root and out.parent.is_dir(),
                "new output must be inside this checkout's tmp/ directory")
        for protected in (args.project, args.tool_root, args.qualification_root, args.campaign.parent):
            require(not resolved.is_relative_to(protected.expanduser().resolve()),
                    "output must be outside the project, campaign and build evidence roots")
        marker = generate(args)
        with out.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(marker, stream, sort_keys=True, indent=2, allow_nan=False)
            stream.write("\n")
        print(f"Wrote {len(marker['allowed_selections'])} source-editor selections: {out}")
        return 0
    except (AdmissionError, OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        print(f"Mac default admission refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
