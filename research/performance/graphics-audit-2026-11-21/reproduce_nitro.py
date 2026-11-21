#!/usr/bin/env python3
"""Run a bounded unchanged NitroVoice component probe, never a whole-app/FPS benchmark."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

from reproduce import ENGINE, LINUX_ENGINE_SHA512

SOURCE = "6b2228c7633a34e38cb05d92e3ca50893810e02b"
FILES = ("app/audio/nitro_voice.gd", "app/audio/nitro_engine_audio.gd")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        parser.error("--out must be new or empty")
    engine = args.godot.resolve()
    engine_bytes = engine.read_bytes()
    if hashlib.sha512(engine_bytes).hexdigest() != LINUX_ENGINE_SHA512:
        parser.error("expected the pinned official Linux x86_64 binary")
    env = os.environ.copy()
    for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        private = out / key.lower()
        private.mkdir()
        env[key] = str(private)
    version = subprocess.check_output([str(engine), "--version"], env=env, text=True).strip()
    if version != ENGINE:
        parser.error(f"unexpected engine {version}")
    fixture = out / "fixture"
    fixture.mkdir()
    inventory = []
    for name in FILES:
        for candidate in (name, name + ".uid"):
            data = subprocess.check_output(["git", "-C", str(root), "show", f"{SOURCE}:{candidate}"])
            target = fixture / candidate.removeprefix("app/")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            inventory.append({"source": candidate, "sha256": digest(data), "bytes": len(data)})
    config = ('config_version=5\n[application]\nconfig/name="Detached Nitro audit"\n'
              '[rendering]\nrenderer/rendering_method="forward_plus"\n')
    (fixture / "project.godot").write_text(config)
    probe = Path(__file__).with_name("nitro_voice_probe.gd")
    (fixture / probe.name).write_bytes(probe.read_bytes())
    runner = root / "tools/godot/run_checked.py"
    manifest = {"source": SOURCE, "engine_version": version, "engine_sha256": digest(engine_bytes),
                "dependencies": inventory, "probe_sha256": digest(probe.read_bytes()),
                "runner_sha256": digest(runner.read_bytes()), "fixture_config_sha256": digest(config.encode()),
                "host": {"system": platform.system(), "release": platform.release(),
                         "machine": platform.machine(), "logical_cpu_count": os.cpu_count()},
                "scope": "component-only elapsed timing, headless/Dummy; no native candidate or FPS claim"}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    checks = []
    for label, tail, marker in (
        ("nitro-fixture-import", ["--editor", "--import"], None),
        ("nitro-component", ["--script", "res://" + probe.name], "NITRO_AUDIT_COMPONENT:"),
    ):
        command = [sys.executable, str(runner), "--out-dir", str(out / "checks"), "--label", label,
                   "--timeout", "60", "--warnings-as-errors"]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--path", str(fixture), "--audio-driver", "Dummy", *tail]
        result = subprocess.run(command, env=env, cwd=root, check=False)
        checks.append({"label": label, "exit_code": result.returncode})
        if result.returncode:
            break
    stable = all(digest((fixture / row["source"].removeprefix("app/")).read_bytes()) == row["sha256"]
                 for row in inventory)
    engine_stable = digest(engine.read_bytes()) == manifest["engine_sha256"]
    harness_stable = (digest((fixture / probe.name).read_bytes()) == manifest["probe_sha256"]
                      and digest(probe.read_bytes()) == manifest["probe_sha256"]
                      and digest(runner.read_bytes()) == manifest["runner_sha256"]
                      and digest((fixture / "project.godot").read_bytes()) == manifest["fixture_config_sha256"])
    result_path = fixture / "nitro-voice-results.json"
    result_ok = False
    result_sha256 = None
    result_error = None
    try:
        result_bytes = result_path.read_bytes()
        result_sha256 = digest(result_bytes)
        result = json.loads(result_bytes)
        result_ok = (result["schema"] == "openrc-audit-nitro-component-v1"
                     and result["failures"] == 0 and result["checks"] == 43
                     and len(result["rows"]) == 18
                     and all(row["sample_count"] == len(row["durations_usec"]) == 41
                             for row in result["rows"]))
    except (OSError, ValueError, KeyError, TypeError) as error:
        result_error = str(error)
    summary = {"checks": checks, "source_stable": stable, "engine_stable": engine_stable,
               "harness_stable": harness_stable, "result_ok": result_ok,
               "result_sha256": result_sha256, "result_error": result_error,
               "ok": len(checks) == 2 and all(row["exit_code"] == 0 for row in checks)
                     and stable and engine_stable and harness_stable and result_ok}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
