#!/usr/bin/env bash
# head v2, final materials: rematerial the built blends, then before/after comparisons, detail renders, audit, metrics
set -u
B="python3 /home/claude/tools/blender"
E=/home/claude/engine; H=$E/v4/head2
cd $E
log() { echo "[$(date +%H:%M:%S)] $*"; }
log remat
for f in $E/v4/engine_se.blend $E/v4/engine_se_model.blend $E/v4/engine_se_bancada.blend /home/claude/props/out/assembly/motor_bancada_helices.blend; do
  $B -b $f --python $E/tools/rematerial.py -- --save $f 2>&1 | grep -c "@@JSON@@"
done
log headcmp
for tag in before after; do
  F=$E/v4/engine_se.blend; [ $tag = before ] && F=$E/v4/engine_se_before_head2.blend
  rm -rf $H/cmp_$tag; mkdir -p $H/cmp_$tag
  $B -b --python /home/claude/head/head_dev.py -- --blend $F --keepmat --out $H/cmp_$tag --views E,Ac,B2,D,A --samples 32 > $H/cmp_$tag/log.txt 2>&1
done
python3 $E/tools/head_sheet.py $H/cmp_before $H/cmp_after $H/sheets E,Ac,B2,D,A
python3 $E/tools/fin_metrics.py $H/cmp_before $H/cmp_after > $H/fin_metrics.json; cat $H/fin_metrics.json
log detail
rm -rf $H/detail
$B -b $E/v4/engine_se.blend --python $E/tools/head_renders.py -- --out $H/detail --samples 96 > $H/detail.log 2>&1
$B -b $E/v4/engine_se_before_head2.blend --python $E/tools/head_renders.py -- --out $H/detail --prefix antes_ --views culata_34,culata_lado --samples 64 > $H/detail_before.log 2>&1
grep -c rendered $H/detail.log $H/detail_before.log
log audit; rm -rf $E/v4/audit3; bash $E/tools/audit_all.sh $E/v4/engine_se.blend $E/v4/audit3 24 50 > $H/audit.log 2>&1; tail -40 $H/audit.log
log CHAIN3_DONE
