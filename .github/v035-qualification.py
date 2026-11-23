from hashlib import sha256
from pathlib import Path
import json
import os
import platform
import re
import shutil
import subprocess
import sys

checkout = Path.cwd()
scratch = Path(os.environ["RUNNER_TEMP"]) / "d11g-v035"
evidence = scratch / "evidence"
evidence.mkdir(parents=True)
baseline = scratch / "baseline"
candidate = scratch / "candidate"
project = Path("app/project.godot")
generator = Path("research/aero/d11g/derive_rate_derivatives.gd")
updater = Path("research/aero/d11g/apply_rate_derivatives.py")
old_hash = "087df168cefe80a55126fb571281f586f8c7189baedaf22dcd3fdfd5c6114430"
paths = ["app", "tools/godot", "tools/testqueue", "research/aero/d11g",
         "assets/aircraft/ugly-stik-60", "assets/aircraft/model-bindings.json", "research/native-kernel"]

def text(command, cwd=checkout):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()

def digest(data):
    return sha256(data).hexdigest()

def load(path):
    return json.loads(path.read_bytes())

def save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

def archive(ref, directory):
    directory.mkdir()
    with subprocess.Popen(["git", "archive", ref, *paths], stdout=subprocess.PIPE) as git:
        subprocess.run(["tar", "-xf", "-", "-C", str(directory)], stdin=git.stdout, check=True)
        assert git.wait() == 0

def replace(path, old, new):
    content = path.read_bytes()
    assert content.count(old) == 1, str(path)
    path.write_bytes(content.replace(old, new))

