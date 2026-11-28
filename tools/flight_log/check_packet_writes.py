"""Check all three ORFL recorders on Linux with real buffered and oversized failed writes.

Run on an imported project with --godot <pinned-editor>. Only the limited engine
child receives RLIMIT_FSIZE; checked logs and receipts stay outside that limit.
On enrolled hosts run inside the admitted Linux integration suite.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.godot.run_checked import run_checked
from tools.testqueue.common import enabled

PROBE = "tests/probe_orfl_packet_write_error.gd"
SOURCES = (PROBE, "sim/orfl_packet.gd", "sim/flight_log.gd", "sim/airship/flight_log.gd",
           "sim/multirotor/flight_log.gd")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=ROOT / "app")
    parser.add_argument("--out", type=Path, default=ROOT / "tmp" / "orfl-write-checks")
    args = parser.parse_args()
    if sys.platform != "linux":
        print("Unsupported: ORFL file-size fault injection requires Linux.", file=sys.stderr)
        return 2
    if enabled() and not os.environ.get("OPENRC_TESTQUEUE_CONTEXT"):
        print("Run this check through the admitted Linux integration suite on an enrolled host.", file=sys.stderr)
        return 2
    app = args.project.resolve()
    engine = args.godot.resolve(strict=True)
    checks = args.out.resolve()
    checks.mkdir(parents=True, exist_ok=True)
    evidence_root = checks.with_name(checks.name + "-orfl-evidence")
    evidence_root.mkdir(exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix="orfl-", dir=evidence_root))
    manifest = {"engine": str(engine), "engine_sha256": digest(engine), "project": str(app),
                "source_sha256": {name: digest(app / name) for name in SOURCES},
                "driver_sha256": digest(Path(__file__)), "checks": {}}
    for mode in ("control", "limited"):
        command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(app),
                   "--script", "res://" + PROBE, "--", mode, str(evidence)]
        if mode == "limited":
            command = [sys.executable, str(Path(__file__).resolve()), "--limit-child", *command]
        result = run_checked(command, checks, label=f"orfl-{mode}", warnings_as_errors=True, timeout=90,
                             required=[f"ORFL write probe {mode}: 0 failures"])
        manifest["checks"][mode] = {"ok": result["ok"], "report": result["report"]}
        print(f"{mode}: {result['reason']} ({result['report']})", flush=True)
    print(f"Source hashes and recordings: {evidence}")
    (evidence / "summary.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0 if all(r["ok"] for r in manifest["checks"].values()) else 1


if __name__ == "__main__":
    if sys.argv[1:2] == ["--limit-child"]:
        import resource
        import signal
        resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
        os.execv(sys.argv[2], sys.argv[2:])
    sys.exit(main())
