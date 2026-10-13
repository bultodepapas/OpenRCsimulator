"""Reject formula defects in disposable minimal Godot projects, never in the live app."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
CASES=[
 ('two-stroke-cycle-angle','two_stroke.gd','cycle_work_j / CYCLE_ANGLE_RAD','cycle_work_j / (2.0 * CYCLE_ANGLE_RAD)'),
 ('four-stroke-opportunity-rate','four_stroke.gd','rpm / 120.0','rpm / 60.0'),
 ('two-stroke-premix-oil','two_stroke.gd','/ (1.0 - oil_fraction)','/ 1.0'),
 ('four-stroke-valve-loss','four_stroke.gd','- valve_torque_nm','- 0.0'),
]


def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--godot',required=True);parser.add_argument('--out',required=True,type=Path)
 args=parser.parse_args(); args.out.mkdir(parents=True,exist_ok=False)
 reports=[]
 with tempfile.TemporaryDirectory(prefix='openrc-glow-mutations-') as temp:
  root=Path(temp);app=root/'app';physics=app/'physics/glow';tests=app/'tests'
  physics.mkdir(parents=True);tests.mkdir(parents=True)
  (app/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Glow fault qualification"\n',encoding='utf-8')
  for name in ['two_stroke.gd','four_stroke.gd']:
   shutil.copy2(ROOT/'app/physics/glow'/name,physics/name)
  shutil.copy2(ROOT/'app/tests/test_glow_oracle.gd',tests/'test_glow_oracle.gd')
  oracle=root/'research/glow-engines/reference/oracle.json';oracle.parent.mkdir(parents=True)
  shutil.copy2(ROOT/'research/glow-engines/reference/oracle.json',oracle)
  original={p.name:p.read_text(encoding='utf-8') for p in physics.glob('*.gd')}
  for label,name,old,new in [('control','','',''),*CASES]:
   for n,text in original.items():(physics/n).write_text(text,encoding='utf-8')
   if name:
    if original[name].count(old)!=1:raise RuntimeError('Mutation no longer identifies exactly one expression: '+label)
    (physics/name).write_text(original[name].replace(old,new),encoding='utf-8')
   run=subprocess.run([args.godot,'--headless','--path',str(app),'--audio-driver','Dummy','--script','res://tests/test_glow_oracle.gd'],capture_output=True,text=True,timeout=60)
   log=run.stdout+run.stderr;(args.out/(label+'.log')).write_text(log,encoding='utf-8')
   passed=(run.returncode==0) if label=='control' else (run.returncode!=0 and 'FAIL' in log and 'SCRIPT ERROR:' not in log)
   reports.append(dict(case=label,exit_code=run.returncode,expected_failure=label!='control',passed=passed))
   print(label+': '+('PASS' if passed else 'FAIL'),flush=True)
  report=dict(format='openrc-glow-mutation-proof v1',cases=reports,passed=all(r['passed'] for r in reports))
  (args.out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
  raise SystemExit(0 if report['passed'] else 1)


if __name__=='__main__':main()
