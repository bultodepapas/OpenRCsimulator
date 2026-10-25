#!/usr/bin/env bash
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
L=/home/claude/engine/tools/lookdev.py
C=/home/claude/engine/carb/carburetor.blend
E=/home/claude/engine/glow_engine_61_lookdev.blend
O=/home/claude/engine/render/carb_final
mkdir -p $O
$R --blend $C $L -- --stage render --frames 61 --camera CAM_Hero --samples 64 --res 1400 1050 --out $O/carb_hero_####
$R --blend $C $L -- --stage render --frames 40 --samples 64 --res 1400 1050 --out $O/carb_needle_side_####
$R --blend $C $L -- --stage render --frames 85 --samples 64 --res 1400 1050 --out $O/carb_arm_side_####
$R --blend $C $L -- --stage render --frames 1 --camera CAM_Top34 --samples 64 --res 1400 1050 --out $O/carb_top_####
$R --blend $C $L -- --stage render --frames 106 --samples 64 --res 1400 1050 --out $O/carb_front_####
$R --blend $E $L -- --stage render --frames 16 --samples 80 --out $O/engine_front_left_####
$R --blend $E $L -- --stage render --frames 106 --muffler off --samples 80 --out $O/engine_exhaust_side_####
$R --blend $E $L -- --stage render --frames 31 --samples 80 --out $O/engine_side_needle_####
echo DONE
