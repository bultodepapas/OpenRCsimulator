#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
L=/home/claude/engine/tools/lookdev.py
V=/home/claude/engine/v3
O=$V/final
while ps -eo args | grep -q "[s]tandard_front_left"; do sleep 5; done
$R --blend $V/engine_standard.blend $L -- --stage render --frames 27 --camera CAM_Hero --muffler off --samples 80 --out $O/standard_photo_match_####
$R --blend $V/engine_standard.blend $L -- --stage render --frames 16 --muffler off --samples 80 --out $O/standard_front_left_####
echo DONE
