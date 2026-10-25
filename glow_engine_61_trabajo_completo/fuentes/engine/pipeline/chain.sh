#!/usr/bin/env bash
# head v2: rebuild the SE engine and everything that contains it
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
B="python3 /home/claude/tools/blender"
E=/home/claude/engine
H=$E/v4/head2
cd $E
log() { echo "[$(date +%H:%M:%S)] $*"; }
list() { $B "$1" --python-expr "import bpy; print('LIST:'+' '.join(o.name for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(('ENG_','MUF_','CARB_')) and not any(c.hide_viewport for c in o.users_collection)))" 2>/dev/null | grep LIST: | cut -c6-; }
log build; $R $E/build_engine.py -- --variant se --save $E/v4/engine_se_model.blend > $H/build.log 2>&1
tail -c 400 $H/build.log
[ -f $E/v4/engine_se_model.blend ] && [ $E/v4/engine_se_model.blend -nt $H/chain.sh ] || { log BUILD_FAILED; exit 1; }
log uv; $R --blend $E/v4/engine_se_model.blend $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $(list $E/v4/engine_se_model.blend) --method smart --angle 66 --save $E/v4/engine_se_uv.blend | cut -c1-80
log lookdev; $R --blend $E/v4/engine_se_uv.blend $E/tools/lookdev.py -- --stage setup --backdrop 0.12 --exposure -2.0 --save $E/v4/engine_se.blend | cut -c1-80
log qa; $R --blend $E/v4/engine_se.blend $S/blender-asset-qa/scripts/qa_check.py -- --objects $(list $E/v4/engine_se.blend) --profile render --eps 0.0002 --tol 0.001 --max-tris 2000000 > $E/v4/qa_engine_se.json
python3 -c "
import json; d=json.load(open('$E/v4/qa_engine_se.json')); print('QA pass',d.get('pass'),'errors',d.get('errors'),'nwarn',len(d.get('warnings',[])),'tris',sum(v['tris'] for v in d['objects'].values()))"
log mech; $B -b $E/v4/engine_se_model.blend --python $E/tools/mech_check.py -- --step 4 --out $E/v4/mech_se.json > $E/v4/mech_se.log 2>&1
$B -b $E/v4/engine_se_model.blend --python $E/tools/muf_check.py -- --voxel 0.6 --out $E/v4/muf_se.json > $E/v4/muf_se.log 2>&1
python3 -c "
import json; m=json.load(open('$E/v4/mech_se.json')); u=json.load(open('$E/v4/muf_se.json'))
print(' mech interference:', m.get('interference'), '| CR', m.get('compression_geometric'), '| BF', m.get('balance_factor_pct'))
print(' muffler:', u['interference_unexpected'], u['gas_path'])"
$B -b $E/v4/engine_se_model.blend --python $E/tools/mass_report.py -- --out $E/v4/mass_se.json > $E/v4/mass.log 2>&1
log bancada; bash $E/tools/bancada_pipeline.sh > $H/bancada.log 2>&1; tail -5 $H/bancada.log
log audit; rm -rf $E/v4/audit3; bash $E/tools/audit_all.sh $E/v4/engine_se.blend $E/v4/audit3 24 50 > $H/audit.log 2>&1; tail -30 $H/audit.log
log props; cd /home/claude/props && $B -b $E/v4/engine_se_bancada.blend --python tools/mount_props.py -- --lib out/props_library.blend --save out/assembly/motor_bancada_helices.blend --show A --check out/assembly/mount_check.json 2>&1 | grep -E "^(A|B|C|D) |Error|Traceback" | cut -c1-300
cd $E
log CHAIN_DONE
