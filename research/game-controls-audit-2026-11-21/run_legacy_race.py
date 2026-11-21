#!/usr/bin/env python3
"""Schedule two real legacy calibration writers at the read/write boundary.

Only a disposable copy of rc_calibration.gd is instrumented. The injected barrier
adds ordering/timeout and marker files; validation and ConfigFile read/write stay
unchanged. This is an instrumented component witness, not a native user incident.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from run_checks import ENGINE, ENGINE_SHA512, digest

DRIVER = '''extends SceneTree
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 4:
        printerr("Expected mode, source, store and device key")
        quit(2)
        return
    var calibration: Script = load(args[1])
    if args[0] == "write":
        var profile: Dictionary = preload("res://input/rc_input.gd").DEFAULT_PROFILE.duplicate(true)
        var result: int = calibration.save_profile(args[2], args[3], profile)
        print("LEGACY_WRITE ", JSON.stringify({device = args[3], result = result}))
        quit(0 if result == OK else 1)
    else:
        var records := {}
        for key: String in ["seed", "writer-A", "writer-B"]:
            records[key] = not calibration.load_profile(args[2], key).is_empty()
        print("LEGACY_READ ", JSON.stringify(records))
        quit(0 if records.seed and not records["writer-A"] and records["writer-B"] else 1)
'''

BARRIER = '''\tvar audit_barrier := OS.get_environment("OPENRC_AUDIT_BARRIER")
\tvar audit_writer := OS.get_environment("OPENRC_AUDIT_WRITER")
\tvar audit_ready := FileAccess.open(audit_barrier.path_join(audit_writer + ".ready"), FileAccess.WRITE)
\tif audit_ready == null: return ERR_CANT_CREATE
\taudit_ready.store_string("loaded and modified")
\taudit_ready.close()
\tvar audit_wait := "B.ready" if audit_writer == "A" else "A.done"
\tvar audit_deadline := Time.get_ticks_msec() + 10000
\twhile not FileAccess.file_exists(audit_barrier.path_join(audit_wait)):
\t\tif Time.get_ticks_msec() >= audit_deadline: return ERR_TIMEOUT
\t\tOS.delay_msec(5)
\tvar audit_result: Error = cfg.save(path)
\tif audit_writer == "A":
\t\tvar audit_done := FileAccess.open(audit_barrier.path_join("A.done"), FileAccess.WRITE)
\t\tif audit_done == null: return ERR_CANT_CREATE
\t\taudit_done.store_string(str(audit_result))
\t\taudit_done.close()
\treturn audit_result
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", type=Path)
    args = parser.parse_args()
    root, out = args.repo.resolve(), args.out.resolve()
    engine = args.godot.resolve() if args.godot else Path(subprocess.check_output(["bash", str(root / "app/get-godot.sh")], cwd=root, text=True).strip())
    if digest(engine, "sha512") != ENGINE_SHA512 or subprocess.check_output([str(engine), "--version"], text=True).strip() != ENGINE:
        parser.error("Use the pinned official Linux engine.")
    out.mkdir(parents=True, exist_ok=False)
    original_path = root / "app/input/rc_calibration.gd"
    original = original_path.read_text()
    start = original.index("static func save_profile(")
    end = original.index("static func load_profile(", start)
    function = original[start:end]
    needle = "\treturn cfg.save(path)\n"
    if function.count(needle) != 1:
        parser.error("Save method changed; review the barrier placement against the current source.")
    modified = original[:start] + function.replace(needle, BARRIER, 1) + original[end:]
    copy_path = out / "instrumented_calibration.gd"
    copy_path.write_text(modified)
    (out / "instrumentation.patch").write_text("".join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True), fromfile="original/rc_calibration.gd", tofile="instrumented/rc_calibration.gd")))
    driver = out / "driver.gd"
    driver.write_text(DRIVER)
    store = out / "legacy.cfg"

    def run(label: str, mode: str, source: Path, key: str, writer: str = "") -> dict:
        env = os.environ.copy()
        for variable, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            env[variable] = str(out / "user" / label / folder)
        if writer:
            env["OPENRC_AUDIT_BARRIER"] = str(out)
            env["OPENRC_AUDIT_WRITER"] = writer
        marker = "LEGACY_WRITE" if mode == "write" else "LEGACY_READ"
        command = [sys.executable, str(root / "tools/godot/run_checked.py"), "--label", label, "--out-dir", str(out / label),
                   "--timeout", "30", "--require-text", marker, "--", str(engine), "--headless", "--path", str(root / "app"),
                   "--audio-driver", "Dummy", "--script", str(driver), "--", mode, str(source), str(store), key]
        with (out / (label + ".txt")).open("w") as stream:
            process = subprocess.run(command, cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT)
        reports = list((out / label).glob("*/report.json"))
        if len(reports) != 1:
            return {"label": label, "ok": False, "returncode": process.returncode}
        p = reports[0]
        report = json.loads(p.read_text())
        log = (p.parent / "engine.log").read_text(errors="replace")
        observations = [line for line in log.splitlines() if line.startswith(marker)]
        return {"label": label, "ok": bool(report.get("ok")) and process.returncode == 0, "counts": report.get("counts"),
                "reason": report.get("reason"), "report": str(p.relative_to(out)), "report_sha256": digest(p),
                "log_sha256": digest(p.parent / "engine.log"), "observations": observations}

    results = [run("seed", "write", original_path, "seed")]
    if results[0]["ok"]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(run, "writer-A", "write", copy_path, "writer-A", "A")
            second = executor.submit(run, "writer-B", "write", copy_path, "writer-B", "B")
            results += [first.result(), second.result()]
        if all(r["ok"] for r in results):
            results.append(run("inspect", "read", original_path, "unused"))
    receipt = {"id": "GCA-04", "scope": "Two processes; production method with injected deterministic scheduling barrier on a disposable copy",
               "source": "app/input/rc_calibration.gd", "source_sha256": digest(original_path),
               "instrumented_sha256": digest(copy_path), "driver_sha256": digest(driver),
               "engine": ENGINE, "engine_sha512": ENGINE_SHA512, "runs": results,
               "witness_reproduced": len(results) == 4 and all(r["ok"] for r in results)}
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["witness_reproduced"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
