#!/usr/bin/env bash
# Final deliverables from the v4 pipeline outputs -> /mnt/user-data/outputs/glow_engine_61
set -u
E=/home/claude/engine
B="python3 /home/claude/tools/blender"
D=/mnt/user-data/outputs/glow_engine_61
AU=${1:-$E/v4/audit}
mkdir -p $D/auditoria $D/mecanica $D/herramientas $D/tiempo_real
# blends: SE with the photo cameras (photos packed), standard as built
$B -b $E/v4/engine_se.blend --python $E/tools/add_photo_cams.py -- --save $D/glow_engine_61_SE.blend > $E/v4/deliver.log 2>&1
cp $E/v4/engine_standard.blend $D/glow_engine_61_standard.blend
# full-detail GLBs (every part, flat PBR values)
$B -b $E/v4/engine_se.blend --python $E/tools/export_glb.py -- --out $D/glow_engine_61_SE.glb >> $E/v4/deliver.log 2>&1
$B -b $E/v4/engine_standard.blend --python $E/tools/export_glb.py -- --out $D/glow_engine_61_standard.glb >> $E/v4/deliver.log 2>&1
# real-time GLB: exterior only, <= 150k tris, baked PBR atlases
$B -b $E/v4/engine_se.blend --python $E/tools/export_rt.py -- --out $D/tiempo_real/glow_engine_61_SE_realtime.glb \
   --res 2048 --tex $D/tiempo_real/texturas >> $E/v4/deliver.log 2>&1
cp $D/tiempo_real/texturas/rt_report.json $D/tiempo_real/reporte_tiempo_real.json 2>/dev/null
# reports
cp $E/v4/mech_se.json $D/mecanica/reporte_mecanico_SE.json
cp $E/v4/mech_standard.json $D/mecanica/reporte_mecanico_standard.json
cp $E/v4/muf_se.json $D/mecanica/reporte_mofle_SE.json
cp $E/v4/muf_standard.json $D/mecanica/reporte_mofle_standard.json
for f in engine_se engine_standard carb_os61; do cp $E/v4/qa_$f.json $D/mecanica/qa_$f.json 2>/dev/null; done
# audit
for v in A Ac B B2 D E T; do cp $AU/sheet_$v.png $D/auditoria/comparacion_$v.png; done
cp $AU/metrics.json $D/auditoria/metricas_contornos.json
cp $AU/color.json $D/auditoria/metricas_color.json
cp $AU/summary.json $D/auditoria/resumen_auditoria.json
cp $AU/mesh_defects.json $D/auditoria/defectos_malla.json
# sources + tools
cp $E/build_engine.py $D/build_engine.py
for t in audit_all.sh audit_views.py color_check.py mesh_defects.py mech_check.py muf_check.py voxel_util.py prop_fit.py \
         export_rt.py export_glb.py add_photo_cams.py pipeline_v4.sh post_checks.sh deliver.sh contour_offsets.py \
         shape_errors.py zoom_cmp.py project_pts.py before_after.py mass_report.py rematerial.py; do cp $E/tools/$t $D/herramientas/; done
cp $E/v4/mass_se.json $D/mecanica/masas_volumenes_SE.json
mkdir -p $D/auditoria/errores_forma && cp $AU/shape/heat_*.png $AU/shape/rank.json $D/auditoria/errores_forma/ 2>/dev/null
rm -f $D/auditoria/estadisticas_escena.json $D/auditoria/audit_views.py
mkdir -p $D/herramientas/camaras && cp $E/cams/cam_*.json $D/herramientas/camaras/
ls -la $D $D/tiempo_real