def checked(tree, label, timeout, args, expected):
    env = os.environ.copy()
    for key in ("DATA", "CONFIG", "CACHE"):
        env[f"XDG_{key}_HOME"] = str(scratch / "profiles" / tree.name / key.lower())
    run = subprocess.run([sys.executable, "tools/godot/run_checked.py", "--timeout", str(timeout),
                          "--out-dir", str(evidence / "checks"), "--label", label, "--",
                          str(engine), "--headless", "--path", "app", "--audio-driver", "Dummy", *args],
                         cwd=tree, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = evidence / f"{label}-generator.log"
    log.write_bytes(run.stdout)
    assert run.returncode == expected, (label, run.returncode, run.stdout[-3000:])
    checked_path, = (evidence / "checks").glob(f"{label}-*/report.json")
    report = load(checked_path)
    assert report["complete"] and report["process_exit"] == expected and report["counts"]["error"] == 0, report
    print(label, "exit", expected, flush=True)
    return report

def derive(tree, label, expected):
    target = evidence / f"{label}.json"
    verdict = checked(tree, f"d11g-{label}", 120,
                      ["--script", str(tree / generator), "--", "--json", "--check", "--report-file", str(target)], expected)
    result = subprocess.run([sys.executable, str(updater), "--report", str(target), "--check"],
                            cwd=tree, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (evidence / f"d11g-{label}-updater.log").write_bytes(result.stdout)
    assert result.returncode == expected, (label, result.stdout)
    return {"process_exit": verdict["process_exit"], "checked_log_sha256": verdict["log_sha256"],
            "report_sha256": digest(target.read_bytes()), "updater_log_sha256": digest(result.stdout)}

def compare(name, passing, expected_issues):
    left = load(evidence / "baseline.json")
    right = load(evidence / f"{name}.json")
    result = right["data_check"]
    assert result["historical_provenance"] == result["passed"] == passing, result
    assert result["issues"] == expected_issues, result
    inventories = []
    for report in (left, right):
        inventories.append(report["derivation_identity"].pop("solver_sources"))
        del report["data_check"]
    assert left == right, name
    return inventories

def inventory(tree, rows):
    normalized = {}
    for row in rows:
        relative = row["path"]
        data = (tree / relative).read_bytes()
        assert digest(data) == row["sha256"], relative
        if relative != generator.as_posix():
            normalized[relative] = digest(data.replace(b"\r\n", b"\n"))
    aggregate = digest("".join(f"{path}\t{value}\n" for path, value in sorted(normalized.items())).encode())
    return normalized, aggregate

engine = Path(text(["bash", "app/get-godot.sh"]))
assert engine.is_absolute()
baseline_commit = text(["git", "rev-parse", "refs/tags/v0.3.4^{}"])
candidate_commit = text(["git", "rev-parse", "HEAD^"])
assert candidate_commit == "2014cafbb13e2d91324ce451c712f548dc534d12"
archive(baseline_commit, baseline)
archive(candidate_commit, candidate)
replace(candidate / project, b'config/version="0.3.4"', b'config/version="0.3.5"')
assert (candidate / project).read_bytes() == subprocess.check_output(["git", "show", f"{candidate_commit}:{project.as_posix()}"]).replace(b'config/version="0.3.4"', b'config/version="0.3.5"')
checked(baseline, "import-baseline", 900, ["--import"], 0)
checks = {"baseline": derive(baseline, "baseline", 0)}
shutil.copytree(baseline / "app/.godot/imported", candidate / "app/.godot/imported")
checked(candidate, "import-candidate", 900, ["--import"], 0)
checks["candidate-before"] = derive(candidate, "candidate-before", 1)
issues = load(evidence / "candidate-before.json")["data_check"]["issues"]
assert len(issues) == 3 and all("source" in item for item in issues), issues
old, new = compare("candidate-before", False, issues)
before_sources, before_hash = inventory(baseline, old)
after_sources, after_hash = inventory(candidate, new)
assert before_hash == old_hash, before_hash
assert before_sources.keys() == after_sources.keys()
changed = {p: {"lf_sha256_before": before_sources[p], "lf_sha256_after": after_sources[p]}
           for p in before_sources if before_sources[p] != after_sources[p]}
assert list(changed) == [project.as_posix()], changed
print("Qualified project delta:", changed, flush=True)
for path in (generator, updater):
    replace(candidate / path, old_hash.encode(), after_hash.encode())
checks["renewed"] = derive(candidate, "renewed", 0)
compare("renewed", True, [])
for name, path in (("physics-mutation", Path("app/physics/aero.gd")), ("version-mutation", project)):
    target = candidate / path
    original = target.read_bytes()
    try:
        if path == project:
            replace(target, b'config/version="0.3.5"', b'config/version="0.3.5-mut"')
        else:
            target.write_bytes(original + b"\n# Disposable source mutation\n")
        checks[name] = derive(candidate, name, 1)
        compare(name, False, issues)
    finally:
        target.write_bytes(original)
checks["restored"] = derive(candidate, "restored", 0)
compare("restored", True, [])
assert (evidence / "renewed.json").read_bytes() == (evidence / "restored.json").read_bytes()

for suite in (
    "native_macos_domain_world", "scenery_build", "landscape_vegetation",
    "farm_tractor", "scenery_destruction", "scenery_loader",
    "flight_compatibility_resolution", "companion" + "s_profiles",
    "companions_behavior_manifest", "companions_shell",
):
    checked(candidate, suite, 180, ["--script", f"res://tests/test_{suite}.gd"], 0)
for suite in ("trajectory", "fleet"):
    checked(candidate, f"nk3-{suite}", 180,
            ["--script", str(candidate / f"research/native-kernel/test_{suite}.gd")], 0)
receipt = {
    "format": "openrc-d11g-source-renewal-v1",
    "date_local": "2026-11-23",
    "baseline_commit": baseline_commit,
    "candidate_commit": candidate_commit,
    "actions_run_id": int(os.environ["GITHUB_RUN_ID"]),
    "candidate_overlay": "app/project.godot config/version 0.3.4 to 0.3.5 and the two D11g inventory guard renewals",
    "platform": f"Linux {platform.machine()} on GitHub Actions Ubuntu 24.04, sequential checked imports and separate profiles",
    "engine": {"version": text([str(engine), "--version"]), "executable_sha256": digest(engine.read_bytes())},
    "inventory": {"source_counts": [len(before_sources), len(after_sources)],
                  "unchanged": len(before_sources) - len(changed),
                  "qualified_sha256_before": before_hash, "qualified_sha256_after": after_hash,
                  "added": {}, "removed": {}, "changed": changed},
    "numerical_and_provenance_result": "All six reports agree exactly outside the solver source inventory and the expected data-check result, including normalized aircraft input, trim, unrounded and rounded derivatives, sensitivity rows and generated provenance.",
    "checks": checks,
    "limits": "Software provenance on Linux. The production aircraft bytes and historical v3 source strings are unchanged."
}
save(evidence / "2026-11-23-release-v035-qualification.json", receipt)
print(after_hash, flush=True)
