"""Execute one reviewed preset inside an owned attempt. No shell command endpoint."""
from __future__ import annotations

import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import shutil
import sys
import time
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.testqueue.common import inherited, write_json


def prepare_history(preset, directory, request):
    """Preparation subprocesses also inherit the attempt's process containment."""
    if ROOT != directory.resolve() / "source":
        raise ValueError("adapter source must be inside its owned attempt directory")
    if preset in {"suite", "ci", "godtest", "capture", "aircraft-screenshot"}:
        if (ROOT / ".git").exists() or (ROOT / ".git").is_symlink():
            raise ValueError("history destination must be new inside the owned attempt")
        history = directory / "history"
        subprocess.run(["git", "clone", "--no-checkout", "--no-hardlinks", request["source"], str(history)],
                       check=True, capture_output=True, timeout=300)
        shutil.move(str(history / ".git"), str(ROOT / ".git"))
        subprocess.run(["git", "reset", "--mixed", request["manifest"]["commit"]], cwd=ROOT,
                       check=True, capture_output=True, timeout=60)
    elif preset == "landscape":
        subprocess.run(["git", "init", "-q", str(ROOT)], check=True, capture_output=True, timeout=30)


def main(directory: Path) -> int:
    request = json.loads((directory / "request.json").read_text(encoding="utf-8"))
    preset, options = request["preset"], request["options"]
    if not inherited("headless" if options["headless"] else "rendered"):
        raise ValueError("attempt capability required")
    verdict = {"ok": False, "complete": False, "preset": preset}
    code = 2
    try:
        prepare_history(preset, directory, request)
        if preset in {"debug-session", "debug-smoke", "checked", "godtest", "aircraft-screenshot"}:
            from tools.godot.run_checked import run_checked
            manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
            if not manifest.get("import_files") or "--import" in options["argv"]:
                imported = run_checked([os.environ["OPENRC_GODOT"], "--headless", "--path", str(ROOT / "app"),
                                        "--audio-driver", "Dummy", "--import"], directory / "imports", timeout=600)
                if (imported.get("ok") is not True or
                        preset == "checked" and imported.get("complete") is not True):
                    # The requested checked test did not run. Preserve the
                    # import report without presenting it as a complete check.
                    verdict.update(ok=False, complete=preset != "checked", import_verdict=imported)
                    code = 1
                    return code
                options["argv"] = [arg for arg in options["argv"] if arg != "--import"]
        if preset in {"debug-session", "debug-smoke"}:
            spec = importlib.util.spec_from_file_location("admitted_debugctl", ROOT / "tools/debug/debugctl.py")
            bridge = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(bridge)
            bridge.RUNS = directory / "debug"
            bridge.SESSIONS = bridge.RUNS / "sessions"
            bridge.CURRENT = bridge.RUNS / "current.json"
            argv = list(options["argv"])
            if preset == "debug-session":
                code = bridge.launch(["--out", str(directory / "debug-session"), "--profile", str(directory / "profile"), *argv])
                if code == 0:
                    session = bridge.current_session()
                    write_json(directory / "ready.json", session)
                    while bridge.alive(session.get("pid")) or bridge.alive(session.get("launcher_pid")):
                        time.sleep(0.1)
                    diagnostics = bridge.exit_report(Path(session["out"]) / "engine.log")
                    verdict["diagnostics"] = diagnostics
                    from tools.godot.run_checked import inspect_log
                    log = inspect_log(Path(session["out"]) / "engine.log", [])
                    owned = bridge._OWNED_PROCESSES.get(session.get("launcher_pid"))
                    engine_code = owned.poll() if owned is not None else None
                    code = 1 if log["counts"]["error"] or diagnostics.get("crash") or engine_code not in (None, 0) else 0
            else:
                code = bridge.smoke(argv)
            verdict.update(ok=code == 0, complete=True)
        elif preset == "checked":
            from tools.godot.run_checked import run_checked
            command = [os.environ["OPENRC_GODOT"], "--path", str(ROOT / "app"), "--audio-driver", "Dummy"]
            if options["headless"]:
                command.append("--headless")
            else:
                command += ["--resolution", "1920x1080"]
            command += ["--script", options["script"]]
            result = run_checked(command, directory / "checks", timeout=options["timeout"] - 0.5,
                                 required=options["require"], **options.get("settings", {}))
            complete = result.get("complete") is True and type(result.get("ok")) is bool
            ok = complete and result["ok"] is True
            verdict.update(ok=ok, complete=complete, checked=result)
            code = 0 if ok else 1
        elif preset == "aircraft-screenshot":
            from tools.godot.run_checked import run_checked
            command = [os.environ["OPENRC_GODOT"], "--path", str(ROOT / "app"),
                       "--audio-driver", "Dummy", "--rendering-driver", "opengl3",
                       "--resolution", "1920x1080", "--script", str(ROOT / "tools/readme/capture_aircraft.gd"),
                       "--", "--stills-only", "--aircraft=" + options["aircraft"],
                       "--out-dir=" + str(directory / "screenshots")]
            result = run_checked(command, directory / "checks", timeout=options["timeout"] - 0.5,
                                 required=["README_RENDER_OK: 1 vehicles, 0 animation frames"],
                                 label="aircraft-screenshot")
            verdict["checked"] = result
            if result.get("ok") is not True or result.get("complete") is not True:
                verdict["complete"] = result.get("complete") is True
                code = 1
            else:
                evidence = validate_screenshot(directory, ROOT, options["aircraft"], request["manifest"]["commit"])
                verdict.update(ok=True, complete=True, evidence=evidence)
                code = 0
        else:
            scripts = {"godtest": [sys.executable, str(ROOT / "tools/godtest/godtest.py")],
                       "suite": ["bash", str(ROOT / "app/test.sh")],
                       "capture": ["bash", str(ROOT / "app/capture.sh")],
                       "landscape": ["bash", str(ROOT / "app/run-landscape.sh")],
                       "ci": ["bash", str(ROOT / "tools/ci/check-local.sh")]}
            command = [*scripts[preset], *options["argv"]]
            if preset == "capture" and options["argv"]:
                command += ["--out", str(directory / "captures"), "--run-id", directory.name]
            if preset == "godtest":
                command += ["--godot", os.environ["OPENRC_GODOT"], "--out", str(directory / "godtest")]
            code = subprocess.call(command, cwd=ROOT)
            complete, evidence_ok, evidence = validate_evidence(preset, directory, ROOT, options)
            verdict.update(ok=code == 0 and evidence_ok, complete=complete, evidence=evidence)
            if code == 0 and complete and not evidence_ok:
                code = 1
    except Exception as error:
        verdict["error"] = str(error)
        verdict["underlying_exit_code"] = code
        code = 2
        print(f"testqueue adapter: {error}", file=sys.stderr)
    finally:
        write_json(directory / "verdict.json", verdict)
    return code


