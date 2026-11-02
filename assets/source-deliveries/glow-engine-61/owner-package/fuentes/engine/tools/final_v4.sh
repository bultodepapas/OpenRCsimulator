#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
L=$E/tools/lookdev.py
mkdir -p $E/v4final
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $E/compare --views Ac B2 E D --samples 48 --crop carb
$R --blend $E/v3/carb_os61.blend $L -- --stage render --frames 14 --camera CAM_Hero --samples 64 --res 1400 1050 --out $E/v4final/carb_hero_####
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 16 --samples 64 --out $E/v4final/engine_SE_front_left_####
$R --blend $E/v3/carb_os61.blend $L -- --stage render --frames 85 --samples 64 --res 1400 1050 --out $E/v4final/carb_arm_side_####
echo DONE
