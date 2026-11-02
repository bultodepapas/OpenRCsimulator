#!/usr/bin/env bash
set -u
E=/home/claude/engine
B="python3 /home/claude/tools/blender"
D=/mnt/user-data/outputs/glow_engine_61
DB=$D/bancada_avion
mkdir -p $DB/renders $DB/verificacion $DB/herramientas
# engine (lug holes now 52 x 25, M3.5 clearance): SE with photo cameras, standard, GLBs, sources, QA
$B -b $E/v4/engine_se.blend --python $E/tools/add_photo_cams.py -- --save $D/glow_engine_61_SE.blend > $E/v4/bancada/deliver.log 2>&1
cp $E/v4/engine_standard.blend $D/glow_engine_61_standard.blend
$B -b $E/v4/engine_se.blend --python $E/tools/export_glb.py -- --out $D/glow_engine_61_SE.glb >> $E/v4/bancada/deliver.log 2>&1
$B -b $E/v4/engine_standard.blend --python $E/tools/export_glb.py -- --out $D/glow_engine_61_standard.glb >> $E/v4/bancada/deliver.log 2>&1
cp $E/v4/qa_engine_se.json $D/mecanica/qa_engine_se.json; cp $E/v4/qa_engine_standard.json $D/mecanica/qa_engine_standard.json
cp $E/build_engine.py $D/build_engine.py
# mount assembly
cp $E/v4/engine_se_bancada.blend $DB/glow_engine_61_SE_bancada.blend
$B -b $E/v4/engine_se_bancada.blend --python $E/tools/export_glb.py -- --out $DB/glow_engine_61_SE_bancada.glb --root Glow_Engine_61,Bancada_Avion >> $E/v4/bancada/deliver.log 2>&1
cp $E/v4/bancada/final/*.png $E/v4/bancada/hoja_bancada.jpg $DB/renders/
cp $E/v4/bancada/mount_check.json $DB/verificacion/interferencias_y_roscas.json
cp $E/v4/bancada/qa_bancada.json $DB/verificacion/qa_bancada.json
cp $E/v4/bancada/bancada_medidas.json $DB/bancada_medidas.json
cp $E/v4/bancada/silueta_foto_vs_modelo.png $DB/verificacion/ 2>/dev/null
for t in build_mount.py render_mount.py mount_check.py mount_photo_cmp.py bancada_pipeline.sh export_glb.py; do cp $E/tools/$t $DB/herramientas/; done
for t in calib.py meas.py silfit.py geofit_excl.py export_mesh.py cam_amazon.json cam_amazon_fit.json geofit_excl.json; do cp /home/claude/mount/$t $DB/herramientas/; done
cp $E/tools/export_glb.py $D/herramientas/
ls -la $D $DB $DB/renders
echo DONE > $E/v4/bancada/deliver.done
