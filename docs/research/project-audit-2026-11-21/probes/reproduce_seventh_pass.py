#!/usr/bin/env python3
"""Reconstruct and verify the source-pinned R7 drone audit in a NEW directory.

Uses real reviewed Git resources, a pinned engine and the repository checked
runner. Production source/data are never edited. The one synthetic custom motor
file preserves all baseline numerical values except the stated resistance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REVIEWED_COMMIT = "5a93c105be0736d23f52ac9b46812b3a5e358233"
ENGINE_SHA256 = "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
BASE_SHA256 = "9b9257242b8873d0045df0abf41aa13ca62dccc6b0a5a925683869152367b9be"
EXTRA_SHA256 = "7d1414c110045817b231de7f451cd6ea2e27adb5e1bb14e9d3ea0aec25172415"
PROBES = (
    ("rates", "seventh_pass_rates.gd", "R7 rates: 9 checks, 0 failed"),
    ("angle", "seventh_pass_angle.gd", "R7 angle: 7 checks, 0 failed"),
    ("motor", "seventh_pass_motor_admission.gd", "R7 motor admission: 36 checks, 0 failed"),
    ("rotor", "seventh_pass_rotor_energy.gd", "R7_ROTOR_COMPLETE 28 checks, 0 failed"),
    ("baseline-rates", "tests/test_mr_rates.gd", "0 failed"),
    ("baseline-bus", "tests/test_mr_electric_bus.gd", "0 failed"),
    ("baseline-admission", "tests/test_mr_admission.gd", "0 failed"),
    ("baseline-pack-charge", "tests/test_mr_pack_charge.gd", "0 failed"),
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
    base_path, extra_path = here.parent/"integration-manifest.json", here.parent/"seventh-pass-extra-sources.json"
    if sha(base_path.read_bytes()) != BASE_SHA256 or sha(extra_path.read_bytes()) != EXTRA_SHA256:
        parser.error("dependency manifest identity mismatch")
    base, extra = json.loads(base_path.read_text()), json.loads(extra_path.read_text())
    def git_file(path):
        return subprocess.check_output(["git", "show", REVIEWED_COMMIT+":"+path], cwd=repo)
    runner = repo/"tools/godot/run_checked.py"
    if runner.read_bytes() != git_file("tools/godot/run_checked.py"):
        raise RuntimeError("checked runner changed since reviewed source")
    out.mkdir(parents=True)
    project=out/"project"
    project.mkdir()
    sources=base["files"]+extra["extra_files"]
    assert len(sources)==extra["source_total"] and len({x["path"] for x in sources})==len(sources)
    for row in sources:
        data=git_file(row["path"])
        assert blob_sha(data)==row["git_blob_sha1"], row["path"]
        if row["checkout_bytes"]=="lf_blob_checked_out_as_crlf": data=data.replace(b"\n", b"\r\n")
        else: assert row["checkout_bytes"]=="exact"
        assert sha(data)==row["fixture_sha256"] and len(data)==row["bytes"], row["path"]
        target=project/Path(row["path"]).relative_to("app")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    settings=base["fixture_project_godot"].replace("A36 full Phoenix readers", "A36 R7 isolated drone research")
    (project/"project.godot").write_text(settings)
    probe_names=[p for _,p,_ in PROBES if not p.startswith("tests/")]
    for filename in probe_names: (project/filename).write_bytes((here/filename).read_bytes())
    stock_path=project/"data/multirotors/openrc-fpv5-x1.json"
    custom=json.loads(stock_path.read_text())
    custom["powertrain"]["resistance"].update(value=.001, kind="estimated",
        source="estimated: manufactured R7 motor stiffness diagnostic; not identified hardware")
    custom_path=project/"r7_custom_motor.json"
    dump(custom_path, custom)
    for name, child in (("XDG_DATA_HOME","user-data"),("XDG_CONFIG_HOME","user-config"),("XDG_CACHE_HOME","user-cache")):
        os.environ[name]=str(out/child)
    # Preserve pool/testqueue admission variables; run_checked owns scheduling.
    sys.dont_write_bytecode=True
    sys.path.insert(0,str(repo))
    from tools.godot.run_checked import run_checked
    from tools.testqueue import common, pool
    evidence={"format":"openrc-a36-r7-evidence v1", "reviewed_commit":REVIEWED_COMMIT,
        "engine_sha256":ENGINE_SHA256,"engine_version":subprocess.check_output([str(engine),"--version"],text=True).strip(),
        "base_manifest_sha256":BASE_SHA256,"extra_manifest_sha256":EXTRA_SHA256,"source_count":len(sources),
        "checked_runner_sha256":sha(runner.read_bytes()),"fixture_project_godot":settings,"production_stubs":[],
        "execution":"GDScript multirotor framed-sampled-v1 and reference RK4; no native qualification",
        "host_admission":{"pool_config_present":Path(pool.default_config()).exists(),"queue_enabled":common.enabled()},
        "stock_data_sha256":sha(stock_path.read_bytes()),
        "synthetic_input":{"path":"r7_custom_motor.json","sha256":sha(custom_path.read_bytes()),
            "physical_change":"powertrain.resistance.value only: stock -> 0.001 ohm",
            "other_changes":["powertrain.resistance.kind","powertrain.resistance.source"],
            "scope":"manufactured input; inherited baseline fit annotations are not recalibrated hardware evidence"},
        "probe_sha256":{n:sha((here/n).read_bytes()) for n in probe_names+[Path(__file__).name,"seventh_pass_oracles.py"]},
        "checks":[],"oracles":[],"ok":False}
    evidence_path=out/"evidence.json"
    def checked(label, args, required):
        result=run_checked([str(engine),"--headless","--path",str(project),"--audio-driver","Dummy"]+args,
            out/"checks",timeout=90,warnings_as_errors=True,required=required,label="a36-r7-"+label)
        evidence["checks"].append({"label":label,"report":result,"engine_log":Path(result["log"]).read_text()})
        dump(evidence_path,evidence)
        print(label+": "+result["reason"],flush=True)
        if not result["ok"] or result["counts"]!={"error":0,"warning":0}:
            raise RuntimeError("unexpected checked result; inspect "+str(evidence_path))
    checked("import",["--editor","--import"],["Godot Engine"])
    for label, filename, marker in PROBES: checked(label,["--script","res://"+filename],[marker])
    command=[sys.executable,str(here/"seventh_pass_oracles.py"),"--evidence",str(evidence_path),"--project",str(project)]
    result=subprocess.run(command,capture_output=True,text=True,check=False)
    evidence["oracles"].append({"command":command,"exit_code":result.returncode,"stdout":result.stdout,"stderr":result.stderr})
    dump(evidence_path,evidence)
    if result.returncode: raise RuntimeError("independent scalar oracle failed")
    for row in sources:
        assert sha((project/Path(row["path"]).relative_to("app")).read_bytes())==row["fixture_sha256"],row["path"]
    assert sha(stock_path.read_bytes())==evidence["stock_data_sha256"]
    evidence["all_source_bytes_unchanged_after_execution"]=True
    evidence["ok"]=True
    dump(evidence_path,evidence)
    print("R7_REPRODUCTION_COMPLETE "+str(evidence_path),flush=True)


if __name__=="__main__": main()
