#!/usr/bin/env bash
# mechanical + muffler checks on the built models
E=/home/claude/engine
for v in se standard; do
  python3 /home/claude/tools/blender -b $E/v4/engine_${v}_model.blend --python $E/tools/mech_check.py -- --step 4 --out $E/v4/mech_${v}.json > $E/v4/mech_${v}.log 2>&1
  python3 /home/claude/tools/blender -b $E/v4/engine_${v}_model.blend --python $E/tools/muf_check.py -- --voxel 0.6 --out $E/v4/muf_${v}.json > $E/v4/muf_${v}.log 2>&1
  echo "== $v"; python3 -c "
import json; m=json.load(open('$E/v4/mech_${v}.json')); u=json.load(open('$E/v4/muf_${v}.json'))
print(' mech interference:', m.get('interference'), '| CR', m.get('compression_geometric'), '| BF', m.get('balance_factor_pct'))
print(' muffler:', u['interference_unexpected'], u['gas_path'])"
done
# asset QA (render profile) on the visible parts of the lookdev files (the hidden prop collection is checked by mesh_defects)
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
for f in engine_se engine_standard carb_os61; do
  L=$(python3 /home/claude/tools/blender $E/v4/$f.blend --python-expr "import bpy; print('LIST:'+' '.join(o.name for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(('ENG_','MUF_','CARB_')) and not any(c.hide_viewport for c in o.users_collection)))" 2>/dev/null | grep LIST: | cut -c6-)
  python3 $S/blender-core/scripts/run_in_blender.py --blend $E/v4/$f.blend $S/blender-asset-qa/scripts/qa_check.py -- --objects $L --profile render --eps 0.0002 --tol 0.001 --max-tris 2000000 > $E/v4/qa_$f.json 2>&1
  echo "== QA $f"; python3 -c "
import json; d=json.load(open('$E/v4/qa_$f.json')); print(' pass', d.get('pass'), '| errors', d.get('errors'), '| warnings', d.get('warnings'), '| tris', sum(v['tris'] for v in d.get('objects', {}).values()))"
done
