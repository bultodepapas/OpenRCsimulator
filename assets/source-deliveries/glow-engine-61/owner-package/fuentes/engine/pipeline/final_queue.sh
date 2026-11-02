#!/usr/bin/env bash
set -u
E=/home/claude/engine; H=$E/v4/head2; B="python3 /home/claude/tools/blender"; D=/mnt/user-data/outputs/glow_engine_61
log() { echo "[$(date +%H:%M:%S)] $*"; }
until grep -q CHAIN3_DONE $H/chain4.log; do sleep 30; done
log before_missing
for v in E Ac B2 D A; do
  if [ ! -f $H/cmp_before/r_$v.png ]; then
    $B -b --python /home/claude/head/head_dev.py -- --blend $E/v4/engine_se_before_head2.blend --keepmat --out $H/cmp_before --views $v --samples 32 >> $H/cmp_before/log.txt 2>&1
  fi
done
python3 $E/tools/head_sheet.py $H/cmp_before $H/cmp_after $H/sheets E,Ac,B2,D,A
python3 $E/tools/fin_metrics.py $H/cmp_before $H/cmp_after > $H/fin_metrics.json; cat $H/fin_metrics.json
log deliver_b; bash $H/deliver_b.sh
log realtime
$B -b $E/v4/engine_se.blend --python $E/tools/export_rt.py -- --out $D/tiempo_real/glow_engine_61_SE_realtime.glb --res 2048 --tex $D/tiempo_real/texturas > $H/rt.log 2>&1
cp $D/tiempo_real/texturas/rt_report.json $D/tiempo_real/reporte_tiempo_real.json 2>/dev/null
grep -o '"bake_s": [^,]*' $H/rt.log | head; grep -o '"total_tris": [0-9]*' $H/rt.log
log renders; bash $H/final_renders.sh
log QUEUE_DONE
