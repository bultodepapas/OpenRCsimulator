#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
L=$E/tools/lookdev.py
mkdir -p $E/compare8 $E/v8final
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $E/compare8 --views A B --samples 40 --crop engine --muffler
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 16 --samples 64 --out $E/v8final/engine_SE_front_left_####
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 106 --samples 64 --out $E/v8final/engine_SE_exhaust_side_####
$R --blend $E/v3/engine_se.blend $L -- --stage render --frames 61 --samples 64 --out $E/v8final/engine_SE_rear_####
echo DONE
