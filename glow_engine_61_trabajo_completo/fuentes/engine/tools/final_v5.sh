#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
L=$E/tools/lookdev.py
O=$E/compare7; mkdir -p $O $E/v7final
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $O --views A B --samples 40 --crop engine --muffler
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $O --views Ac E D --samples 40 --crop head
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $O --views Ac B2 E D --samples 40 --crop carb
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 16 --samples 64 --out $E/v7final/engine_SE_front_left_####
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 106 --samples 64 --out $E/v7final/engine_SE_exhaust_side_####
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 1 --camera CAM_Top34 --samples 64 --out $E/v7final/engine_SE_top_####
echo DONE
