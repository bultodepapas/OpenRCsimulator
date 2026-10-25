#!/usr/bin/env bash
# head v2, second pass: rebuild the SE engine, checks, mount, audit, props assembly, before/after renders
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
touch $H/stamp
log build; $R $E/build_engine.py -- --variant se --save $E/v4/engine_se_model.blend > $H/build.log 2>&1
[ $E/v4/engine_se_model.blend -nt $H/stamp ] || { log BUILD_FAILED; tail -c 1500 $H/build.log; exit 1; }
log uv; $R --blend $E/v4/engine_se_model.blend $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $(list $E/v4/engine_se_model.blend) --method smart --angle 66 --save $E/v4/engine_se_uv.blend | cut -c1-80
log lookdev; $R --blend $E/v4/engine_se_uv.blend $E/tools/lookdev.py -- --stage setup --backdrop 0.12 --exposure -2.0 --save $E/v4/engine_se.blend | cut -c1-80
log qa; $R --blend $E/v4/engine_se.blend $S/blender-asset-qa/scripts/qa_check.py -- --objects $(list $E/v4/engine_se.blend) --profile render --eps 0.0002 --tol 0.001 --max-tris 2000000 > $E/v4/qa_engine_se.json
python3 -c "
import json; d=json.load(open('$E/v4/qa_engine_se.json')); print('QA pass',d.get('pass'),'errors',d.get('errors'),'nwarn',len(d.get('warnings',[])),'tris',sum(v['tris'] for v in d['objects'].values())); print('head', {k:d['objects']['ENG_Head'][k] for k in ('tris','ngons','degenerate_faces','nonmanifold_edges','boundary_edges')})"
log mech; $B -b $E/v4/engine_se_model.blend --python $E/tools/mech_check.py -- --step 4 --out $E/v4/mech_se.json > $E/v4/mech_se.log 2>&1
$B -b $E/v4/engine_se_model.blend --python $E/tools/muf_check.py -- --voxel 0.6 --out $E/v4/muf_se.json > $E/v4/muf_se.log 2>&1
python3 -c "
import json; m=json.load(open('$E/v4/mech_se.json')); u=json.load(open('$E/v4/muf_se.json'))
print(' mech interference:', m.get('interference'), '| CR', m.get('compression_geometric'), '| BF', m.get('balance_factor_pct'))
print(' muffler:', u['interference_unexpected'], u['gas_path'])"
$B -b $E/v4/engine_se_model.blend --python $E/tools/mass_report.py -- --out $E/v4/mass_se.json > $E/v4/mass.log 2>&1
python3 -c "
import json,sys; u=json.load(open('$E/v4/muf_se.json')); sys.exit(0 if u['gas_path']['sealed_when_plugged'] else 3)" || { log MUF_LEAK; exit 3; }
log bancada; bash $E/tools/bancada_pipeline.sh > $H/bancada.log 2>&1; tail -4 $H/bancada.log
log props; cd /home/claude/props && $B -b $E/v4/engine_se_bancada.blend --python tools/mount_props.py -- --lib out/props_library.blend --save out/assembly/motor_bancada_helices.blend --show A --check out/assembly/mount_check.json 2>&1 | grep -E "^(A|B|C|D) |Error|Traceback" | cut -c1-300
cd $E
log headcmp
for tag in before after; do
  F=$E/v4/engine_se.blend; [ $tag = before ] && F=$E/v4/engine_se_before_head2.blend
  [ $tag = before ] && [ -f $H/cmp_before/r_A.png ] && continue
  mkdir -p $H/cmp_$tag
  $B -b --python /home/claude/head/head_dev.py -- --blend $F --keepmat --out $H/cmp_$tag --views E,Ac,B2,D,A --samples 32 > $H/cmp_$tag/log.txt 2>&1
done
python3 $E/tools/head_sheet.py $H/cmp_before $H/cmp_after $H/sheets E,Ac,B2,D,A
log detail
$B -b $E/v4/engine_se.blend --python $E/tools/head_renders.py -- --out $H/detail --samples 96 > $H/detail.log 2>&1
$B -b $E/v4/engine_se_before_head2.blend --python $E/tools/head_renders.py -- --out $H/detail --prefix antes_ --views culata_34,culata_lado --samples 64 > $H/detail_before.log 2>&1
grep -c rendered $H/detail.log $H/detail_before.log
log audit; rm -rf $E/v4/audit3; bash $E/tools/audit_all.sh $E/v4/engine_se.blend $E/v4/audit3 24 50 > $H/audit.log 2>&1; tail -30 $H/audit.log
log CHAIN_DONE
