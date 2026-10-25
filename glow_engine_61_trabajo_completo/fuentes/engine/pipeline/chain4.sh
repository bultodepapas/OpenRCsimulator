#!/usr/bin/env bash
set -u
B="python3 /home/claude/tools/blender"; E=/home/claude/engine; H=$E/v4/head2
log() { echo "[$(date +%H:%M:%S)] $*"; }
log detail; rm -rf $H/detail
$B -b $E/v4/engine_se.blend --python $E/tools/head_renders.py -- --out $H/detail --views culata_34,bujia,culata_lado,culata_arriba --res 1200 900 --samples 40 > $H/detail.log 2>&1
$B -b $E/v4/engine_se_before_head2.blend --python $E/tools/head_renders.py -- --out $H/detail --prefix antes_ --views culata_34 --res 1200 900 --samples 40 > $H/detail_before.log 2>&1
grep -c rendered $H/detail.log $H/detail_before.log
log audit; rm -rf $E/v4/audit3; bash $E/tools/audit_all.sh $E/v4/engine_se.blend $E/v4/audit3 24 50 > $H/audit.log 2>&1; tail -40 $H/audit.log
log CHAIN3_DONE
