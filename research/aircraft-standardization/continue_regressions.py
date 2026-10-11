"""Continue the official suite after a recorded failure without hiding later failures.

Diagnostic evidence only: leaves app/test.sh and every test unchanged. Run with
Linux Python against an isolated complete repository after app/test.sh imported
and parsed it. Each remaining test/official tail section is a separate process.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time


ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:|^FAIL(?:\b|:)", re.MULTILINE)


def manifest(repo: Path) -> dict[str, str]:
    return {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((repo / "app").rglob("*"))
            if p.is_file() and not {".godot", "captures"}.intersection(p.parts)
            and p.suffix not in {".uid", ".import"}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--after",
                        help="Last test already attempted by official app/test.sh")
    parser.add_argument("--tail-only", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    repo, godot, out = args.repo.resolve(), args.godot.resolve(), args.out.resolve()
    script = (repo / "app/test.sh").read_text(encoding="utf-8")
    tests = sorted((repo / "app/tests").glob("test_*.gd"))
    if not args.tail_only and args.after not in {p.name for p in tests}:
        parser.error("--after must name an existing test in this snapshot")
    tests = [] if args.tail_only else [p for p in tests if p.name > args.after]
    # This is the exact official tail after the GDScript loop; each top-level
    # heading already denotes one independent check, with all its local state.
    tail = script[script.index('echo "== H7:'):]
    sections = re.split(r'(?=^echo "== )', tail, flags=re.MULTILINE)
    sections = [s for s in sections if s.strip()]
    jobs = [(p.name, [str(godot), "--headless", "--path", str(repo / "app"),
                      "--audio-driver", "Dummy", "--script", "res://tests/" + p.name], 90)
            for p in tests]
    common = "\n".join([
        "set -euo pipefail", "HERE=" + shlex.quote(str(repo / "app")),
        "GODOT=" + shlex.quote(str(godot)),
        'run() { timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }',
        'LOG="$(mktemp)"; trap \'rm -f "$LOG"\' EXIT', "",
    ])
    for index, section in enumerate(sections, 1):
        title = section.splitlines()[0].removeprefix('echo "== ').removesuffix('"')
        jobs.append((f"tail-{index:02d}: {title}", ["bash", "-c", common + section], 360))
    if args.list:
        print("\n".join(name for name, _, _ in jobs))
        return 0
    out.mkdir(parents=True, exist_ok=False)
    before = manifest(repo)
    records = []
    env = os.environ.copy()
    env["OPENRC_TEST_GODOT"] = str(godot)
    env["XDG_DATA_HOME"] = str(repo / ".tools" / "as-regression-userdata")
    for index, (name, command, timeout) in enumerate(jobs, 1):
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=repo, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=timeout)
            text = result.stdout.decode("utf-8", errors="replace")
            code = result.returncode
        except subprocess.TimeoutExpired as error:
            text = (error.stdout or b"").decode("utf-8", errors="replace") + "\nTIMEOUT\n"
            code = 124
        log_name = f"{index:03d}-" + re.sub(r"[^a-zA-Z0-9_.-]+", "-", name)[:100] + ".log"
        (out / log_name).write_text(text, encoding="utf-8")
        errors = ERROR.findall(text)
        record = {"name": name, "ok": code == 0 and not errors, "exit_code": code,
                  "engine_or_assertion_errors": len(errors), "log": log_name,
                  "seconds": round(time.monotonic() - start, 3)}
        records.append(record)
        print(f"{index}/{len(jobs)} {'PASS' if record['ok'] else 'FAIL'} {name}", flush=True)
        (out / "progress.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    after = manifest(repo)
    stable = before == after
    report = {"method": __doc__, "repo": str(repo), "godot": str(godot),
              "engine_sha256": hashlib.sha256(godot.read_bytes()).hexdigest(),
              "official_script_sha256": hashlib.sha256(script.encode()).hexdigest(),
              "after_test": args.after, "source_stable": stable,
              "passed": sum(r["ok"] for r in records), "failed": sum(not r["ok"] for r in records),
              "results": records, "source_before": before, "source_after": after}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return int(not stable or any(not r["ok"] for r in records))


if __name__ == "__main__":
    raise SystemExit(main())
