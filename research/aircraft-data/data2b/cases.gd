# DATA-2b: exact induced-map parity at varied targets, twists and downwash; refusal parity.
extends SceneTree
var checks := 0
var failures := 0
func check(label: String, before: Variant, after: Variant) -> void:
	checks += 1
	if var_to_bytes(before) != var_to_bytes(after):
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	for key in ["OPENRC_DATA2B_BEFORE", "OPENRC_DATA2B_AFTER"]:
		if not FileAccess.file_exists(OS.get_environment(key)):
			printerr("FAIL missing loader path: ", key)
			quit(2)
			return
	var before: Script = load(OS.get_environment("OPENRC_DATA2B_BEFORE"))
	var after: Script = load(OS.get_environment("OPENRC_DATA2B_AFTER"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 204708
	for file in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var path: String = "res://data/aircraft/" + file + ".json"
		var loaded: Dictionary = before.load_file(path)
		var model: Dictionary = loaded.model
		for i in 32:
			var aero: Dictionary = model.aero.duplicate(true)
			var surfaces: Dictionary = model.surfaces.duplicate(true)
			var env: Dictionary = model.envelope.duplicate(true)
			# Include unbracketed extremes: this optimization must also retain the old boundary result.
			var target: float = [-1.0, 1e-12, 50.0, 100.0][i] if i < 4 else rng.randf_range(0.1, 12.0)
			aero.CLa = target + float(surfaces.horizontal.area) / model.reference.S * float(surfaces.horizontal.lift_slope)
			aero.CL0 = rng.randf_range(-0.5, 0.5)
			surfaces.horizontal.incidence = rng.randf_range(-0.2, 0.2)
			if i % 2 == 0:
				surfaces.horizontal.downwash_gradient = rng.randf_range(0.0, 0.9)
			else:
				surfaces.horizontal.erase("downwash_gradient")
			var twist := PackedFloat64Array()
			for k in env.station_ys.size():
				twist.append(rng.randf_range(-0.1, 0.1))
			surfaces.station_incidence = twist
			var other_env := env.duplicate(true)
			var other_surfaces := surfaces.duplicate(true)
			before._induced_map(env, surfaces, aero, model.reference.S, model.reference.b, model.reference.chords)
			after._induced_map(other_env, other_surfaces, aero, model.reference.S, model.reference.b, model.reference.chords)
			check(file + " derived map/offsets/downwash " + str(i), [env, surfaces], [other_env, other_surfaces])
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for invalid in ["slope", "width", "mass", "cg", "unit", "source"]:
			var candidate := raw.duplicate(true)
			match invalid:
				"slope": candidate.aero.coefficients.CLa.value = 1e-300
				"width": candidate.aero.envelope.stall_blend_width.value = 0.0
				"mass": candidate.inventory[0].mass.value = 0.0
				"cg": candidate.balance.plan_cg.value[0] = -2.0
				"unit": candidate.reference.wing_span.unit = "ft"
				"source": candidate.reference.wing_area.source = ""
			var result: Dictionary = before.validate_and_derive(candidate)
			if result.ok:
				printerr("FAIL invalid fixture accepted: ", invalid)
				failures += 1
			check(file + " refusal " + invalid, result, after.validate_and_derive(candidate))
	print("DATA-2b: %d exact checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
