extends SceneTree

const Profile := preload("res://physics/glow/profile.gd")
const Source := preload("res://physics/glow/source.gd")
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func _initialize() -> void:
	for id: String in ["os_max_55ax_candidate", "os_fs_64v_candidate"]:
		var path: String = "res://data/glow/" + id + ".json"
		var loaded: Dictionary = Profile.load_file(path)
		check("candidate profile loads " + id, loaded.ok)
		if not loaded.ok:
			print(loaded.errors)
			continue
		var model: Dictionary = loaded.model
		var before: Dictionary = model.duplicate(true)
		var op: Dictionary = model.operation
		var point: Dictionary = Source.evaluate(model, op.rated_rpm, 1.0, op.nominal_mixture, op.reference_dry_density_kg_m3)
		check("manufacturer rated knot reproduced " + id, point.ok and absf(point.brake_power_w - op.rated_power_w) < 1e-8)
		check("candidate identity retained " + id, point.profile_identity.status == "candidate" and point.profile_identity.input_sha256 == loaded.input_identity.sha256)
		var invalid_identity: Dictionary = model.duplicate(true)
		invalid_identity.identity = "broken"
		check("invalid normalized identity refused " + id, not Source.evaluate(invalid_identity, 5000.0, .5, 1.15, 1.225).ok)
		check("derived premix density " + id, absf(model.fuel.density_kg_m3 - 856.92) < 1e-10)
		check("no mutation during evaluation " + id, model == before)
		check("profile byte identity " + id, loaded.input_identity.sha256 == FileAccess.get_sha256(path))
		check("RPM domain respected " + id, not Source.evaluate(model, op.max_rpm + 1.0, 1.0, 1.15, 1.225).ok)
		var stopped: Dictionary = Source.evaluate(model, 0.0, 1.0, 1.15, 1.225)
		check("stopped profile consumes no fuel " + id, stopped.ok and stopped.delivered_fuel_kg_s == 0.0 and stopped.brake_power_w == 0.0)
		var cut: Dictionary = Source.evaluate(model, op.rated_rpm, 1.0, 1.15, 1.225, false)
		check("cut keeps losses but no combustion " + id, cut.ok and cut.shaft_torque_nm < 0.0 and cut.delivered_fuel_kg_s == 0.0 and cut.firing_frequency_hz == 0.0)
		var raw: Dictionary = model.provenance.duplicate(true)
		var prepared: Dictionary = Profile.prepare(raw)
		raw.parameters.displacement_m3.value *= 2.0
		check("prepare detaches caller data " + id, prepared.model.parameters.displacement_m3 == before.parameters.displacement_m3)
		_invalid(model.provenance)
	check("legacy solver kind cannot identify glow family", not Source.evaluate({family = "glow_prop", parameters = {}, operation = {}}, 5000.0, .5, 1.0, 1.225).ok)
	var two: Dictionary = Profile.load_file("res://data/glow/os_max_55ax_candidate.json").model
	var four: Dictionary = Profile.load_file("res://data/glow/os_fs_64v_candidate.json").model
	var rich_two: Dictionary = Source.evaluate(two, 6000.0, .5, 1.15, 1.225, true, .5)
	var true_four: Dictionary = Source.evaluate(four, 6000.0, .5, 1.15, 1.225)
	check("rich 2T and true 4T can share an exhaust cadence", rich_two.firing_frequency_hz == true_four.firing_frequency_hz)
	check("matching cadence cannot change mechanical cycle", rich_two.cycle_revolutions == 1 and true_four.cycle_revolutions == 2 and rich_two.cycle_frequency_hz == 2.0 * true_four.cycle_frequency_hz)
	check("rich 2T profile stays explicitly two-stroke", rich_two.family == "glow_2t" and rich_two.profile_identity.id == two.identity.id)
	check("unreadable profile refused", not Profile.load_file("res://data/glow/absent.json").ok)
	print("NITRO profiles: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _invalid(original: Dictionary) -> void:
	var mutations: Array[Dictionary] = []
	var d: Dictionary = original.duplicate(true)
	d.parameters.displacement_m3.value = true
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.displacement_m3.unit = "cc"
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.displacement_m3.source = " "
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.displacement_m3.value = INF
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.unrecognized = d.parameters.displacement_m3
	mutations.append(d)
	d = original.duplicate(true)
	d.family = "glow_4t" if original.family == "glow_2t" else "glow_2t"
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.mechanical_torque_nm.value[1][0] = 0.0
	mutations.append(d)
	d = original.duplicate(true)
	d.parameters.mechanical_torque_nm.value[0][1] = -1.0
	mutations.append(d)
	d = original.duplicate(true)
	d.operation.max_rpm.value = d.operation.max_rpm.value * 2.0
	mutations.append(d)
	d = original.duplicate(true)
	d.fuel.lubricant_volume_fraction.value = .95
	mutations.append(d)
	d = original.duplicate(true)
	d.status = "calibrated"
	mutations.append(d)
	d = original.duplicate(true)
	d.fuel.methanol_density_kg_m3.value = 1e-300
	d.fuel.nitromethane_density_kg_m3.value = 1e-300
	d.fuel.lubricant_density_kg_m3.value = 1e100
	mutations.append(d)
	d = original.duplicate(true)
	d.feed = "ys_supercharged"
	mutations.append(d)
	for index: int in mutations.size():
		check("invalid candidate rejected " + str(index), not Profile.prepare(mutations[index]).ok)
