"""Exercise the real Godot probe, including disposable pause/input observer mutations."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from session_baseline import ENGINE_ERROR_RE, reduce_backend_pair, reduce_pair, validate_probe_report


def isolated_app(source: Path, target: Path, stale: bool) -> Path:
    """Use separate writable project metadata/native files; never alter the installed extension."""
    target.mkdir()
    for entry in source.iterdir():
        if entry.name in (".godot", "native"):
            continue
        (target / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    (target / ".godot").mkdir()
    # Runtime loads already-imported assets but does not run the editor/importer here.
    (target / ".godot/imported").symlink_to(source / ".godot/imported", target_is_directory=True)
    class_cache = source / ".godot/global_script_class_cache.cfg"
    if class_cache.is_file():
        shutil.copy2(class_cache, target / ".godot/global_script_class_cache.cfg")
    kernel = target / "native/kernel"
    kernel.mkdir(parents=True)
    if stale:
        installed = source / "native/kernel"
        for name in ("libopenrc_native_kernel.so", "openrc_native_kernel.gdextension", "build-receipt.json"):
            shutil.copy2(installed / name, kernel / name)
        receipt_path = kernel / "build-receipt.json"
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["platforms"]["linux"]["mirrored_sources"]["app/physics/aero.gd"] = "0" * 64
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--native-guards", action="store_true",
                        help="also check an installed verified Linux native backend and isolated refusal cases")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    probe = Path(__file__).with_name("session_probe.gd")
    source = probe.read_text(encoding="utf-8")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    engine = args.godot.resolve()
    results = []
    reports = {}
    with tempfile.TemporaryDirectory(prefix="openrc-probe-mutations-") as temporary:
        temporary_path = Path(temporary)
        cases = [
            ("control-on", "", "on", "gdscript_reference", root / "app", ""),
            ("control-off", "", "off", "gdscript_reference", root / "app", ""),
            ("paused", "_session.sim.set_paused(true)", "on", "gdscript_reference", root / "app", ""),
            ("input-disabled", "_session.input_enabled = false", "on", "gdscript_reference", root / "app", ""),
            ("stopped", "_session.sim.stop_at_tick = 0", "on", "gdscript_reference", root / "app", ""),
            ("altered-observer", "altered-observer", "on", "gdscript_reference", root / "app", ""),
            ("altered-warmup", "altered-warmup", "on", "gdscript_reference", root / "app", ""),
        ]
        if args.native_guards:
            absent_app = isolated_app(root / "app", temporary_path / "absent-app", False)
            stale_app = isolated_app(root / "app", temporary_path / "stale-app", True)
            cases.extend([
                ("native-control", "", "on", "native", root / "app", ""),
                ("native-absent", "", "on", "native", absent_app, ""),
                ("native-stale", "", "on", "native", stale_app, ""),
                ("native-refused-aircraft", "", "on", "native", root / "app", "p51d-mustang-120"),
                ("native-displaced", "native-displaced", "on", "native", root / "app", ""),
                ("native-uncovered", "native-uncovered", "on", "native", root / "app", ""),
            ])
        for name, edit, observer, backend, app, aircraft in cases:
            script = probe
            if edit:
                mutated = source
                if edit == "altered-observer":
                    needle = "\t\tvar middle: int = Time.get_ticks_usec()"
                    mutated = mutated.replace(needle, "\t\t_session.sim.inputs[0] += 0.1\n" + needle, 1)
                elif edit == "altered-warmup":
                    needle = "\t\t\t_hash_tick(digest)\n\t\tif _failure.is_empty():"
                    mutated = mutated.replace(needle, "\t\t\t_session.sim.inputs[0] += 0.1\n"
                                              "\t\t\t_hash_tick(digest)\n\t\t\t_session.sim.inputs[0] -= 0.1\n"
                                              "\t\tif _failure.is_empty():", 1)
                elif edit in ("native-displaced", "native-uncovered"):
                    needle = "\tif _session.sim.tick != tick + 1 or _input_reads != reads + 1:"
                    action = ("_session.sim.model.stage = Callable(_session, \"_wheel_evaluate\")"
                              if edit == "native-displaced" else "_native.reset_stage_stats(false)")
                    mutated = mutated.replace(needle, "\t" + action + "\n" + needle, 1)
                else:
                    mutated = mutated.replace("\tif _prepare():\n", "\tif _prepare():\n\t\t" + edit + "\n", 1)
                if mutated == source:
                    raise RuntimeError("mutation seam changed; review this verification tool")
                script = Path(temporary) / (name + ".gd")
                script.write_text(mutated, encoding="utf-8")
            path = out / (name + ".json")
            command = [str(engine), "--headless", "--path", str(app),
                       "--script", str(script), "--", f"--output={path}",
                       "--warmup-ticks=2", "--sample-ticks=8", f"--observer={observer}",
                       f"--physics-backend={backend}"]
            if aircraft:
                command.append(f"--aircraft={aircraft}")
            run = subprocess.run(command, capture_output=True, timeout=120)
            log = run.stdout + run.stderr
            (out / (name + ".log")).write_bytes(log)
            report = json.loads(path.read_text(encoding="utf-8"))
            reports[name] = report
            expected_success = name in ("control-on", "control-off", "native-control", "altered-observer", "altered-warmup")
            passed = ((run.returncode == 0) == expected_success
                      and report.get("complete") is expected_success
                      and not ENGINE_ERROR_RE.search(log.decode("utf-8", errors="replace"))
                      and not validate_probe_report(report, allow_incomplete=not expected_success))
            refusal = {"native-absent": "not installed", "native-stale": "mirrored source differs",
                       "native-refused-aircraft": "only the stock Ugly Stik",
                       "native-displaced": "stage backend changed", "native-uncovered": "did not cover tick"}
            if name in refusal:
                passed = passed and refusal[name] in report.get("failure", "")
                if name in ("native-absent", "native-stale", "native-refused-aircraft"):
                    passed = passed and report.get("backend", {}).get("actual", {}).get("backend") == "gdscript_reference"
            results.append({"case": name, "passed": passed, "exit_code": run.returncode,
                            "failure": report.get("failure"), "command": command,
                            "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest()})
    for name, left, right, expected in (
        ("unchanged-observer-parity", "control-on", "control-off", True),
        ("altered-observer-rejected", "altered-observer", "control-off", False),
        ("altered-warmup-rejected", "altered-warmup", "control-off", False),
    ):
        reduced = reduce_pair(reports[left], reports[right])
        results.append({"case": name, "passed": reduced["comparable"] is expected,
                        "pair": reduced})
    if args.native_guards:
        pair = reduce_backend_pair(reports["control-on"], reports["native-control"])
        results.append({"case": "production-backend-parity", "passed": pair["comparable"], "pair": pair})
    complete = all(case["passed"] for case in results)
    (out / "verification.json").write_text(json.dumps({
        "format": "openrc-session-probe-verification v1", "complete": complete,
        "native_guards_requested": args.native_guards,
        "probe_sha256": hashlib.sha256(probe.read_bytes()).hexdigest(), "cases": results,
        "scope": "Disposable external scripts only; no runtime or golden mutation. Software guard checks, not performance samples.",
    }, indent=2) + "\n", encoding="utf-8")
    print(f"session probe verification: {sum(c['passed'] for c in results)}/{len(results)} passed")
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
