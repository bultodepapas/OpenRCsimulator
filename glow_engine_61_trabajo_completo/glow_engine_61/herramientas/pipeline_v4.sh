#!/usr/bin/env bash
# build -> UV (blender-retopology-uv) -> lookdev (hardsurface stack + turntable) -> QA (blender-asset-qa)
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
list() { python3 /home/claude/tools/blender "$1" --python-expr "import bpy; print('LIST:'+' '.join(o.name for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(('ENG_','MUF_','CARB_')) and not any(c.hide_viewport for c in o.users_collection)))" 2>/dev/null | grep LIST: | cut -c6-; }
for v in se standard; do
  $R $E/build_engine.py -- --variant $v --save $E/v4/engine_${v}_model.blend | cut -c1-120
  $R --blend $E/v4/engine_${v}_model.blend $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $(list $E/v4/engine_${v}_model.blend) --method smart --angle 66 --save $E/v4/engine_${v}_uv.blend | cut -c1-40
  HERO=""; [ "$v" = "standard" ] && HERO='--hero 78,4,100,0.62'
  $R --blend $E/v4/engine_${v}_uv.blend $E/tools/lookdev.py -- --stage setup --backdrop 0.12 --exposure -2.0 $HERO --save $E/v4/engine_${v}.blend | cut -c1-60
  echo "QA $v"; $R --blend $E/v4/engine_${v}.blend $S/blender-asset-qa/scripts/qa_check.py -- --objects $(list $E/v4/engine_${v}.blend) --profile render --eps 0.0002 --tol 0.001 --max-tris 2000000 | python3 -c "
import json,sys; d=json.loads(sys.stdin.read()); print(' pass',d.get('pass')); print(' errors',d.get('errors')); print(' warnings',d.get('warnings')); print(' tris',sum(v['tris'] for v in d['objects'].values()))"
done
# classic carburetor on its own
$R $E/build_engine.py -- --carb-only --carb os61 --save $E/v4/carb_os61_model.blend | cut -c1-120
$R --blend $E/v4/carb_os61_model.blend $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $(list $E/v4/carb_os61_model.blend) --method smart --angle 66 --save $E/v4/carb_os61_uv.blend | cut -c1-40
$R --blend $E/v4/carb_os61_uv.blend $E/tools/lookdev.py -- --stage setup --backdrop 0.12 --elevation 22 --frame 14 --exposure -2.1 --fstop 32 --hero "39,22,50,0.46" --res 1400 1050 --save $E/v4/carb_os61.blend | cut -c1-60
echo "QA carb"; $R --blend $E/v4/carb_os61.blend $S/blender-asset-qa/scripts/qa_check.py -- --objects $(list $E/v4/carb_os61.blend) --profile render --eps 0.0001 --tol 0.0005 | python3 -c "
import json,sys; d=json.loads(sys.stdin.read()); print(' pass',d.get('pass')); print(' errors',d.get('errors')); print(' warnings',d.get('warnings')); print(' tris',sum(v['tris'] for v in d['objects'].values()))"
