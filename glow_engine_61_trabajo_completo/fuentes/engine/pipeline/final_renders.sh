#!/usr/bin/env bash
# re-render the mount and prop scenes that show the engine (new head) and their contact sheets
set -u
E=/home/claude/engine; P=/home/claude/props; B=/home/claude/tools/blender
D=/mnt/user-data/outputs/glow_engine_61; DB=$D/bancada_avion; DP=$D/helices_spinners
log() { echo "[$(date +%H:%M:%S)] $*"; }
cd $E
log bancada; rm -rf v4/bancada/final; bash v4/bancada/render_final.sh
python3 - <<'PY'
from PIL import Image
D = "/home/claude/engine/v4/bancada/final"
names = ["hero", "frente_izq", "lado", "detalle", "atras", "bancada_sola", "arriba"]
W, H = 640, 480
g = Image.new("RGB", (4 * W, 2 * H), (255, 255, 255))
for i, n in enumerate(names):
    im = Image.open(f"{D}/{n}.png").convert("RGB").resize((W, H), Image.LANCZOS)
    g.paste(im, ((i % 4) * W, (i // 4) * H))
g.save("/home/claude/engine/v4/bancada/hoja_bancada.jpg", quality=88)
PY
cp v4/bancada/final/*.png v4/bancada/hoja_bancada.jpg $DB/renders/
log props
python3 $B -b $P/out/assembly/motor_bancada_helices.blend --python $P/tools/render_props.py -- --out $P/out/renders --views a_hero,a_frente,b_hero,c_detalle,d_detalle,a_lado --res 1400 960 --samples 32 2>&1 | grep -E "rendered|Error|Traceback"
python3 $P/tools/sheet.py $P/out/renders $P/out/renders/hoja_helices.jpg
for n in a_hero a_frente b_hero c_detalle d_detalle a_lado hoja_helices; do cp $P/out/renders/$n.* $DP/renders/ 2>/dev/null; done
log FINAL_RENDERS_DONE
