"""Exercise the D11g CI gate and stale-output controls in a disposable source copy."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--copy-root", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    source = args.source_root.resolve(strict=True)
    engine = args.godot.resolve(strict=True)
    copied = args.copy_root.resolve()
    out = args.out.resolve()
    if copied.exists() or out.exists():
        raise ValueError("copy and evidence destinations must both be new")
    if source == copied or source.is_relative_to(copied):
        raise ValueError("copy must not contain the source workspace")
    out.mkdir(parents=True)
    copied.mkdir(parents=True)
    generator = "research/aero/d11g/derive_rate_derivatives.gd"
    target_rel = "app/data/aircraft/jensen_ugly_stik_60.json"
    paths = sorted({
        *(p.relative_to(source).as_posix() for p in (source / "app").rglob("*.gd")
          if ".godot" not in p.parts),
        *(p.relative_to(source).as_posix() for p in (source / "app/data").rglob("*.json")),
        "app/project.godot", "app/test.sh", "app/i18n/es.po", generator,
    })
    manifest = {}
    for rel in paths:
        raw = (source / rel).read_bytes()
        destination = copied / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
        manifest[rel] = hashlib.sha256(raw).hexdigest()
        if destination.stat().st_nlink != 1:
            raise ValueError(f"physical copy required: {rel}")
    target = copied / target_rel
    original = target.read_bytes()
    rows = []
    try:
        for case in ("current", "stale_value", "stale_provenance"):
            target.write_bytes(original)
            if case != "current":
                data = json.loads(original)
                coefficient = data["aero"]["coefficients"]["Cmq"]
                if case == "stale_value":
                    coefficient["value"] *= 1.01
                else:
                    coefficient["source"] = "deliberate stale provenance negative control"
                target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            report_path = out / f"{case}.json"
            command = [str(engine), "--headless", "--path", str(copied / "app"),
                       "--audio-driver", "Dummy", "--script", str(copied / generator),
                       "--", "--json", "--check", "--report-file", str(report_path)]
            started = time.monotonic()
            with (out / f"{case}.log").open("wb") as log:
                result = subprocess.run(command, cwd=copied, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=60, check=False)
            elapsed = time.monotonic() - started
            report = json.loads(report_path.read_text(encoding="utf-8"))
            issues = report.get("data_check", {}).get("issues", [])
            passed = report.get("data_check", {}).get("passed")
            expected_exit = 0 if case == "current" else 1
            log_text = (out / f"{case}.log").read_text(encoding="utf-8", errors="replace")
            ok = (result.returncode == expected_exit and passed is (case == "current")
                  and (not issues if case == "current" else len(issues) == 1 and "Cmq" in issues[0])
                  and "SCRIPT ERROR:" not in log_text and "ERROR:" not in log_text)
            rows.append({"case": case, "command": command, "exit": result.returncode,
                         "expected_exit": expected_exit, "elapsed_s": elapsed, "ok": ok,
                         "input_sha256": digest(target), "report_sha256": digest(report_path),
                         "log_sha256": digest(out / f"{case}.log"), "issues": issues})
            print(f"{case}: exit={result.returncode}, check_passed={passed}, verified={ok}", flush=True)
    finally:
        target.write_bytes(original)
    source_drift = [rel for rel, expected in manifest.items() if digest(source / rel) != expected]
    copy_drift = [rel for rel, expected in manifest.items() if digest(copied / rel) != expected]
    receipt = {"format": "openrc-d11g-ci-gate-verification-v1", "source_root": str(source),
               "copy_root": str(copied), "engine": str(engine), "engine_sha256": digest(engine),
               "runner_sha256": digest(Path(__file__)), "manifest": manifest,
               "source_drift": source_drift, "restored_copy_drift": copy_drift, "runs": rows,
               "ok": len(rows) == 3 and all(row["ok"] for row in rows) and not source_drift and not copy_drift}
    (out / "verification.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return 0 if receipt["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
