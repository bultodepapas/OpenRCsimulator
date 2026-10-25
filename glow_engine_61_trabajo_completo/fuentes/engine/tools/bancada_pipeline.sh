#!/usr/bin/env bash
# engine_se.blend -> + O.S. 905 mount, firewall, lines, nose -> UV -> QA -> fit / interference checks
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
B=$E/v4/engine_se_bancada.blend
OUT=$E/v4/bancada
mkdir -p $OUT
python3 /home/claude/tools/blender -b $E/v4/engine_se.blend --python $E/tools/build_mount.py -- --save $B 2>&1 | grep "@@JSON@@" | cut -c9- > $OUT/build.json
OBJS=$(python3 /home/claude/tools/blender $B -b --python-expr "import bpy; print('LIST:'+' '.join(o.name for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('BANC_')))" 2>/dev/null | grep LIST: | cut -c6-)
$R --blend $B $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $OBJS --method smart --angle 66 --save $B | cut -c1-40
$R --blend $B $S/blender-asset-qa/scripts/qa_check.py -- --objects $OBJS --profile render --eps 0.0002 --tol 0.001 > $OUT/qa_bancada.json
python3 -c "
import json; d=json.load(open('$OUT/qa_bancada.json')); print('QA pass',d.get('pass'),'errors',d.get('errors')); print('tris',sum(v['tris'] for v in d['objects'].values()))"
python3 /home/claude/tools/blender -b $B --python $E/tools/mount_check.py -- --out $OUT/mount_check.json 2>&1 | grep "@@JSON" | python3 -c "
import sys,json; d=json.loads(sys.stdin.read().split('@@JSON@@')[1]); print('interference',d['interference'])"
cat $OUT/build.json
