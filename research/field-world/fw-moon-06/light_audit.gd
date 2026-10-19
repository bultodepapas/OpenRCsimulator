## FW-MOON-06 baseline audit: the field-world light, step by step (30 s of sky, as World.flow_to) through the scenes
## where the moon takes over or hands back the light. Pure SkyState (no rendering). Writes one CSV per scenario.
## Run from the repository root:
##   "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
##     --script "$PWD/research/field-world/fw-moon-06/light_audit.gd" -- --out=/abs/dir
##   python3 -I research/field-world/fw-moon-06/analyze_audit.py /abs/dir
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")

const STEP_S := 30.0
## Reference field (40° N, 3.7° W, UTC+2). [start date, start time, duration h].
const SCENARIOS := {
	# The Moonrise preset: full moon rising ENE while the sun sets WSW (sun and moon opposite).
	harvest_moonrise = ["2026-09-26", "19:00", 3.0],
	# A 19 % waxing crescent low in the west after sunset (FW-MOON-03 crescent case): sun and moon on the same side.
	crescent_dusk = ["2026-06-18", "21:00", 3.0],
	# A gibbous moon setting in the west while the sun rises in the east (morning hand-back).
	gibbous_dawn = ["2026-10-29", "06:00", 3.0],
	# Full moon high all night: the steady state.
	full_night = ["2026-10-25", "21:00", 2.0],
}

var _out := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if _out.is_empty() or not _out.is_absolute_path():
		printerr("--out=<absolute directory> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	for id: String in SCENARIOS:
		var s: Array = SCENARIOS[id]
		var c := Conditions.resolve(PackedStringArray(["--date=" + str(s[0]), "--time=" + str(s[1])]))
		var f := FileAccess.open(_out.path_join(id + ".csv"), FileAccess.WRITE)
		f.store_line(",".join(["t_min", "hour", "sun_az", "sun_el", "moon_az", "moon_el", "illum", "light_source", "light_az",
			"light_el", "light_r", "light_g", "light_b", "light_energy", "light_lum", "direct_h_lum", "ambient_lum", "zenith_lum",
			"haze_lum", "lobe_source", "lobe_lum", "exposure", "gain", "shadow", "sun_disc", "moon_disc_lum", "cloud_lum"]))
		var steps := int(float(s[2]) * 3600.0 / STEP_S)
		for k in steps + 1:
			var when: Dictionary = c.when.duplicate()
			when.hour = float(when.hour) + k * STEP_S / 3600.0
			var sky := Ephemeris.sky(when)
			var st := SkyState.state(sky)
			var col: Color = (st.light_color as Color).srgb_to_linear()
			var rgb := Vector3(col.r, col.g, col.b) * float(st.light_energy)
			var lum := 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
			var light_dir: Vector3 = st.light_dir
			f.store_line(",".join(PackedStringArray([str(k * STEP_S / 60.0), "%.5f" % float(when.hour),
				"%.3f" % float(sky.sun.azimuth_deg), "%.3f" % float(st.sun_elevation_deg),
				"%.3f" % float(st.moon_azimuth_deg), "%.3f" % float(st.moon_elevation_deg), "%.4f" % float(st.moon_illuminated),
				str(st.light_source), "%.3f" % rad_to_deg(atan2(light_dir.x, -light_dir.z)), "%.3f" % float(st.light_elevation_deg),
				String.num_scientific(rgb.x), String.num_scientific(rgb.y), String.num_scientific(rgb.z), String.num_scientific(float(st.light_energy)), String.num_scientific(lum),
				String.num_scientific(lum * maxf(light_dir.y, 0.0)), String.num_scientific(_l(st.ambient_lin)), String.num_scientific(_l(st.zenith_lin)),
				String.num_scientific(_l(st.haze_lin)), "moon" if (st.lobe_dir as Vector3).dot(SkyState.direction(float(st.moon_azimuth_deg), 0.0)) > 0.999 else "sun",
				String.num_scientific(_l(st.lobe_lin)), String.num_scientific(float(st.exposure)), String.num_scientific(float(st.gain)), "%.4f" % float(st.shadow_strength),
				"%.1f" % float(st.sun_disc), String.num_scientific(_l(st.moon_lin)), String.num_scientific(_l(st.cloud_lin))])))
		f.close()
		print("wrote ", id)
	quit(0)


static func _l(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z
