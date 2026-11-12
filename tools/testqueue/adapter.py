"""Execute one reviewed preset inside an owned attempt. No shell command endpoint."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.testqueue.common import inherited, write_json


def prepare_history(preset, directory, request):
    """Preparation subprocesses also inherit the attempt's process containment."""
    if ROOT != directory.resolve() / "source":
        raise ValueError("adapter source must be inside its owned attempt directory")
    if preset in {"suite", "ci", "godtest", "capture"}:
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
        if preset in {"debug-session", "debug-smoke", "checked", "godtest"}:
            from tools.godot.run_checked import run_checked
            manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
            if not manifest.get("import_files") or "--import" in options["argv"]:
                imported = run_checked([os.environ["OPENRC_GODOT"], "--headless", "--path", str(ROOT / "app"),
                                        "--audio-driver", "Dummy", "--import"], directory / "imports", timeout=600)
                if not imported["ok"]:
                    verdict.update(ok=False, complete=True, import_verdict=imported)
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
            verdict.update(ok=result["ok"], complete=True, checked=result)
            code = 0 if result["ok"] else 1
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
            complete, evidence_ok, evidence = validate_evidence(preset, directory, ROOT)
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


def validate_evidence(preset, directory, root):
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
    if preset in {"suite", "ci"}:
        reports = []
        for path in (directory / "checks").rglob("*.json"):
            item = json.loads(path.read_text())
            if item.get("format") == "openrc-godot-check v1":
                reports.append(item)
        complete = complete and bool(reports)
        ok = ok and all(item.get("ok") is True and item.get("complete") is True for item in reports)
    return complete, ok, result


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1]).resolve()))
