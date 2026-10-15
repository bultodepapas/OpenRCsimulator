#!/usr/bin/env bash
# usage: bisect_step.sh <commit>  -> prints liftoff and loop results at that commit (clean worktree)
S=${SCRATCH:?set SCRATCH to a work directory}
WT=$S/wt-bisect; G=/c/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.7.2-stable_win64_console.exe
cd $WT && git checkout -q --force --detach "$1" && git clean -qfd app/tests app/physics app/sim >/dev/null 2>&1
timeout 900 $G --headless --path app --audio-driver Dummy --editor --import > $S/bisect-import.log 2>&1
g=$(timeout 600 $G --headless --path app --audio-driver Dummy --script res://tests/test_p51_ground.gd 2>&1 | grep -E "lift-off between|^info takeoff:" | tr '\n' ' ')
h=$(timeout 600 $G --headless --path app --audio-driver Dummy --script res://tests/test_p51_handling.gd 2>&1 | grep -E "inside loop at" | tr '\n' ' ')
echo "$(git log --oneline -1 | cut -c1-60) || $g || $h"
