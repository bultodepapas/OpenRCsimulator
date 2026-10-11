"""G3b qualification in a fresh disposable app; never mutate the caller's source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ERROR = re.compile(r"^\s*(?:(?:SCRIPT|SHADER) )?ERROR:", re.MULTILINE)
TESTS = ("test_engine_sound", "test_engine_voice", "test_engine_audio", "test_ui_pause")


def run(godot: Path, app: Path, out: Path, name: str, args: list[str], *, expected: str | None = None) -> dict:
    command = [str(godot), "--display-driver", "headless", "--audio-driver", "Dummy",
               "--path", str(app), *args]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=180 if "--import" in args else 60)
    log = result.stdout + result.stderr
    (out / f"{name}.log").write_text(log, encoding="utf-8")
    valid = not ERROR.search(log) and (result.returncode == 0 if expected is None
                                     else result.returncode != 0 and expected in log)
    if not valid:
        raise RuntimeError(f"{name}: unexpected result; inspect {out / (name + '.log')}")
    return {"command": command, "exit_code": result.returncode, "expected_failure": expected}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    godot, source, out = args.godot.resolve(), args.app.resolve(), args.out.resolve()
    if out.exists():
        parser.error("--out must be a fresh path")
    out.mkdir(parents=True)
    app = out / "app"
    shutil.copytree(source, app, ignore=shutil.ignore_patterns(".godot", "captures", "__pycache__"))
    manifest = {str(p.relative_to(app)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(app.rglob("*")) if p.is_file()}
    (out / "source-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    results = {"import": run(godot, app, out, "import", ["--import"])}
    for test in TESTS:
        results[test] = run(godot, app, out, test, ["--script", f"res://tests/{test}.gd"])

    # Real defects in a disposable source copy, each restored before the next one.
    mutations = [
        ("phase_reset", "render/engine_voice.gd", "cycles = fposmod(cycles, 1.0)",
         "cycles = 0.0", "test_engine_voice", "pure oscillator partitioning"),
        ("dc_at_rest", "render/engine_voice.gd", "if freq <= 0.0:",
         "if freq < 0.0:", "test_engine_voice", "zero frequency returns exact silence"),
        ("missed_endpoint", "render/engine_audio.gd", "snapshot_rpm = aux[0]",
         "snapshot_rpm = 0.0", "test_engine_audio", "observes every accepted endpoint"),
        ("stale_resume", "render/engine_audio.gd", "if _was_paused:",
         "if false and _was_paused:", "test_engine_audio", "resume replaces old playback queue"),
        ("unowned_source", "render/engine_audio.gd", 'playback.set_meta("openrc_generator_source", stream)',
         "pass", "test_engine_audio", "playback retains its source after node removal"),
    ]
    for name, relative, before, after, test, failure in mutations:
        path = app / relative
        original = path.read_bytes()
        text = original.decode("utf-8")
        if text.count(before) != 1:
            raise RuntimeError(f"{name}: mutation anchor changed")
        try:
            path.write_text(text.replace(before, after), encoding="utf-8", newline="\n")
            results[name] = run(godot, app, out, name, ["--script", f"res://tests/{test}.gd"], expected=failure)
        finally:
            path.write_bytes(original)
    results["restored"] = run(godot, app, out, "restored", ["--script", "res://tests/test_engine_audio.gd"])
    (out / "verified.json").write_text(json.dumps({"ok": True, "results": results}, indent=2) + "\n", encoding="utf-8")
    print("G3b focused tests and five real defects verified")


if __name__ == "__main__":
    main()
