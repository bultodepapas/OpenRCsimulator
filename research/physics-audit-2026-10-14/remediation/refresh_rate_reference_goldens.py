"""Record intentional D11g data-change goldens in an isolated app; never publish them."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from run_fixture_checks import digest, identity

ROOT = Path(__file__).resolve().parents[3]
TICKS = {"roll_15": 600, "pull_throttle": 720, "rudder_doublet": 720, "glide_15": 1200}
REASON = (
    "D11g: regenerate the Stik's stored Cmq, CLq and Cnr through its rate-derivative "
    "pipeline under the current R02 law; no force-law, input tape or tolerance change. "
    "Regression reference only; open R02 physical-model discrepancies remain open."
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    if app == ROOT / "app":
        parser.error("use a physically separate app copy, never the working app")
    paths = {name: app / "tests/golden" / (name + ".json") for name in TICKS}
    if any(p.stat().st_nlink != 1 for p in paths.values()):
        parser.error("golden outputs must not be hardlinked")
    out.mkdir(parents=True, exist_ok=False)
    (out / "previous").mkdir()
    (out / "generated").mkdir()
    old = {}
    for name, path in paths.items():
        shutil.copy2(path, out / "previous" / path.name)
        old[name] = json.loads(path.read_text(encoding="utf-8"))
    before = identity(app)
    context_before = {"project.godot": digest(app / "project.godot")}
    commands, changes = [], []
    error = ""

    def run(script):
        command = [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy",
                   "--script", "res://tests/" + script]
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=180)
            output, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as exc:
            output, code = exc.stdout or b"", 124
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
        (out / (script + ".log")).write_text(output, encoding="utf-8")
        errors = [s for s in output.splitlines() if s.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL"))]
        commands.append({"command": command, "exit_code": code, "errors": errors})
        print(json.dumps({"script": script, "exit_code": code, "errors": errors}), flush=True)
        if code or errors:
            raise RuntimeError(script + " failed; generated outputs are not accepted")

    try:
        run("record_golden.gd")
        for name, path in paths.items():
            new = json.loads(path.read_text(encoding="utf-8"))
            previous = old[name]
            if set(new) != set(previous):
                raise RuntimeError(name + ": record schema changed")
            allowed = {"checkpoints", "aux_checkpoints", "mode_checkpoints", "stamp"}
            for key in new.keys() - allowed:
                if new[key] != previous[key]:
                    raise RuntimeError(name + ": unexpected change to " + key)
            if new["ticks"] != TICKS[name]:
                raise RuntimeError(name + ": tick count changed")
            for key in ("checkpoints", "aux_checkpoints", "mode_checkpoints"):
                rows = new[key]
                if ([r[0] for r in rows] != [r[0] for r in previous[key]]
                        or rows[0][0] != 0 or rows[-1][0] != TICKS[name]
                        or [len(r) for r in rows] != [len(r) for r in previous[key]]):
                    raise RuntimeError(name + ": checkpoint coverage/layout changed")
            maxima = {}
            for label, first, last in (("position_m", 1, 4), ("velocity_mps", 4, 7),
                                       ("quaternion_component", 7, 11), ("rate_radps", 11, 14)):
                maxima[label] = max(abs(a[i] - b[i])
                                    for a, b in zip(previous["checkpoints"], new["checkpoints"])
                                    for i in range(first, last))
            changed_keys = sorted(k for k in new if new[k] != previous[k])
            shutil.copy2(path, out / "generated" / path.name)
            changes.append({"name": name, "before_sha256": digest(out / "previous" / path.name),
                            "after_sha256": digest(path), "changed_keys": changed_keys,
                            "unchanged_input_tape": new["inputs"] == previous["inputs"],
                            "unchanged_policy": new["policy"] == previous["policy"],
                            "ticks": new["ticks"], "body_checkpoint_component_maxima": maxima})
        run("test_golden.gd")
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        error = str(exc)
    after = identity(app)
    context_after = {"project.godot": digest(app / "project.godot")}
    drift = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
    report = {"ok": not error and not drift and context_before == context_after,
              "error": error, "reason": REASON, "source_drift": drift,
              "source_before": before, "source_after": after,
              "context_before": context_before, "context_after": context_after,
              "runner_sha256": digest(Path(__file__)), "godot_sha256": digest(godot),
              "commands": commands, "golden_changes": changes}
    (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("ok", "error", "source_drift", "golden_changes")}))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
