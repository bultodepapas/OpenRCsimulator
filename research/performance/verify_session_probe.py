"""Exercise the real Godot probe, including disposable pause/input observer mutations."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from session_baseline import ENGINE_ERROR_RE, reduce_pair, validate_probe_report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    probe = Path(__file__).with_name("session_probe.gd")
    source = probe.read_text(encoding="utf-8")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    engine = args.godot.resolve()
    results = []
    reports = {}
    with tempfile.TemporaryDirectory(prefix="openrc-probe-mutations-") as temporary:
        for name, edit, observer in (
            ("control-on", "", "on"), ("control-off", "", "off"),
            ("paused", "_session.sim.set_paused(true)", "on"),
            ("input-disabled", "_session.input_enabled = false", "on"),
            ("stopped", "_session.sim.stop_at_tick = 0", "on"),
            ("altered-observer", "altered-observer", "on"),
        ):
            script = probe
            if edit:
                mutated = source
                if edit == "altered-observer":
                    needle = "\t\tvar middle: int = Time.get_ticks_usec()"
                    mutated = mutated.replace(needle, "\t\t_session.sim.inputs[0] += 0.1\n" + needle, 1)
                else:
                    mutated = mutated.replace("\tif _prepare():\n", "\tif _prepare():\n\t\t" + edit + "\n", 1)
                if mutated == source:
                    raise RuntimeError("mutation seam changed; review this verification tool")
                script = Path(temporary) / (name + ".gd")
                script.write_text(mutated, encoding="utf-8")
            path = out / (name + ".json")
            command = [str(engine), "--headless", "--path", str(root / "app"),
                       "--script", str(script), "--", f"--output={path}",
                       "--warmup-ticks=0", "--sample-ticks=8", f"--observer={observer}"]
            run = subprocess.run(command, capture_output=True, timeout=120)
            log = run.stdout + run.stderr
            (out / (name + ".log")).write_bytes(log)
            report = json.loads(path.read_text(encoding="utf-8"))
            reports[name] = report
            expected_success = name in ("control-on", "control-off", "altered-observer")
            passed = ((run.returncode == 0) == expected_success
                      and report.get("complete") is expected_success
                      and not ENGINE_ERROR_RE.search(log.decode("utf-8", errors="replace"))
                      and not validate_probe_report(report, allow_incomplete=not expected_success))
            results.append({"case": name, "passed": passed, "exit_code": run.returncode,
                            "failure": report.get("failure"), "command": command,
                            "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest()})
    for name, left, right, expected in (
        ("unchanged-observer-parity", "control-on", "control-off", True),
        ("altered-observer-rejected", "altered-observer", "control-off", False),
    ):
        reduced = reduce_pair(reports[left], reports[right])
        results.append({"case": name, "passed": reduced["comparable"] is expected,
                        "pair": reduced})
    complete = all(case["passed"] for case in results)
    (out / "verification.json").write_text(json.dumps({
        "format": "openrc-session-probe-verification v1", "complete": complete,
        "probe_sha256": hashlib.sha256(probe.read_bytes()).hexdigest(), "cases": results,
        "scope": "Disposable external scripts only; no runtime or golden mutation. Software guard checks, not performance samples.",
    }, indent=2) + "\n", encoding="utf-8")
    print(f"session probe verification: {sum(c['passed'] for c in results)}/{len(results)} passed")
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
