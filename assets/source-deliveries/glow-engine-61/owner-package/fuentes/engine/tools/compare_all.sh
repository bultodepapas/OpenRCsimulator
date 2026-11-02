#!/usr/bin/env bash
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
E=/home/claude/engine
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $E/compare --views Ac B2 E D --samples 48 --crop carb
$R --blend $E/v3/engine_se.blend $E/tools/compare_render.py -- --out $E/compare --views A B --samples 48 --crop engine
echo DONE
