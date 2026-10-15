#!/usr/bin/env bash
# Diagnostic remainder of canonical app/test.sh after the first canonical failure.
# Runs every later test_*.gd sequentially, continuing after failures, with the
# same timeout assignments and SCRIPT/ERROR detection as app/test.sh.
set -u
candidate=/home/bulto/openrc-r11-b09-r05b-20261015-07
app="$candidate/app"
godot="$candidate/.tools/Godot_v4.7.2-stable_linux.x86_64"
evidence=/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/next-candidate/materialized-20261015-07-01/diagnostic-remainder-01
mkdir -p "$evidence/logs" "$candidate/tmp"
printf 'candidate=%s\napp=%s\ngodot=%s\nstarted_utc=%s\nfirst_test_after=%s\n' "$candidate" "$app" "$godot" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "test_atmosphere_column_session.gd" | tee "$evidence/runner-metadata.txt"
printf 'test\texit\ttimeout_s\tengine_error\tlog\n' > "$evidence/results.tsv"
count=0
failed=0
for t in "$app"/tests/test_*.gd; do
  name=${t##*/}
  [[ "$name" > test_atmosphere_column_session.gd ]] || continue
  limit=60
  case "$name" in
    test_landing_maneuver.gd|test_crash_integration.gd|test_crash_wreck.gd) limit=180 ;;
    test_ui_pause.gd|test_ui_screen_stack.gd|test_landing_variations.gd|test_input_report_cli.gd|test_latency_patch_cli.gd) limit=180 ;;
    test_heli_session.gd|test_heli_ground_session.gd) limit=300 ;;
    test_failure_session.gd|test_failure_shutdown.gd|test_failure_routes.gd) limit=180 ;;
    test_rcv_vehicle_dynamics.gd|test_rcv_session.gd|test_rcv_airfield_course.gd|test_rcv_airfield_track.gd|test_rcv_obstacle_contacts.gd|test_rcv_activity.gd|test_rcv_presentation.gd|test_rcv_menu.gd) limit=300 ;;
    test_aircraft_catalog.gd|test_ui_aircraft.gd|test_ui_runway.gd|test_workshop_integration.gd|test_workshop_ui.gd|test_ui_natural_random.gd) limit=600 ;;
  esac
  log="$evidence/logs/${name%.gd}.log"
  printf 'RUN %s timeout=%ss\n' "$name" "$limit" | tee -a "$evidence/console.log"
  timeout "$limit" "$godot" --headless --path "$app" --audio-driver Dummy --script "res://tests/$name" > "$log" 2>&1
  status=$?
  engine_error=0
  if grep -qE '^(SCRIPT )?ERROR:' "$log"; then engine_error=1; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$limit" "$engine_error" "logs/${name%.gd}.log" >> "$evidence/results.tsv"
  count=$((count + 1))
  if [ "$status" -ne 0 ] || [ "$engine_error" -ne 0 ] || grep -qE '(^|[[:space:]])[0-9]+ checks?, [1-9][0-9]* failed|[1-9][0-9]* checks?, [1-9][0-9]* failures|^FAIL ' "$log"; then
    failed=$((failed + 1))
    printf 'FAIL %s exit=%s engine_error=%s (continuing)\n' "$name" "$status" "$engine_error" | tee -a "$evidence/console.log"
  else
    printf 'PASS %s\n' "$name" | tee -a "$evidence/console.log"
  fi
done
printf 'completed_utc=%s\ntests=%s\nfailed_or_engine_error=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$count" "$failed" | tee -a "$evidence/runner-metadata.txt" | tee -a "$evidence/console.log"
