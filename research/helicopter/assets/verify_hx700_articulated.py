#!/usr/bin/env python3
"""HELI-25c native admission, fresh import and isolated package dependency proof."""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def run(command, log, expected_missing_texture=False):
    result = subprocess.run([str(v) for v in command], cwd=REPO, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=180)
    log.write_text(result.stdout, encoding="utf-8")
    errors = re.findall(r"^(?:SCRIPT |SHADER )?ERROR:.*$", result.stdout, re.MULTILINE)
    resource_path = r"res://(?:\.godot/imported/[^/]+\.(?:ctex|scn)|assets/aircraft/hx-700/articulated/[^/]+\.(?:png|glb))"
    expected_error = r"ERROR: (?:(?:Unable to open file|Failed loading resource): " + resource_path + r"\.|(?:Can't load dependency|Error loading resource): '" + resource_path + r"'\.)"
    allowed = expected_missing_texture and all(re.fullmatch(expected_error, line.strip()) for line in errors)
    if result.returncode or (errors and not allowed):
        raise RuntimeError(f"Check failed ({result.returncode}): {log}\n{result.stdout[-4000:]}")
    if "WARNING: Broken external resource!" in result.stdout and not expected_missing_texture:
        raise RuntimeError("Broken imported resource dependency: " + str(log))
    if expected_missing_texture and "HELI-25c package rejected:" not in result.stdout:
        raise RuntimeError("Missing-texture fixture did not fail closed: " + str(log))
    if expected_missing_texture and not any("Unable to open file:" in line and ".ctex" in line for line in errors):
        raise RuntimeError("Texture omission did not exercise the expected missing payload: " + str(log))
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--capture", action="store_true", help="requires a display; records native material inspection")
    parser.add_argument("--motion", action="store_true", help="also qualify the advanced mechanical inspection adapter")
    args = parser.parse_args()
    godot, out = args.godot.resolve(strict=True), args.out.resolve()
    out.relative_to((REPO / ".tools").resolve())
    if out.exists():
        raise ValueError("Use a fresh output directory.")
    out.mkdir(parents=True)
    run([sys.executable, HERE / "compile_hx700_articulated.py"], out / "compiler.log")
    if args.motion:
        run([sys.executable, HERE / "compile_hx700_motion.py", "--check"], out / "motion-compiler.log")
        run([godot, "--headless", "--path", REPO / "app", "--audio-driver", "Dummy", "--script",
             "res://tests/test_heli_mechanism.gd"], out / "motion-native-tests.log")
        run([godot, "--headless", "--path", REPO / "app", "--audio-driver", "Dummy", "--script",
             "res://tests/test_heli_mechanics_view.gd"], out / "motion-ui-native-tests.log")
    run([godot, "--headless", "--path", REPO / "app", "--audio-driver", "Dummy", "--script",
         "res://tests/test_heli_construction.gd"], out / "native-tests.log")
    project = out / "fresh"
    project.mkdir()
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="HELI-25c isolated preview"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    for relative in ("aircraft/hx700_articulated_model.gd", "assets/aircraft/hx-700/articulated/hx-700.glb",
                     "assets/aircraft/hx-700/articulated/construction.json"):
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / "app" / relative, target)
    shutil.copyfile(HERE / "preview_hx700_native.gd", project / "smoke.gd")
    shutil.copyfile(HERE / "pack_hx700_preview.gd", project / "pack.gd")
    if args.motion:
        for relative in ("render/rotor/hx700_motion_equations.gd", "render/rotor/hx700_mechanism.gd",
                         "render/rotor/hx700_mechanics_view.gd", "tools/inspect_hx700.gd", "tests/test_heli_mechanism.gd",
                         "tests/test_heli_mechanics_view.gd"):
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / "app" / relative, target)
    run([godot, "--headless", "--path", project, "--editor", "--import"], out / "fresh-import.log")
    run([godot, "--headless", "--path", project, "--audio-driver", "Dummy", "--script", "res://smoke.gd",
         "--", "--proof=" + str(out / "fresh-proof.json")], out / "fresh-smoke.log")
    oracle = REPO / "research/helicopter/reference/hx700_motion_oracle.json"
    if args.motion:
        run([godot, "--headless", "--path", project, "--audio-driver", "Dummy", "--script",
             "res://tests/test_heli_mechanism.gd", "--", "--oracle=" + str(oracle)], out / "motion-fresh-tests.log")
        run([godot, "--headless", "--path", project, "--audio-driver", "Dummy", "--script",
             "res://tests/test_heli_mechanics_view.gd"], out / "motion-ui-fresh-tests.log")
    empty = out / "empty"
    empty.mkdir()
    for defect in ("", "profile", "raw-glb", "texture"):
        label = defect or "complete"
        pack = out / (label + ".pck")
        run([godot, "--headless", "--path", project, "--script", "res://pack.gd", "--",
             "--out=" + str(pack), "--omit=" + defect], out / (label + "-pack.log"))
        cmd = [godot, "--headless", "--path", empty, "--main-pack", pack, "--audio-driver", "Dummy",
               "--script", "res://smoke.gd", "--"]
        cmd += ["--expect-reject"] if defect else ["--proof=" + str(out / "package-proof.json")]
        run(cmd, out / (label + "-smoke.log"), expected_missing_texture=defect == "texture")
        if args.motion and not defect:
            run([godot, "--headless", "--path", empty, "--main-pack", pack, "--audio-driver", "Dummy",
                 "--script", "res://tests/test_heli_mechanism.gd", "--", "--oracle=" + str(oracle)], out / "motion-package-tests.log")
            run([godot, "--headless", "--path", empty, "--main-pack", pack, "--audio-driver", "Dummy",
                 "--script", "res://tests/test_heli_mechanics_view.gd"], out / "motion-ui-package-tests.log")
    if args.capture:
        run([godot, "--path", project, "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility",
             "--script", "res://smoke.gd", "--", "--capture=" + str(out / "captures")], out / "capture.log")
        if args.motion:
            run([godot, "--path", project, "--audio-driver", "Dummy", "--script", "res://tools/inspect_hx700.gd",
                 "--", "--capture=" + str(out / "motion-captures")], out / "motion-capture.log")
    report = {"step": "HELI-25c", "native_tests": "pass", "fresh_import": "pass", "isolated_pack": "pass",
              "missing_profile_rejected": True, "missing_raw_glb_rejected": True, "missing_texture_rejected": True, "flight_admitted": False,
              "production_export_qualified": False, "captured": args.capture}
    if args.motion:
        report.update(step="HELI-26a", motion_native="pass", motion_fresh_import="pass", motion_package="pass", motion_ui="pass")
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
