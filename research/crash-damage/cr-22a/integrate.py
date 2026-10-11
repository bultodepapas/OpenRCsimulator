"""Apply guarded, additive crash seams to a selected app (used first on a copy)."""
from pathlib import Path
import sys

app = Path(sys.argv[1])

def replace(path, old, new):
    text = path.read_text(encoding='utf-8')
    if new in text:
        return
    if text.count(old) != 1:
        raise RuntimeError(f'Expected one integration anchor in {path}: {old[:70]}')
    path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')

main = app/'main.gd'
replace(main, 'const FlightSession := preload("res://sim/flight_session.gd")', 'const FlightSession := preload("res://sim/flight_session.gd")\nconst CrashDirector = preload("res://render/crash/director.gd")')
replace(main, 'var _engine_phase := 0.0', '## Technical fixtures can retain the original diagnostic freeze route.\nvar crash_effects_enabled := true\nvar _crash_director: CrashDirector\nvar _engine_phase := 0.0')
replace(main, '\tif bool(frametime_options.enabled):', '\tif crash_effects_enabled and not _scripted and not args.has("capture") and str(args.get("crash-effects", "on")) != "off":\n\t\t_crash_director = CrashDirector.new()\n\t\t_crash_director.name = "CrashDirector"\n\t\tadd_child(_crash_director)\n\t\t_crash_director.configure(self, physics_path, str(args.get("soundscape", "on")) != "off")\n\t\tsession.crash_auto_restart = false\n\tif bool(frametime_options.enabled):')
replace(main, '\t_render_pose(_current_pose(), surfaces, _prop_angle)\n\t_update_hud()', '\t_render_pose(_current_pose(), surfaces, _prop_angle)\n\tif _crash_director != null:\n\t\t_crash_director.update(dt)\n\t\tif _crash_director.active and is_nan(_look.x):\n\t\t\t_crash_director.aim(_camera, _inspect)\n\t_update_hud()')
replace(main, '\tif sim.paused:\n\t\tline += "\\nPAUSED%s  [P] resume"', '\tif _crash_director != null and _crash_director.active:\n\t\tline += "\\n" + _crash_director.description()\n\telif sim.paused:\n\t\tline += "\\nPAUSED%s  [P] resume"')
session = app/'sim/flight_session.gd'
replace(session, 'const CRASH_HOLD_S := 1.5', 'const CRASH_HOLD_S := 1.5\n## Presentation may retain the aftermath until explicit reset; technical sessions keep the legacy timer.\nvar crash_auto_restart := true')
replace(session, '\tif not crash.is_empty():\n\t\tcrash.ticks_left -= 1', '\tif not crash.is_empty():\n\t\tif not crash_auto_restart:\n\t\t\treturn\n\t\tcrash.ticks_left -= 1')
replace(session, '\tpause_reason = "CRASH at %.1f m/s (sink %.1f m/s%s) - restarting" % [speed, sink, "" if why.is_empty() else ", " + why]', '\tpause_reason = "CRASH at %.1f m/s (sink %.1f m/s%s) - %s" % [speed, sink, "" if why.is_empty() else ", " + why, "restarting" if crash_auto_restart else "[R] restart"]')
pose_test = app/'tests/test_crash_pose.gd'
replace(pose_test, '\t\tflight.aircraft_id = entry.id', '\t\tflight.aircraft_id = entry.id\n\t\tflight.crash_effects_enabled = false # CR-01 diagnostic pose and legacy timer fixture')
