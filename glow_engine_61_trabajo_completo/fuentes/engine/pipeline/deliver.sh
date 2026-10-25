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
log audit
for v in A Ac B B2 D E T; do cp $AU/sheet_$v.png $D/auditoria/comparacion_$v.png; done
cp $AU/metrics.json $D/auditoria/metricas_contornos.json; cp $AU/color.json $D/auditoria/metricas_color.json
cp $AU/summary.json $D/auditoria/resumen_auditoria.json; cp $AU/mesh_defects.json $D/auditoria/defectos_malla.json
cp $AU/render_A.png $D/renders/SE_vista_A_frente_izq.png; cp $AU/render_B2.png $D/renders/SE_vista_B2_lado_aguja.png
cp $AU/render_D.png $D/renders/SE_vista_D_atras.png; cp $AU/render_E.png $D/renders/SE_vista_E_lado_escape.png
cp $AU/render_T.png $D/renders/SE_vista_T_arriba.png
mkdir -p $D/auditoria/culata_v2 $D/renders/culata
cp $H/sheets/*.jpg $D/auditoria/culata_v2/
cp $H/audit_before_summary.json $D/auditoria/culata_v2/resumen_auditoria_antes.json
cp $H/detail/*.png $D/renders/culata/
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