def validate_screenshot(directory, root, aircraft, expected_commit):
    """Validate the still and its source-bound manifest without an image dependency."""
    if not isinstance(aircraft, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", aircraft):
        raise ValueError("invalid screenshot aircraft ID")
    folder = directory / "screenshots"
    if folder.is_symlink() or folder.resolve().parent != directory.resolve():
        raise ValueError("screenshot directory must belong to the attempt")
    manifest_path = folder / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError("screenshot manifest missing or linked")
    if manifest_path.stat().st_size > 1024 * 1024:
        raise ValueError("screenshot manifest too large")
    raw_manifest = manifest_path.read_bytes()
    if len(raw_manifest) > 1024 * 1024:
        raise ValueError("screenshot manifest too large")
    manifest = json.loads(raw_manifest)
    if not isinstance(manifest, dict):
        raise ValueError("invalid screenshot manifest")
    source = manifest.get("source_start")
    if (manifest.get("format") != "openrc-readme-renders v2"
            or not isinstance(source, dict) or not source or source != manifest.get("source_end")
            or manifest.get("source_changed_during_capture") is not False
            or not isinstance(expected_commit, str) or not re.fullmatch(r"[0-9a-f]{40,64}", expected_commit)
            or source.get("commit") != expected_commit
            or source.get("capture_tool_sha256") != hashlib.sha256((root / "tools/readme/capture_aircraft.gd").read_bytes()).hexdigest()
            or manifest.get("stills_size") != [1920, 1080]
            or type(manifest.get("frame_count")) is not int or manifest["frame_count"] != 0):
        raise ValueError("invalid screenshot source identity or manifest")
    vehicles = manifest.get("vehicles")
    if not isinstance(vehicles, list) or len(vehicles) != 1 or not isinstance(vehicles[0], dict):
        raise ValueError("screenshot manifest must contain one vehicle")
    vehicle = vehicles[0]
    if (vehicle.get("id") != aircraft or vehicle.get("still") != aircraft + ".png"
            or type(vehicle.get("frames")) is not int or vehicle["frames"] != 0):
        raise ValueError("screenshot vehicle, still path or frame count differs")
    still = folder / vehicle["still"]
    if still.is_symlink() or still.resolve().parent != folder.resolve() or not still.is_file():
        raise ValueError("screenshot still missing or linked")
    if still.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("screenshot PNG too large")
    image = still.read_bytes()
    if len(image) > 64 * 1024 * 1024:
        raise ValueError("screenshot PNG too large")
    digest = hashlib.sha256(image).hexdigest()
    if digest != vehicle.get("still_sha256"):
        raise ValueError("screenshot checksum differs")
    _validate_png(image)
    return {"manifest": str(manifest_path), "manifest_sha256": hashlib.sha256(raw_manifest).hexdigest(),
            "still": str(still), "still_sha256": digest, "size": [1920, 1080], "aircraft": aircraft,
            "source_commit": expected_commit}


def _validate_png(data):
    """Check PNG chunks, CRCs and bounded 8-bit RGB/RGBA scanlines."""
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("screenshot is not a PNG")
    position, chunks, header, ended = 8, [], None, False
    while position + 12 <= len(data):
        length = struct.unpack_from(">I", data, position)[0]
        end = position + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk")
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        checksum = struct.unpack_from(">I", data, position + 8 + length)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != checksum:
            raise ValueError("PNG chunk checksum differs")
        if header is None:
            if kind != b"IHDR" or length != 13:
                raise ValueError("invalid PNG header")
            header = struct.unpack(">IIBBBBB", payload)
            if header[:2] != (1920, 1080) or header[2:] not in ((8, 2, 0, 0, 0), (8, 6, 0, 0, 0)):
                raise ValueError("unexpected PNG dimensions or pixel format")
        elif kind == b"IHDR":
            raise ValueError("duplicate PNG header")
        if kind == b"IDAT":
            chunks.append(payload)
        if kind == b"IEND":
            if length or end != len(data):
                raise ValueError("invalid PNG end")
            ended = True
            break
        position = end
    if not ended or not chunks:
        raise ValueError("incomplete PNG")
    stride = 1920 * (3 if header[3] == 2 else 4) + 1
    expected = stride * 1080
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(b"".join(chunks), expected + 1)
    if (len(pixels) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail
            or any(pixels[offset] > 4 for offset in range(0, expected, stride))):
        raise ValueError("invalid PNG image data")


def validate_evidence(preset, directory, root, options=None):
    """Success requires the owning runner's receipts, not merely exit status zero."""
    if preset == "godtest":
        sys.path.insert(0, str(root / "tools/godtest"))
        from analysis import report
        suite = directory / "godtest/suite.json"
        if suite.exists():
            receipt = json.loads(suite.read_text())
            cases = receipt.get("cases", [])
            complete = receipt.get("complete") is True and bool(cases)
            observed = []
            for case in cases:
                path = Path(case.get("run_dir", "")).resolve()
                if (directory / "godtest").resolve() not in path.parents or not (path / "execution.json").is_file():
                    return False, False, {"missing": "GOD TEST case artifacts"}
                observed.append(report(path))
            complete = complete and all(case.get("coverage") == "complete" for case in observed)
            ok = complete and all(case.get("data") == "valid" for case in observed)
            return complete, ok, {"suite": str(suite), "cases": len(cases)}
        if not (directory / "godtest/execution.json").exists():
            return False, False, {"missing": "GOD TEST execution.json or suite.json"}
        result = report(directory / "godtest")
        return result["coverage"] == "complete", result["data"] == "valid", result
    receipt = directory / "shell-receipt.json"
    if not receipt.exists():
        return False, False, {"missing": "shell completion receipt"}
    result = json.loads(receipt.read_text())
    complete = result.get("preset") == preset and result.get("complete") is True
    ok = result.get("exit_code") == 0
    if preset == "capture":
        full = root / "app/captures/run-manifest.json"
        partial = directory / "captures/capture-group-receipt.json"
        if full.exists():
            manifest = json.loads(full.read_text())
            captures = manifest.get("captures", [])
            complete = complete and manifest.get("format") == "openrc-capture-set v1" and manifest.get("complete") is True and bool(captures)
            def matches(relative, expected):
                path = (full.parent / relative).resolve()
                if full.parent.resolve() not in path.parents or not path.is_file():
                    return False
                import hashlib
                return hashlib.sha256(path.read_bytes()).hexdigest() == expected
            ok = ok and all(matches(item["image"], item["sha256"]) and matches(str(Path(item["image"]).with_suffix(".json")), item["manifest_sha256"]) for item in captures)
            ok = ok and matches("trace-physics.csv", manifest.get("trace_sha256"))
            for name, checksum in manifest.items():
                if name.endswith("_sha256") and name != "trace_sha256":
                    ok = ok and matches(manifest.get(name[:-7], ""), checksum)
        elif partial.exists():
            manifest = json.loads(partial.read_text())
            complete = complete and manifest.get("format") == "openrc-experimental-capture-group v1" and manifest.get("status") == "passed" and bool(manifest.get("outputs"))
            sys.path.insert(0, str(root / "tools/ci"))
            from capture_groups import verify_outputs
            ok = ok and manifest["outputs"] == verify_outputs(partial.parent, manifest["start"]["group"])
        else:
            complete = False
    if preset == "ci":
        argv = options.get("argv") if isinstance(options, dict) else None
        if argv not in ([], ["quick"], ["full"], ["release"]):
            return False, False, {"missing": "valid local CI mode"}
        result = {**result, "mode": argv[0] if argv else "quick"}
    if preset == "suite" or (preset == "ci" and result["mode"] != "quick"):
        reports = []
        for path in (directory / "checks").rglob("*.json"):
            item = json.loads(path.read_text())
            if item.get("format") == "openrc-godot-check v1":
                reports.append(item)
        required_labels = {"local-resource-import", "nk3-trajectory-policy", "nk3-fleet-policy"} if preset == "ci" else set()
        labels = {item.get("label") for item in reports}
        complete = complete and bool(reports) and required_labels.issubset(labels)
        ok = ok and all(item.get("ok") is True and item.get("complete") is True for item in reports)
        result.update(checked_reports=len(reports), missing_labels=sorted(required_labels - labels))
    return complete, ok, result


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1]).resolve()))
