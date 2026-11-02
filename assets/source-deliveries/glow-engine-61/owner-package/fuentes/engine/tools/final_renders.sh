#!/usr/bin/env bash
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
B=/home/claude/engine/glow_engine_61_lookdev.blend
O=/home/claude/engine/render/final
mkdir -p $O
SPP=${SPP:-96}
$R --blend $B /home/claude/engine/tools/lookdev.py -- --stage render --frames 16  --samples $SPP --out $O/hero_front_left_####
$R --blend $B /home/claude/engine/tools/lookdev.py -- --stage render --frames 106 --muffler off --samples $SPP --out $O/hero_exhaust_side_####
$R --blend $B /home/claude/engine/tools/lookdev.py -- --stage render --frames 1 --camera CAM_Top34 --samples $SPP --out $O/top_three_quarter_####
$R --blend $B /home/claude/engine/tools/lookdev.py -- --stage render --frames 31  --samples $SPP --out $O/side_needle_####
$R --blend $B /home/claude/engine/tools/lookdev.py -- --stage render --frames 91  --muffler off --samples $SPP --out $O/side_exhaust_####
echo DONE
