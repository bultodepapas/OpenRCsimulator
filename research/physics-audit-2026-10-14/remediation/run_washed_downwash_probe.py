"""Record the read-only powered-tail zero-freestream counterexample and its identity."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(app):
    paths = set(app.rglob("*.gd")) | set((app / "data").rglob("*.json"))
    return {p.relative_to(app).as_posix(): sha(p) for p in sorted(paths)
            if ".godot" not in p.parts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    probe = Path(__file__).with_name("washed_downwash_limit_probe.gd").resolve()
    before = identity(app)
    command = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy",
               "--script", str(probe), "--", "--out=" + str(out / "loads.json")]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=60)
        log, exit_code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as exc:
        log = exc.stdout or b""
        if isinstance(log, bytes):
            log = log.decode("utf-8", errors="replace")
        exit_code = 124
    (out / "probe.log").write_text(log, encoding="utf-8")
    after = identity(app)
    drift = [p for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
    errors = [line for line in log.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
    receipt = {"command": command, "exit_code": exit_code, "engine_errors": errors,
               "source_drift": drift, "source_before": before, "source_after": after,
               "probe_sha256": sha(probe), "runner_sha256": sha(Path(__file__)),
               "godot_sha256": sha(godot)}
    receipt["ok"] = exit_code == 0 and not errors and not drift and (out / "loads.json").is_file()
    (out / "identity.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(log, end="")
    print(json.dumps({k: v for k, v in receipt.items() if k not in ("source_before", "source_after")}))
    return 0 if receipt["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
