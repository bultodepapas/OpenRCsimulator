#!/usr/bin/env python3
"""Reject adapter-output/sign/transport faults in a disposable native experiment."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location("smooth_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    changes = [
        ("zero returned native loads", "\t\treturn result\n",
         "\t\treturn PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])\n"),
        ("reverse native roll moment", "\t\treturn result\n", "\t\tresult[3] = -result[3]\n\t\treturn result\n"),
        ("discard stopped residual", "fade = 1.0 if velocity[0] >= 0.0 else 0.0", "fade = 0.0"),
        ("discard transported axial increments", "resolved_downwash, transported_dv)",
         "resolved_downwash, PackedFloat64Array())"),
    ]
    records = []
    with tempfile.TemporaryDirectory(prefix="openrc-smooth-mutants-") as temp:
        project = Path(temp) / "app"
        runner._copy_project(args.project, project)
        probe = runner._install_probe(project, args.library.resolve())
        adapter = probe / "adapter.gd"
        original = adapter.read_text()
        for label, old, new in changes:
            if original.count(old) != 1:
                raise RuntimeError(f"Mutation anchor changed: {label}")
            adapter.write_text(original.replace(old, new))
            result = subprocess.run([runner._resolve_godot(args.godot), "--headless", "--path", str(project),
                                     "--script", str(probe / "verify.gd"), "--", str(Path(temp) / "report.json")],
                                    text=True, capture_output=True, timeout=60)
            output = result.stdout + result.stderr
            if result.returncode != 1 or runner.ERROR_RE.search(output) or not re.search(r"(?m)^FAIL ", output):
                raise RuntimeError(f"Mutation did not fail through assertions: {label}\n{output}")
            records.append({"mutation": label, "exit_code": result.returncode,
                            "assertion_failures": [line for line in output.splitlines() if line.startswith("FAIL ")]})
            print("rejected:", label)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"scope": "adapter mutations; original native binary unchanged",
                                     "rejected": records}, indent=2) + "\n")


if __name__ == "__main__":
    main()
