#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
L=/home/claude/engine/tools/lookdev.py
V=/home/claude/engine/v3
O=$V/final; mkdir -p $O
$R --blend $V/engine_standard.blend $L -- --stage render --frames 27 --camera CAM_Hero --muffler off --samples 80 --out $O/standard_photo_match_####
$R --blend $V/carb_classic.blend $L -- --stage render --frames 14 --camera CAM_Hero --samples 64 --res 1400 1050 --out $O/carb_classic_hero_####
$R --blend $V/engine_se.blend $L -- --stage render --frames 16 --samples 80 --out $O/se_front_left_####
$R --blend $V/engine_standard.blend $L -- --stage render --frames 16 --muffler off --samples 80 --out $O/standard_front_left_####
$R --blend $V/engine_se.blend $L -- --stage render --frames 31 --samples 80 --out $O/se_side_needle_####
$R --blend $V/engine_se.blend $L -- --stage render --frames 106 --muffler off --samples 80 --out $O/se_exhaust_side_####
$R --blend $V/carb_classic.blend $L -- --stage render --frames 85 --samples 64 --res 1400 1050 --out $O/carb_classic_arm_side_####
echo DONE
