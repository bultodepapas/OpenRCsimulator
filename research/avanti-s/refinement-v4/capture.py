#!/usr/bin/env python3
"""Capture all seven frozen views; never re-fit cameras or overwrite a run."""
import argparse,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);p.add_argument('--inspector',action='store_true');a=p.parse_args();out=a.output.resolve()
 if out.exists():p.error('Output directory must be new')
 out.mkdir(parents=True)
 binary=ROOT/'.tools/Godot_v4.7.2-stable_linux.x86_64'
 common=['xvfb-run','-a',str(binary),'--path',str(ROOT/'research/avanti-s/av02'),'--audio-driver','Dummy','--rendering-driver','opengl3']
 for label,folder in [('original','alignment'),('additional','new-angles'),('profile','user-profile')]:
  subprocess.run(common+['--script','../alignment/render.gd','--','--compare-geometry',f'--fit=res://../{folder}/camera-fit.json',f'--picks=res://../{folder}/picks.json','--output-dir='+str(out/label)],check=True,timeout=60)
 if a.inspector:subprocess.run(common+['--script','res://inspect.gd','--','--output-dir='+str(out/'inspector')],check=True,timeout=60)
if __name__=='__main__':main()
