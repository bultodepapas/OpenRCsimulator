#!/usr/bin/env bash
cd /home/claude/engine
OUT=v4/bancada/final
mkdir -p $OUT
for v in hero frente_izq lado detalle atras bancada_sola arriba; do
  [ -f $OUT/$v.png ] && continue
  python3 /home/claude/tools/blender -b v4/engine_se_bancada.blend --python tools/render_mount.py -- --out $OUT --res 1280 960 --samples 32 --views $v > $OUT/$v.log 2>&1
done
echo ALLDONE > $OUT/done.txt
