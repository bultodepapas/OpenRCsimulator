"""Run bounded, exact-source shadow state/geometry checks with the pinned engine.

Uses the repository checked runner. The minimal project deliberately omits the
production autoloads, UI, assets and renderer session; it is not full-app or visual
qualification. Existing selected tests are copied without editing their bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

BASE = "3c91936ab8f9064daa798311b5fb3e89e28d3754"
ENGINE_SHA512 = "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
TESTS = ["tests/test_shadow_collection.gd", "tests/test_shadow_blur.gd"]
START = TESTS + ["render/atmosphere.gd", "render/shadow.gd", "render/cloud_shadow_map.gd", "debug/render_probe.gd"]
DEPENDENCY = re.compile(r'(?:preload|load)\("res://([^"\n]+)"\)|#include\s+"res://([^"\n]+)"|extends\s+"res://([^"\n]+)"')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source, godot, output = args.source.resolve(), args.godot.resolve(), args.out.resolve()
    if output.exists():
        parser.error("--out must be a new directory; earlier evidence is never overwritten")
    engine_hash = hashlib.sha512(godot.read_bytes()).hexdigest()
    if engine_hash != ENGINE_SHA512:
        parser.error("this retained campaign requires the pinned Linux x86_64 4.8-beta2 executable")
    baseline_rows = subprocess.check_output(["git", "ls-tree", "-r", BASE, "app"], cwd=source, text=True).splitlines()
    blobs = {row.split("\t", 1)[1]: row.split()[2] for row in baseline_rows}
    output.mkdir(parents=True)
    fixture = output / "fixture"
    fixture.mkdir()
    pending, seen, manifest = list(START), set(), []
    while pending:
        relative = pending.pop()
        if relative in seen:
            continue
        seen.add(relative)
        path = source / "app" / relative
        if not path.is_file():
            raise FileNotFoundError(f"exact-source fixture dependency missing: {path}")
        data = path.read_bytes()
        git_blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if git_blob != blobs.get("app/" + relative):
            raise ValueError(f"source does not match the audited baseline: {relative}")
        target = fixture / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest.append({"path": "app/" + relative, "git_blob": git_blob, "sha256": hashlib.sha256(data).hexdigest()})
        if path.suffix in {".gd", ".gdshader", ".gdshaderinc"}:
            for groups in DEPENDENCY.findall(data.decode("utf-8")):
                pending.append(next(value for value in groups if value))
    (fixture / "project.godot").write_text('config_version=5\n\n[application]\nconfig/name="OpenRC shadow audit isolated fixture"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    shutil.copyfile(Path(__file__).with_name("probe.gd"), fixture / "probe.gd")
    harness = [Path(__file__).resolve(), Path(__file__).with_name("probe.gd").resolve(),
               source / "tools/godot/run_checked.py", source / "tools/testqueue/common.py", fixture / "project.godot"]
    harness_hashes = [{"path": str(path.relative_to(source)) if path.is_relative_to(source) else str(path),
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in harness]
    (output / "source_manifest.json").write_text(json.dumps({"baseline": BASE, "engine_sha512": engine_hash,
        "fixture_scope": "unchanged selected source modules; minimal project; no production app startup or GPU qualification",
        "harness": harness_hashes,
        "files": sorted(manifest, key=lambda x: x["path"])}, indent=2) + "\n")
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(output / "user-data")
    env["XDG_CONFIG_HOME"] = str(output / "user-config")
    env["XDG_CACHE_HOME"] = str(output / "user-cache")
    runner = source / "tools/godot/run_checked.py"
    def run(label: str, tail: list[str], required: str | None = None) -> int:
        command = [sys.executable, str(runner), "--out-dir", str(output / "checks"), "--label", label,
                   "--timeout", "90", "--warnings-as-errors"]
        if required:
            command += ["--require-text", required]
        command += ["--", str(godot), "--headless", "--path", str(fixture), "--audio-driver", "Dummy"] + tail
        return subprocess.run(command, cwd=source, env=env, check=False).returncode
    results = [{"label": "import", "exit": run("import", ["--editor", "--import"])}]
    if results[-1]["exit"] == 0:
        for test in TESTS:
            results.append({"label": test, "exit": run(Path(test).stem, ["--script", "res://" + test], "0 failed")})
        results.append({"label": "probe", "exit": run("shadow-audit-probe", ["--script", "res://probe.gd", "--",
            "--out=" + str(output / "observations.json")], "0 failed")})
    (output / "campaign.json").write_text(json.dumps({"baseline": BASE, "results": results,
        "passed": len(results) == len(TESTS) + 2 and all(row["exit"] == 0 for row in results),
        "visual_qualification": "not_run", "gpu_performance": "not_run", "full_app_suite": "not_run"}, indent=2) + "\n")
    return 0 if len(results) == len(TESTS) + 2 and all(row["exit"] == 0 for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
