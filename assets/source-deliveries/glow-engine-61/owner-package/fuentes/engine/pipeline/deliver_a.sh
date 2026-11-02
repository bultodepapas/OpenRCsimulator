#!/usr/bin/env bash
# head v2 deliverables -> /mnt/user-data/outputs/glow_engine_61
set -u
E=/home/claude/engine; H=$E/v4/head2; B="python3 /home/claude/tools/blender"
D=/mnt/user-data/outputs/glow_engine_61; DB=$D/bancada_avion; DP=$D/helices_spinners; AU=$E/v4/audit3
log() { echo "[$(date +%H:%M:%S)] $*"; }
log blend; $B -b $E/v4/engine_se.blend --python $E/tools/add_photo_cams.py -- --save $D/glow_engine_61_SE.blend > $H/deliver.log 2>&1
log glb; $B -b $E/v4/engine_se.blend --python $E/tools/export_glb.py -- --out $D/glow_engine_61_SE.glb >> $H/deliver.log 2>&1
log reports
cp $E/v4/mech_se.json $D/mecanica/reporte_mecanico_SE.json; cp $E/v4/muf_se.json $D/mecanica/reporte_mofle_SE.json
cp $E/v4/qa_engine_se.json $D/mecanica/qa_engine_se.json; cp $E/v4/mass_se.json $D/mecanica/masas_volumenes_SE.json
log sources
cp $E/build_engine.py $D/build_engine.py
for t in head_renders.py head_sheet.py export_glb.py export_rt.py; do cp $E/tools/$t $D/herramientas/; done
cp /home/claude/head/head_dev.py /home/claude/head/tools/zf_locate.py $D/herramientas/
log bancada
cp $E/v4/engine_se_bancada.blend $DB/glow_engine_61_SE_bancada.blend
$B -b $E/v4/engine_se_bancada.blend --python $E/tools/export_glb.py -- --out $DB/glow_engine_61_SE_bancada.glb --root Glow_Engine_61,Bancada_Avion >> $H/deliver.log 2>&1
cp $E/v4/bancada/mount_check.json $DB/verificacion/interferencias_y_roscas.json; cp $E/v4/bancada/qa_bancada.json $DB/verificacion/qa_bancada.json
log props
cp /home/claude/props/out/assembly/motor_bancada_helices.blend $DP/motor_bancada_helices.blend
cp /home/claude/props/out/assembly/mount_check.json $DP/verificacion/mount_check.json 2>/dev/null
log realtime
$B -b $E/v4/engine_se.blend --python $E/tools/export_rt.py -- --out $D/tiempo_real/glow_engine_61_SE_realtime.glb --res 2048 --tex $D/tiempo_real/texturas >> $H/deliver.log 2>&1
cp $D/tiempo_real/texturas/rt_report.json $D/tiempo_real/reporte_tiempo_real.json 2>/dev/null
log DELIVER_DONE
