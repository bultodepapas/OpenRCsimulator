from pathlib import Path
import hashlib, json, subprocess, time
r = Path.cwd()
w = r / "tmp/perf-pass2-20261019"
out = w / "verification"
out.mkdir(exist_ok=True)
engine = r / ".tools/Godot_v4.7.2-stable_win64.exe"
tests = ["test_ground_stage_queries", "test_wheel_session", "test_ground_contact", "test_ground_stiction",
    "test_retractable_gear_ground", "test_p51_ground", "test_timber_ground", "test_liquid_fuel_session",
    "test_glow_session", "test_lake_ground_contact", "test_lake_session", "test_checkpoint",
    "test_checkpoint_integrity", "test_simulation", "test_ground_start_integrity", "test_golden"]
ledger = []
for name in tests:
    command = [str(engine), "--headless", "--path", str(r / "app"), "--audio-driver", "Dummy",
        "--script", "res://tests/" + name + ".gd"]
    start = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True, timeout=600)
    log = result.stdout + result.stderr
    (out / (name + ".log")).write_text(log, encoding="utf-8")
    row = {"test": name, "command": command, "exit_code": result.returncode,
        "ok": result.returncode == 0 and "ERROR:" not in log and "FAIL" not in log,
        "elapsed_seconds": time.monotonic() - start,
        "test_sha256": hashlib.sha256((r / "app/tests" / (name + ".gd")).read_bytes()).hexdigest()}
    ledger.append(row)
    (out / "results.json").write_text(json.dumps(ledger, indent=2))
    print(name, "PASS" if row["ok"] else "FAIL", round(row["elapsed_seconds"], 1), log[-180:].strip(), flush=True)
raise SystemExit(0 if all(x["ok"] for x in ledger) else 1)
