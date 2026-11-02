#!/usr/bin/env bash
set -u
E=/home/claude/engine; H=$E/v4/head2; D=/mnt/user-data/outputs/glow_engine_61; AU=$E/v4/audit3
log() { echo "[$(date +%H:%M:%S)] $*"; }
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
log DELIVER_B_DONE
