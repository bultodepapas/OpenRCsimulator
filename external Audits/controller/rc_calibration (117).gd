{
  "format": "openrc-godot-check v1",
  "capture_id": "5dad9124-c558-4b35-9698-2f33a3ea0f0b",
  "command": [
    "/workspace/scratch/912e78c5574d/repo_current/.tools/Godot_v4.8-beta2_linux.x86_64",
    "--headless",
    "--path",
    "/workspace/scratch/a1128d42a6f8/evidence/profiles/repro",
    "--audio-driver",
    "Dummy",
    "--script",
    "res://inspect_store.gd"
  ],
  "cwd": "/workspace/scratch/a1128d42a6f8/openrc-audit",
  "started_utc": "2026-11-14T15:04:10.918355+00:00",
  "label": "race-final-store",
  "log": "/workspace/scratch/a1128d42a6f8/evidence/profiles/checks/race-final-store-2eo9smvp/engine.log",
  "report": "/workspace/scratch/a1128d42a6f8/evidence/profiles/checks/race-final-store-2eo9smvp/report.json",
  "timeout_seconds": 30.0,
  "max_log_bytes": 8388608,
  "warnings_as_errors": false,
  "required_text": [
    "FINAL_STORE names=[\"Writer B\"] ok=true"
  ],
  "process_exit": 0,
  "complete": true,
  "counts": {
    "error": 0,
    "warning": 0
  },
  "diagnostics": [],
  "missing_required_text": [],
  "reason": "passed",
  "detail": "",
  "exit_code": 0,
  "ok": true,
  "elapsed_seconds": 0.463674,
  "log_bytes": 109,
  "log_sha256": "10c9edefa50ca44d6f31398ac813f37dbbcea159f4fc87aad2c7f9f3c0153043"
}
