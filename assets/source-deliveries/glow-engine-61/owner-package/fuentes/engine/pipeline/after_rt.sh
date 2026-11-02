#!/usr/bin/env bash
H=/home/claude/engine/v4/head2
until grep -q RT2_DONE $H/rt_rebake.log; do sleep 20; done
bash $H/final_renders.sh > $H/final_renders.log 2>&1
echo AFTER_DONE >> $H/final_renders.log
