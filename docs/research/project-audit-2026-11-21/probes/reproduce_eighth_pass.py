#!/usr/bin/env python3
"""Reconstruct the source-pinned R8 helicopter audit in a NEW directory.

Uses real reviewed Git resources, a pinned engine and the repository checked
runner. Production source/data are never edited. Synthetic skid files change
only four physical lateral positions and their honest provenance annotation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REVIEWED_COMMIT = "c1eb426900e594c20d095120c149386305afdd4d"
ENGINE_SHA256 = "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
BASE_SHA256 = "9b9257242b8873d0045df0abf41aa13ca62dccc6b0a5a925683869152367b9be"
EXTRA_SHA256 = "66d7bba214780d484ab2b8f3cc1dfe92c033eaae2cbae496f96d75da4010236b"
PROBES = (
    ("skid-admission", "eighth_pass_skid_admission.gd", "R8 skid admission: 70 checks, 0 failed"),
    ("arming", "eighth_pass_arming.gd", "R8 final arming observations: 22 checks, 0 failures"),
    ("rotor-consistency", "eighth_pass_rotor_consistency.gd", "R8 ROTOR LEDGER: 48 checks, 0 failed"),
    ("baseline-swash", "tests/test_heli_swash.gd", "0 failed"),
    ("baseline-coupling", "tests/test_heli_coupling.gd", "0 failed"),
    ("baseline-skid-bristles", "tests/test_heli_skid_bristles.gd", "0 failed"),
    ("baseline-tail-rotor", "tests/test_heli_tail_rotor.gd", "0 failed"),
    ("baseline-main-rotor-stage", "tests/test_heli_main_rotor_stage.gd", "0 failed"),
)
ORACLE_FILES = (
    "eighth_pass_oracles.py", "eighth_pass_oracle_skid.py",
    "eighth_pass_oracle_arming.py", "eighth_pass_oracle_rotor.py",
)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def blob_sha(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()


def dump(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False)+"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    repo, engine, out = args.repo_root.resolve(), args.godot.resolve(), args.out.resolve()
    here = Path(__file__).resolve().parent
    if out.exists(): parser.error("--out must be new; previous work is never removed")
    if sha(engine.read_bytes()) != ENGINE_SHA256: parser.error("engine identity mismatch")
    base_path = here.parent/"integration-manifest.json"
    extra_path = here.parent/"eighth-pass-extra-sources.json"
    if sha(base_path.read_bytes()) != BASE_SHA256 or sha(extra_path.read_bytes()) != EXTRA_SHA256:
        parser.error("dependency manifest identity mismatch")
    base, extra = json.loads(base_path.read_text()), json.loads(extra_path.read_text())

    def git_file(path):
        return subprocess.check_output(["git", "show", REVIEWED_COMMIT+":"+path], cwd=repo)

    runner = repo/"tools/godot/run_checked.py"
    if runner.read_bytes() != git_file("tools/godot/run_checked.py"):
        raise RuntimeError("checked runner changed since reviewed source")
    out.mkdir(parents=True)
    project = out/"project"
    project.mkdir()
    sources = base["files"]+extra["extra_files"]
    assert len(sources)==extra["source_total"] and len({x["path"] for x in sources})==len(sources)
    for row in sources:
        data = git_file(row["path"])
        assert blob_sha(data)==row["git_blob_sha1"], row["path"]
        if row["checkout_bytes"]=="lf_blob_checked_out_as_crlf": data=data.replace(b"\n", b"\r\n")
        else: assert row["checkout_bytes"]=="exact"
        assert sha(data)==row["fixture_sha256"] and len(data)==row["bytes"], row["path"]
        target = project/Path(row["path"]).relative_to("app")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    settings = base["fixture_project_godot"].replace("A36 full Phoenix readers", "A36 R8 isolated helicopter research")
    (project/"project.godot").write_text(settings)
    probe_names = [p for _,p,_ in PROBES if not p.startswith("tests/")]
    for filename in probe_names: (project/filename).write_bytes((here/filename).read_bytes())
    stock_path = project/"data/aircraft/xcell_60_research.json"
    custom_inputs = []
    for y in (0.5, 1.0):
        custom = json.loads(stock_path.read_text())
        points = custom["skids"]["points_body_frd_m"]
        for index in range(1, len(points["value"]), 3):
            points["value"][index] = y if points["value"][index]>0.0 else -y
        points.update(kind="estimated", source="estimated: manufactured R8 skid numerical-admission diagnostic; not measured X-Cell geometry")
        custom_path = project/("r8_skid_"+str(y)+".json")
        dump(custom_path, custom)
        custom_inputs.append({"path":custom_path.name,"sha256":sha(custom_path.read_bytes()),
            "physical_change":"four skids.points_body_frd_m.value lateral y coordinates only, preserving signs: +/- "+str(y)+" m",
            "other_changes":["skids.points_body_frd_m.kind","skids.points_body_frd_m.source"],
            "scope":"manufactured numerical-admission geometry, not measured hardware; all other physical values preserved"})
    for name, child in (("XDG_DATA_HOME","user-data"),("XDG_CONFIG_HOME","user-config"),("XDG_CACHE_HOME","user-cache")):
        os.environ[name] = str(out/child)
    # Preserve pool/testqueue admission variables; run_checked owns scheduling.
    sys.dont_write_bytecode = True
    sys.path.insert(0,str(repo))
    from tools.godot.run_checked import run_checked
    from tools.testqueue import common, pool
    evidence = {"format":"openrc-a36-r8-evidence v1", "reviewed_commit":REVIEWED_COMMIT,
        "engine_sha256":ENGINE_SHA256,"engine_version":subprocess.check_output([str(engine),"--version"],text=True).strip(),
        "base_manifest_sha256":BASE_SHA256,"extra_manifest_sha256":EXTRA_SHA256,"source_count":len(sources),
        "checked_runner_sha256":sha(runner.read_bytes()),"fixture_project_godot":settings,"production_stubs":[],
        "execution":"Historical X-Cell GDScript reference, 240 Hz; no native or HX-700 qualification",
        "host_admission":{"pool_config_present":Path(pool.default_config()).exists(),"queue_enabled":common.enabled()},
        "stock_data_sha256":sha(stock_path.read_bytes()),"synthetic_inputs":custom_inputs,
        "probe_sha256":{n:sha((here/n).read_bytes()) for n in probe_names+[Path(__file__).name]+list(ORACLE_FILES)},
        "checks":[],"oracles":[],"ok":False}
    evidence_path = out/"evidence.json"

    def checked(label, args, required):
        result = run_checked([str(engine),"--headless","--path",str(project),"--audio-driver","Dummy"]+args,
            out/"checks",timeout=90,warnings_as_errors=True,required=required,label="a36-r8-"+label)
        evidence["checks"].append({"label":label,"report":result,"engine_log":Path(result["log"]).read_text()})
        dump(evidence_path,evidence)
        print(label+": "+result["reason"],flush=True)
        if not result["ok"] or result["counts"]!={"error":0,"warning":0}:
            raise RuntimeError("unexpected checked result; inspect "+str(evidence_path))

    checked("import",["--editor","--import"],["Godot Engine"])
    for label, filename, marker in PROBES: checked(label,["--script","res://"+filename],[marker])
    command = [sys.executable,str(here/"eighth_pass_oracles.py"),"--evidence",str(evidence_path),"--project",str(project)]
    result = subprocess.run(command,capture_output=True,text=True,check=False)
    evidence["oracles"].append({"command":command,"exit_code":result.returncode,"stdout":result.stdout,"stderr":result.stderr})
    dump(evidence_path,evidence)
    if result.returncode: raise RuntimeError("independent scalar oracles failed")
    for row in sources:
        assert sha((project/Path(row["path"]).relative_to("app")).read_bytes())==row["fixture_sha256"],row["path"]
    assert sha(stock_path.read_bytes())==evidence["stock_data_sha256"]
    for row in custom_inputs: assert sha((project/row["path"]).read_bytes())==row["sha256"]
    evidence["all_source_bytes_unchanged_after_execution"] = True
    evidence["ok"] = True
    dump(evidence_path,evidence)
    print("R8_REPRODUCTION_COMPLETE "+str(evidence_path),flush=True)


if __name__=="__main__": main()
