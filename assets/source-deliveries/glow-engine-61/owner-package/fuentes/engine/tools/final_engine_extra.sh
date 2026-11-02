#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
L=/home/claude/engine/tools/lookdev.py
E=/home/claude/engine/glow_engine_61_lookdev.blend
O=/home/claude/engine/render/carb_final
$R --blend $E $L -- --stage render --frames 1 --camera CAM_Top34 --samples 80 --out $O/engine_top_three_quarter_####
$R --blend $E $L -- --stage render --frames 91 --muffler off --samples 80 --out $O/engine_side_exhaust_####
echo DONE
