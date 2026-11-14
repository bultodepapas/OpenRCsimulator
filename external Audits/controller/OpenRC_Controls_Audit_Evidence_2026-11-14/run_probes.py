#!/usr/bin/env python3
"""Run the delivered synthetic OpenRC controls probes through the repo's checker.

Requires the audited checkout and its pinned Godot. Does not modify that checkout.
Default: calibration, setup/capture, routing and hot-path operation counts.
Baseline tests, the controlled race and the timing experiment are opt-in.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parent
EXPECTED_ENGINE="4.8.beta2.official.cafc17a19"
GROUPS={
    "calibration":("evidence/calibration/project",[
        ("audit_probe.gd","Calibration audit: 16 checks, 0 failed"),
        ("ui_probe.gd","Calibration UI audit: 5 checks, 0 failed"),
    ]),
    "profiles":("evidence/profiles/repro",[
        ("probe.gd","AUDIT_PROBE_COMPLETE failures=0"),
        ("capture_probe.gd","CAPTURE_PROBE_COMPLETE failures=0"),
    ]),
    "routing":("evidence/routing/probe",[
        ("probe.gd","probe complete"),
        ("quad_fc.gd","quad FC probe complete"),
        ("airship_pause.gd","airship pause probe complete"),
    ]),
    "hotpath":("evidence/parent/project",[
        ("audit_hotpath.gd","HOTPATH_AUDIT_COMPLETE"),
    ]),
}
BASELINE=[
    ("test_controller_conditioning.gd","Controller conditioning: 57 checks, 0 failed"),
    ("test_controller_profile.gd","Controller profile: 74 checks, 0 failed"),
    ("test_controller_actions.gd","all controller action checks passed"),
    ("test_rc_input.gd","41 checks, 0 failed"),
    ("test_rc_calibration.gd","39 checks, 0 failed"),
    ("test_jeti_runtime.gd","JETI runtime: 105 checks, 0 failures"),
    ("test_jeti_identity.gd","JETI identity/service: 56/56 checks passed"),
    ("test_controller_registry.gd","Controller registry: 27 checks, 0 failed"),
    ("test_radio_menu.gd","Radio menu: 180 checks, 0 failed"),
    ("test_controller_store.gd","Controller profile store: 47 checks, 0 failed"),
    ("test_controller_profile_hardening.gd","Controller profile hardening: 94 checks, 0 failures"),
    ("test_controller_diagnostics.gd","Controller diagnostics: 49 checks, 0 failed"),
    ("test_input_report_buttons.gd","F1 button data: 15 checks, 0 failed"),
    ("test_controller_auto_defaults.gd","Controller automatic defaults: 37/37 checks passed"),
]

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-bin",default=os.environ.get("GODOT_BIN"))
    parser.add_argument("--checked-runner",default=os.environ.get("CHECKED_RUNNER"))
    parser.add_argument("--group",choices=["all",*GROUPS,"baseline"],default="all")
    parser.add_argument("--baseline",action="store_true",help="also run the 14 existing test scripts")
    parser.add_argument("--race",action="store_true",help="also run the controlled two-writer protocol")
    parser.add_argument("--measure",action="store_true",help="also time the hot-path projection; stop other engine work first")
    parser.add_argument("--no-import",action="store_true",help="use already imported disposable projects")
    args=parser.parse_args()
    for name in ("godot_bin","checked_runner"):
        if not getattr(args,name):
            parser.error("supply --"+name.replace("_","-")+" or "+name.upper())
    engine=Path(args.godot_bin).expanduser().resolve()
    runner=Path(args.checked_runner).expanduser().resolve()
    if not engine.is_file() or not runner.is_file():
        parser.error("engine and checked-runner paths must be existing files")
    version=subprocess.check_output([str(engine),"--version"],text=True,timeout=10).strip()
    if version!=EXPECTED_ENGINE:
        parser.error(f"expected {EXPECTED_ENGINE}; observed {version}")
    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run_root=ROOT/"new_runs"/stamp
    run_root.mkdir(parents=True)
    env=os.environ.copy()
    env.update({
        "XDG_DATA_HOME":str(run_root/"xdg-data"),
        "XDG_CONFIG_HOME":str(run_root/"xdg-config"),
        "XDG_CACHE_HOME":str(run_root/"xdg-cache"),
    })
    imported=set()
    invocations=[]
    def checked(project:Path,label:str,script:str|None=None,marker:str|None=None,measure=False):
        argv=[sys.executable,str(runner),"--out-dir",str(run_root/"checks"),
              "--label",label,"--timeout","60"]
        if marker:argv+=["--require-text",marker]
        argv+=["--",str(engine),"--headless","--path",str(project),"--audio-driver","Dummy"]
        if script:
            argv+=["--script","res://"+script]
            if measure:argv+=["--","--measure"]
        else:
            argv+=["--import"]
        print("RUN "+label,flush=True)
        result=subprocess.run(argv,cwd=ROOT,env=env,timeout=75,check=False)
        invocations.append({"label":label,"returncode":result.returncode})
        if result.returncode:raise RuntimeError("checked run failed: "+label)
    def ensure_import(project:Path):
        if project in imported:return
        if not args.no_import:checked(project,"import-"+project.parent.name)
        imported.add(project)
    try:
        chosen=list(GROUPS) if args.group=="all" else ([] if args.group=="baseline" else [args.group])
        for group in chosen:
            rel,scripts=GROUPS[group]
            project=ROOT/rel
            ensure_import(project)
            for script,marker in scripts:
                checked(project,group+"-"+Path(script).stem,script,marker)
        if args.baseline or args.group=="baseline":
            project=ROOT/"evidence/parent/project"
            ensure_import(project)
            for script,marker in BASELINE:
                checked(project,"baseline-"+Path(script).stem,"tests/"+script,marker)
        if args.measure:
            project=ROOT/"evidence/parent/project"
            ensure_import(project)
            checked(project,"hotpath-timing","audit_hotpath.gd","HOTPATH_AUDIT_COMPLETE",True)
        if args.race:
            ensure_import(ROOT/"evidence/profiles/repro")
            print("RUN controlled-two-writer-race",flush=True)
            result=subprocess.run([
                sys.executable,str(ROOT/"evidence/profiles/run_concurrent_portable.py"),
                "--godot-bin",str(engine),"--checked-runner",str(runner)],
                cwd=ROOT,env=env,timeout=65,check=False)
            invocations.append({"label":"controlled-two-writer-race","returncode":result.returncode})
            if result.returncode:raise RuntimeError("controlled race failed")
    finally:
        (run_root/"launcher_summary.json").write_text(json.dumps({
            "engine":version,"group":args.group,"invocations":invocations,
            "scope":"Synthetic fixtures, not hardware or full application qualification",
        },indent=2)+"\n")
    print("PROBES_COMPLETE results="+str(run_root),flush=True)
    return 0

if __name__=="__main__":
    try:raise SystemExit(main())
    except (OSError,RuntimeError,subprocess.SubprocessError) as error:
        print("Probe launcher failed: "+str(error),file=sys.stderr)
        raise SystemExit(1)
