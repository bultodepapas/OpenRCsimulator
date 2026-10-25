#!/usr/bin/env bash
E=/home/claude/engine; H=$E/v4/head2; B="python3 /home/claude/tools/blender"; D=/mnt/user-data/outputs/glow_engine_61
$B -b $E/v4/engine_se.blend --python $E/tools/export_rt.py -- --out $D/tiempo_real/glow_engine_61_SE_realtime.glb --res 2048 --tex $D/tiempo_real/texturas --rebake --save $H/rt_scene.blend > $H/rt2.log 2>&1
cp $D/tiempo_real/texturas/rt_report.json $D/tiempo_real/reporte_tiempo_real.json
for az in 35 215; do $B -b $H/rt_scene.blend --python $E/tools/rt_preview.py -- --out $H/rt_prev_$az.png --rt --az $az > /dev/null 2>&1; done
python3 - <<'PY'
from PIL import Image
a = Image.open("/home/claude/engine/v4/head2/rt_prev_35.png").convert("RGB"); b = Image.open("/home/claude/engine/v4/head2/rt_prev_215.png").convert("RGB")
g = Image.new("RGB", (a.width + b.width, a.height)); g.paste(a, (0, 0)); g.paste(b, (a.width, 0))
g.save("/mnt/user-data/outputs/glow_engine_61/tiempo_real/vista_previa_realtime.jpg", quality=88)
PY
echo RT2_DONE
