#!/usr/bin/env bash
set -u
P=/home/claude/props; O=$P/out
B=/home/claude/tools/blender
python3 $B -b $O/assembly/motor_bancada_helices.blend --python $P/tools/render_props.py -- --out $O/renders --views a_hero,a_frente,b_hero,c_detalle,d_detalle,a_lado --res 1400 960 --samples 48 2>&1 | grep -E "rendered|Error|Traceback"
python3 $B -b $O/props_library.blend --python $P/tools/catalog.py -- --studio /home/claude/engine/v4/engine_se_bancada.blend --check $O/check_props.json --out $O/renders --views catalogo,detalle_raices,spinners --res 1800 1250 --samples 48 --save $O/catalogo_helices.blend 2>&1 | grep -E "rendered|Error|Traceback"
echo RENDERS_DONE
