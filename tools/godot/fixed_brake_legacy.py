"""GP-12 strict historical golden and same-host fixed-brake regression gate.

The reconstructed R3 owner must first reproduce every original OS golden under
the historical engine with the original CRLF fuel registry. Then the reference
runs under the current engine with the two pinned candidate input identities and
a strictly derived glow-law identity overlay. Outputs are not normalized.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

from get_historical_godot import (
    ENGINE_LINUX_SHA512, ENGINE_WINDOWS_CONSOLE_SHA512, ENGINE_WINDOWS_SHA512,
    HISTORICAL_VERSION, ensure_historical_godot,
)

ROOT = Path(__file__).resolve().parents[2]
CONSTRUCTION = ROOT / "docs/research/ground-physics/GP-12/evidence/fixed-brake-input/construction"
CAPTURE = ROOT / "docs/research/release-readiness/PT1-v0.1.9/capture_fixed_brake_values.gd"
FIELDS = ("checkpoint", "metadata", "trace_csv", "after_three_ticks")
IDS = {"gp-extra-300s-60", "jensen-das-ugly-stik-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"}
FUEL_LF = "6f4908ba7ea67eac4f5c01580ce88aae95355b76852586ee9ef299ba03f7e043"
FUEL_CRLF = "cae59374afdc9345a05774342c9c9be1fdec8573f6f75c97eed8aae6257d5df1"
AVANTI_OLD = "3ebd08c2869207e869c3c127da6f0db7be1409a32ab0903b17d3211d0b2807b1"
AVANTI_CURRENT = "048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd"
SESSION_OLD = "2bc02a0f52601a60193c4724c597f47d57b11f5fb0a7a851095fd08c5f29a864"
TRACE_OLD = "1c529262fb33b7db3137f9cba064be0e32a6d9c7620ae224cc06500a5a05a62e"
TRACE_LAW_OVERLAY = "9e52848c5c6831dab8993a6b638ab953f5bf680eb22059ec3f328dd1717ff65b"
GLOW_FLIGHT_OLD_LF = "37b5e2d58ffb3615a8aabcaceb26db4408835135723200d07fb5f6b4dd8b60a0"
GLOW_FLIGHT_LAW_OVERLAY_LF = "28262e121121cb50b4db3fef22304f5139a9d166d47795c5b80a83d9fd0ec0c6"
GLOW_FLIGHT_PATH = "physics/glow/flight.gd"
TRACE_PATH = "sim/trace.gd"
GLOW_LAW_OLD = b"glow-mean-cycle-carburettor-v4"
GLOW_LAW_CURRENT = b"glow-mean-cycle-segmented-firing-v6"
REFERENCE_LAW_DECLARATIONS = {
    GLOW_FLIGHT_PATH: (b'const LAW := "' + GLOW_LAW_OLD + b'"',
                       b'const LAW := "' + GLOW_LAW_CURRENT + b'"'),
    TRACE_PATH: (b'const GLOW_LAW_V4: String = "' + GLOW_LAW_OLD + b'"',
                 b'const GLOW_LAW_V4: String = "' + GLOW_LAW_CURRENT + b'"'),
}
CARB_R3 = "16d8065ae5ce49d1d79d8d6f14ea3f7e613983587b5b00eeb0f357e536505505"
FROZEN_FIXTURE = "61b27a375e3d29808b2f84a0e69dfaa4057a6b0c58b3e1abe8a1c62bd31dc9bd"
CAPTURE_SOURCE = "ea3918c0661db3a497d1149c057875890f7b44af1d462f8d5172800ecd33c85b"
RECONSTRUCTOR_SOURCE = "48b46620a7ed91cfc8b3f4c3dd98f24d16eca8917b81141270e41be769fc9d50"
SOURCE_PINS = "c186c5432377e62ea3045281c20fc4c8aaacab3063fd3bbda75ef96f18410f55"
REFERENCE_PROJECT = "5f54ed734e87ede917879857c6cbc4a86787d0a1484e448b2c1714b3b1e6d11e"
CURRENT_LINUX_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
CURRENT_WINDOWS_CONSOLE_SHA512 = "dd05e00ff13faac6b863aa1e4c51599cfaa973c9b8d2e31158d717b499a4ee0b08d46661c0c91215dcce77ce1edfb33595b8af476b2862a47465ec27545962ea"
CURRENT_WINDOWS_SHA512 = "e83c615fb181c6e1c83f204801e8c73a9340ea500d0da3d7e598f6c4213051de5df8073041c27790838b9e4eff4770c483d7dbb75545da7ad4382c53e23f6a55"
CURRENT_VERSION = "4.8.beta2.official.cafc17a19"
CURRENT_CAPTURE_ENGINE = "4.8-beta2 (official)"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def pin_paths() -> dict[str, str]:
    pins = json.loads((CONSTRUCTION / "loaded-source-pins.json").read_text(encoding="utf-8"))
    prefix = "C:\\DEVELOPMENT\\OpenRCsimulator\\"
    paths = {}
    for name, digest in list(pins["scripts"].items()) + list(pins["data"].items()):
        rel = name[len(prefix):].replace("\\", "/") if name.startswith(prefix) else name
        if rel.startswith("app/"):
            paths[rel.removeprefix("app/")] = digest
    require(len(paths) == 400, "candidate source list differs")
    return paths


def candidate_manifest(project: Path) -> dict[str, str]:
    # Candidate source paths evolve independently of the frozen historical tree.
    paths = {str(path.relative_to(project)).replace("\\", "/") for path in project.rglob("*.gd")
             if ".godot" not in path.relative_to(project).parts}
    require(paths and (project / "data").is_dir(), "candidate sources or data are missing")
    paths.update(str(path.relative_to(project)).replace("\\", "/") for path in (project / "data").rglob("*") if path.is_file())
    paths.update({"data/fuels/openrc-fuel-registry.json", "project.godot",
                  "tests/fixtures/fixed_brake_legacy_outputs.json", "tests/test_fixed_gear_brake_input.gd"})
    manifest = {path: file_sha(project / path) for path in sorted(paths)}
    manifest["capture_script"] = file_sha(CAPTURE)
    manifest["gate_script"] = file_sha(Path(__file__))
    manifest["historical_engine_getter"] = file_sha(ROOT / "tools/godot/get_historical_godot.py")
    manifest["checked_runner"] = file_sha(ROOT / "tools/godot/run_checked.py")
    manifest["reconstructor"] = file_sha(CONSTRUCTION / "reconstruct_legacy_reference.py")
    manifest["historical_pins"] = file_sha(CONSTRUCTION / "loaded-source-pins.json")
    return manifest


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_input_bytes(fuel: bytes, avanti: bytes) -> None:
    require(sha(fuel) in {FUEL_LF, FUEL_CRLF}, "candidate fuel registry is not a pinned identity")
    require(sha(avanti) in {AVANTI_OLD, AVANTI_CURRENT}, "candidate Avanti is not a pinned identity")


def check_candidate_glow_law(data: bytes) -> None:
    declarations = re.findall(rb"(?m)^[ \t]*const[ \t]+LAW[ \t]*(?::[^=\r\n]*)?=[^\r\n]*", data)
    require(declarations == [REFERENCE_LAW_DECLARATIONS[GLOW_FLIGHT_PATH][1]],
            "candidate glow LAW declaration differs from the supported v6 identity")


def replace_once(data: bytes, before: bytes, after: bytes, path: str) -> bytes:
    require(data.count(before) == 1, "reference glow-law declaration missing or duplicated: " + path)
    return data.replace(before, after, 1)


def reference_law_overlay(project: Path) -> dict[str, bytes]:
    """Derive the only allowed edits from independently pinned original bytes."""
    pins = pin_paths()
    require(set(REFERENCE_LAW_DECLARATIONS).issubset(pins), "reference glow-law source pins missing")
    overlay = {}
    for path, (before, after) in REFERENCE_LAW_DECLARATIONS.items():
        original = (project / path).read_bytes()
        lf = original.replace(b"\r\n", b"\n")
        require(pins[path] in {sha(original), sha(lf), sha(lf.replace(b"\n", b"\r\n"))},
                "reference input changed before glow-law overlay: " + path)
        patched = replace_once(original, before, after, path)
        if path == GLOW_FLIGHT_PATH:
            require(sha(lf) == GLOW_FLIGHT_OLD_LF and sha(patched.replace(b"\r\n", b"\n")) == GLOW_FLIGHT_LAW_OVERLAY_LF,
                    "reference glow flight overlay identity differs")
        else:
            require(sha(original) == TRACE_OLD and sha(patched) == TRACE_LAW_OVERLAY,
                    "reference trace overlay identity differs")
        overlay[path] = patched
    return overlay


def check_reference_inputs(project: Path, fuel: bytes, avanti: bytes,
                           law_overlay: dict[str, bytes] | None = None) -> None:
    require((project / "data/fuels/openrc-fuel-registry.json").read_bytes() == fuel, "reference fuel changed")
    require((project / "data/aircraft/sebart_avanti_s_a200.json").read_bytes() == avanti, "reference Avanti changed")
    require(sha((project / "project.godot").read_bytes().replace(b"\r\n", b"\n")) == REFERENCE_PROJECT,
            "reference project settings changed")
    pins = pin_paths()
    if law_overlay is not None:
        require(set(law_overlay) == set(REFERENCE_LAW_DECLARATIONS) and set(law_overlay).issubset(pins),
                "reference glow-law overlay set differs")
    for path, digest in pins.items():
        data = (project / path).read_bytes()
        if law_overlay is not None and path in law_overlay:
            require(data == law_overlay[path], "reference glow-law overlay changed: " + path)
            continue
        if path == "data/aircraft/sebart_avanti_s_a200.json":
            continue
        if path == "physics/glow/carburetor.gd":
            require(sha(data) == CARB_R3, "reference R3 carburetor changed")
            continue
        lf = data.replace(b"\r\n", b"\n")
        require(digest in {sha(data), sha(lf), sha(lf.replace(b"\n", b"\r\n"))}, "reference input changed: " + path)


def load_capture(path: Path, fixture: dict, reference: bool, engine: str,
                 reference_trace_sha: str = TRACE_OLD) -> dict:
    capture = json.loads(path.read_text(encoding="utf-8"))
    require(capture.get("format") == "openrc-fixed-brake-legacy-capture v1", "invalid capture format")
    require(capture.get("engine") == engine and capture.get("physics_hz") == fixture["physics_hz"], "engine or physics rate differs")
    os_name = capture.get("os")
    require(os_name in fixture["os_captures"], "no frozen reference for this OS")
    require(set(capture.get("outputs", {})) == IDS, "capture aircraft set differs")
    for aircraft, row in capture["outputs"].items():
        require(all(isinstance(row.get(key), str) and re.fullmatch(r"[0-9a-f]{64}", row[key]) for key in FIELDS),
                "missing digest for " + aircraft)
        require(isinstance(row.get("checkpoint_value"), dict) and isinstance(row.get("metadata_value"), dict)
                and isinstance(row.get("csv_value"), str) and bool(row["csv_value"]), "missing full values for " + aircraft)
    if reference:
        require(capture.get("session_sha256") == SESSION_OLD and capture.get("trace_sha256") == reference_trace_sha,
                "historical owner identity differs")
    return capture


def check_goldens(capture: dict, fixture: dict) -> None:
    os_name = capture["os"]
    require(set(fixture["outputs"]) == IDS, "fixture aircraft set differs")
    for aircraft in sorted(IDS):
        expected = dict(fixture["outputs"][aircraft])
        expected.update(fixture.get("outputs_by_os", {}).get(os_name, {}).get(aircraft, {}))
        for key in FIELDS:
            require(capture["outputs"][aircraft][key] == expected.get(key), "historical golden mismatch: " + aircraft + " " + key)


def check_comparison(reference: dict, candidate: dict) -> None:
    require(reference["os"] == candidate["os"] and reference["engine"] == candidate["engine"]
            and reference["physics_hz"] == candidate["physics_hz"], "capture host or engine differs")
    for aircraft in sorted(IDS):
        for key in FIELDS:
            require(reference["outputs"][aircraft][key] == candidate["outputs"][aircraft][key],
                    "candidate differs: " + aircraft + " " + key)
        for key in ("checkpoint_value", "metadata_value", "csv_value"):
            require(reference["outputs"][aircraft][key] == candidate["outputs"][aircraft][key],
                    "candidate full value differs: " + aircraft + " " + key)


def checked(godot: Path, project: Path, out: Path, label: str, args: list[str], timeout: int = 180,
            extra_env: dict[str, str] | None = None, required_text: tuple[str, ...] = ()) -> None:
    env = os.environ.copy()
    env.update(extra_env or {})
    command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"), "--label", label,
               "--timeout", str(timeout), "--out-dir", str(out)]
    for marker in required_text:
        command += ["--require-text", marker]
    command += ["--", str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy", *args]
    subprocess.run(command, check=True, env=env)


def check_engine(godot: Path, historical: bool) -> dict[str, str]:
    def digest512(path: Path) -> str:
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha512").hexdigest()
    label = "historical" if historical else "current"
    version = HISTORICAL_VERSION if historical else CURRENT_VERSION
    if platform.system() == "Linux":
        expected = ENGINE_LINUX_SHA512 if historical else CURRENT_LINUX_SHA512
        require(digest512(godot) == expected, label + " Linux engine bytes differ from the pinned editor")
        identity = {"path": str(godot), "sha512": expected, "version": version}
    elif platform.system() == "Windows":
        expected = ENGINE_WINDOWS_CONSOLE_SHA512 if historical else CURRENT_WINDOWS_CONSOLE_SHA512
        gui_expected = ENGINE_WINDOWS_SHA512 if historical else CURRENT_WINDOWS_SHA512
        gui = godot.with_name("Godot_v4.8-beta1_win64.exe" if historical else "Godot_v4.8-beta2_win64.exe")
        require(digest512(godot) == expected and digest512(gui) == gui_expected,
                label + " Windows engine bytes differ from the pinned editor")
        identity = {"path": str(godot), "sha512": expected, "version": version,
                    "gui_path": str(gui), "gui_sha512": gui_expected}
    else:
        raise ValueError("no pinned fixed-brake engine for this OS")
    require(subprocess.check_output([str(godot), "--version"], text=True).strip() == version,
            label + " engine build differs")
    return identity


def run(repo: Path, project: Path, godot: Path, historical_godot: Path, out: Path, scratch: Path) -> None:
    require(project.is_dir() and godot.is_file() and (project / ".godot/imported").is_dir(), "candidate project must be imported")
    require(historical_godot.is_file(), "historical beta1 engine is missing: " + str(historical_godot))
    current_engine = check_engine(godot, False)
    historical_engine = check_engine(historical_godot, True)
    fixture_path = project / "tests/fixtures/fixed_brake_legacy_outputs.json"
    for path, expected in ((fixture_path, FROZEN_FIXTURE), (CAPTURE, CAPTURE_SOURCE),
                           (CONSTRUCTION / "reconstruct_legacy_reference.py", RECONSTRUCTOR_SOURCE),
                           (CONSTRUCTION / "loaded-source-pins.json", SOURCE_PINS)):
        require(sha(path.read_bytes().replace(b"\r\n", b"\n")) == expected, "frozen gate source differs: " + str(path))
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    fuel_path = Path("data/fuels/openrc-fuel-registry.json")
    avanti_path = Path("data/aircraft/sebart_avanti_s_a200.json")
    candidate_fuel = (project / fuel_path).read_bytes()
    candidate_avanti = (project / avanti_path).read_bytes()
    check_input_bytes(candidate_fuel, candidate_avanti)
    candidate_sources = candidate_manifest(project)
    candidate_glow_flight = (project / GLOW_FLIGHT_PATH).read_bytes()
    require(sha(candidate_glow_flight) == candidate_sources[GLOW_FLIGHT_PATH],
            "candidate glow source changed during inventory")
    check_candidate_glow_law(candidate_glow_flight)
    out.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(parents=True, exist_ok=True)
    require(out.resolve() != scratch.resolve() and out.resolve() not in scratch.resolve().parents
            and scratch.resolve() not in out.resolve().parents, "checked receipts and scratch must be disjoint")
    run_dir = Path(tempfile.mkdtemp(prefix="fixed-brake-", dir=scratch))
    isolated_data, isolated_config, isolated_cache = (run_dir / name for name in ("user-data", "user-config", "user-cache"))
    for directory in (isolated_data, isolated_config, isolated_cache):
        directory.mkdir()
    run_env = {"XDG_DATA_HOME": str(isolated_data), "XDG_CONFIG_HOME": str(isolated_config),
               "XDG_CACHE_HOME": str(isolated_cache), "APPDATA": str(isolated_config),
               "LOCALAPPDATA": str(isolated_data)}
    ref = run_dir / "reference"
    subprocess.run([sys.executable, str(CONSTRUCTION / "reconstruct_legacy_reference.py"), str(repo), str(ref),
                    "--nitro-06-r3", "--focused-checkout"], check=True, timeout=1200)
    identity = json.loads((ref / "app/reference.json").read_text(encoding="utf-8"))
    require(identity.get("pinned_inputs_verified") == 400 and identity.get("base_commit") == "fa9f387f6"
            and identity.get("nitro_06_r3") == "20662f264" and identity.get("carburetor_sha256") == CARB_R3,
            "reconstructed source identity differs")
    (run_dir / "input-identities.json").write_text(json.dumps({"candidate": candidate_sources,
                                                                "historical": identity,
                                                                "engines": {"historical": historical_engine,
                                                                            "current": current_engine}}, indent=2, sort_keys=True) + "\n",
                                                    encoding="utf-8")
    historical_avanti = (ref / "app" / avanti_path).read_bytes()
    require(sha(historical_avanti) == AVANTI_OLD, "historical Avanti identity differs")
    reconstructed_fuel = (ref / "app" / fuel_path).read_bytes().replace(b"\r\n", b"\n")
    require(sha(reconstructed_fuel) == FUEL_LF, "historical fuel content differs")
    (ref / "app" / fuel_path).write_bytes(reconstructed_fuel.replace(b"\n", b"\r\n"))
    require(sha((ref / "app" / fuel_path).read_bytes()) == FUEL_CRLF, "historical fuel identity differs")
    require((repo / "assets").is_dir(), "reference asset source is missing")
    os.symlink(repo / "assets", ref / "assets", target_is_directory=True)
    # The old custom font is read before a fresh project's first import. Disable
    # that setting only to bootstrap resources, restore the exact original bytes,
    # then require a second error-free checked import with the real settings.
    project_file = ref / "app/project.godot"
    project_bytes = project_file.read_bytes()
    theme_line = b'theme/custom_font="res://assets/fonts/interface_font.tres"'
    require(project_bytes.count(theme_line) == 1, "historical font setting differs")
    try:
        project_file.write_bytes(project_bytes.replace(theme_line, b";" + theme_line))
        checked(historical_godot, ref / "app", out, "fixed-brake-reference-bootstrap", ["--import"], timeout=1200, extra_env=run_env)
    finally:
        project_file.write_bytes(project_bytes)
    require(project_file.read_bytes() == project_bytes, "historical project settings were not restored")
    checked(historical_godot, ref / "app", out, "fixed-brake-reference-import", ["--import"], timeout=1200, extra_env=run_env)
    historical_fuel = reconstructed_fuel.replace(b"\n", b"\r\n")
    check_reference_inputs(ref / "app", historical_fuel, historical_avanti)
    gold_path = run_dir / "historical-goldens.json"
    checked(historical_godot, ref / "app", out, "fixed-brake-historical-goldens", ["--script", str(CAPTURE), "--", "--out=" + str(gold_path)], extra_env=run_env)
    golden = load_capture(gold_path, fixture, True, fixture["engine"])
    check_goldens(golden, fixture)
    check_reference_inputs(ref / "app", historical_fuel, historical_avanti)
    # Keep the historical capture intact; import the same verified source with
    # the current engine before constructing the current-engine oracle.
    checked(godot, ref / "app", out, "fixed-brake-current-reference-import", ["--import"], timeout=1200, extra_env=run_env)
    check_reference_inputs(ref / "app", historical_fuel, historical_avanti)
    # Only after the historical goldens and original reference checks pass,
    # derive exact declaration-only substitutions from the pinned old files.
    # This matches metadata identity, not the v6 fuel-event implementation.
    law_overlay = reference_law_overlay(ref / "app")
    overlay_identities = {
        path: {"original_sha256": file_sha(ref / "app" / path), "patched_sha256": sha(patched)}
        for path, patched in law_overlay.items()
    }
    for path, patched in law_overlay.items():
        (ref / "app" / path).write_bytes(patched)
    (ref / "app" / fuel_path).write_bytes(candidate_fuel)
    (ref / "app" / avanti_path).write_bytes(candidate_avanti)
    check_reference_inputs(ref / "app", candidate_fuel, candidate_avanti, law_overlay)
    (run_dir / "glow-law-overlay.json").write_text(json.dumps({
        "candidate_law": GLOW_LAW_CURRENT.decode("ascii"),
        "reference": overlay_identities,
        "scope": "identity declarations only; historical glow dynamics retained",
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    matched_path, candidate_path = run_dir / "matched-reference.json", run_dir / "candidate.json"
    checked(godot, ref / "app", out, "fixed-brake-matched-reference", ["--script", str(CAPTURE), "--", "--out=" + str(matched_path)], extra_env=run_env)
    checked(godot, project, out, "fixed-brake-candidate-capture", ["--script", str(CAPTURE), "--", "--out=" + str(candidate_path)], extra_env=run_env)
    matched = load_capture(matched_path, fixture, True, CURRENT_CAPTURE_ENGINE, TRACE_LAW_OVERLAY)
    candidate = load_capture(candidate_path, fixture, False, CURRENT_CAPTURE_ENGINE)
    check_reference_inputs(ref / "app", candidate_fuel, candidate_avanti, law_overlay)
    check_comparison(matched, candidate)
    checked(godot, project, out, "fixed-brake-input", ["--script", "res://tests/test_fixed_gear_brake_input.gd"],
            timeout=180, extra_env={**run_env, "OPENRC_FIXED_BRAKE_REFERENCE": str(matched_path)},
            required_text=("Fixed brake candidate:", "0 failed"))
    check_reference_inputs(ref / "app", candidate_fuel, candidate_avanti, law_overlay)
    require(candidate_manifest(project) == candidate_sources, "candidate inputs changed during the comparison")
    require(check_engine(historical_godot, True) == historical_engine and check_engine(godot, False) == current_engine,
            "engine identity changed during the comparison")
    print("Fixed-brake: all 16 beta1 original goldens and beta2 same-host candidate digests match; evidence:", run_dir)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--historical-godot", type=Path, help="verified beta1 editor; otherwise obtain it in the repository .tools cache")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--scratch-dir", type=Path, default=ROOT / "tmp/fixed-brake-evidence")
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    args = parser.parse_args()
    try:
        repo = args.repo.resolve()
        historical_godot = (args.historical_godot or ensure_historical_godot(repo)).resolve()
        run(repo, args.project.resolve(), args.godot.resolve(), historical_godot, args.out_dir.resolve(), args.scratch_dir.resolve())
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Fixed-brake gate failed:", error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
