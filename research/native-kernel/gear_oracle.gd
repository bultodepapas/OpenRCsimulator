## NK-3 component oracle for catalog retractable contacts and live-mass hulls.
## Compares current source laws and prepared aircraft data byte-for-byte. This
## does not admit a full stage, a flight backend, or physical validation.
extends "stage_oracle.gd"

const RetractableGear := preload("res://physics/retractable_gear.gd")
const LiquidFlight := preload("res://sim/liquid_fuel_flight.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")

const RETRACTABLE_IDS := ["p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx"]
const LIVE_HULL_IDS := ["p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx",
	"stik-glow-61fx-2t", "gp-extra-300s-60"]


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/retractable_gear.gd", "res://physics/effective_mass.gd",
			"res://physics/mass_inventory.gd", "res://physics/liquid_fuel.gd", "res://sim/liquid_fuel_flight.gd",
			"res://physics/glow/flight.gd", "res://physics/glow/fuel_mass.gd", "res://data/field_loader.gd",
			"res://data/lake_loader.gd", "res://data/fields/default.json", "res://data/fields/lake.json",
			"res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/f4u_corsair_250.json",
			"res://data/aircraft/sebart_avanti_s_a200.json", "res://data/aircraft/stik_glow_61fx_2t.json",
			"res://data/aircraft/gp_extra_300s_60.json", "res://data/fuels/openrc-fuel-registry.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-gear-hull-oracle v1"
	_report.gear_cases = []
	_report.live_hull_cases = []
	if _states < 20:
		_failures.append("gear and live-hull oracle needs at least 20 states per installation")
		return
	for id: String in LIVE_HULL_IDS:
		var session := _build_session(id, "runway", false)
		if session == null:
			continue
		if id in RETRACTABLE_IDS:
			_check_retractable(id, session)
		_check_live_hull(id, session)
		session.free()
	if _report.gear_cases.size() != RETRACTABLE_IDS.size():
		_failures.append("not all retractable catalog aircraft were exercised")
	if _report.live_hull_cases.size() != LIVE_HULL_IDS.size():
		_failures.append("not all live-fuel catalog hulls were exercised")


func _gear_pose_values(gear: Dictionary, extension: float) -> PackedFloat64Array:
	var posed: Dictionary = RetractableGear.pose(gear, extension)
	var out := PackedFloat64Array()
	if posed.is_empty():
		return out
	for contact: Dictionary in posed.contacts:
		out.append_array(contact.position)
		for key: String in ["stiffness", "damping", "max_compression", "max_steering", "anchor_stiffness", "anchor_damping"]:
			out.append(float(contact[key]))
	return out


func _gear_extension(index: int) -> float:
	match index % 12:
		0: return 0.0
		1: return 1.0
		2: return 0.25
		3: return 0.5
		4: return 0.75
		5: return 1.0e-12
		6: return 1.0 - 1.0e-12
		_: return _rng.randf_range(0.0, 1.0)


func _check_retractable(id: String, session: Node) -> void:
	var gear: Dictionary = session.aircraft.model.landing_gear
	var surfaces: PackedFloat64Array = session.ground_surfaces
	var lake: Dictionary = session._lake
	if not RetractableGear.enabled(gear):
		_failures.append("expected retractable gear: " + id)
		return
	var base: Dictionary = gear.duplicate(true)
	base.erase("retraction")
	for contact: Dictionary in base.contacts:
		contact.erase("retraction_path")
	var ground: Dictionary = _ground_ready(_native, base, surfaces, lake)
	if not ground.get("ok", false):
		_failures.append("prepare_ground %s: %s" % [id, ground.get("error", "")])
		return
	var prepared: Dictionary = _native.prepare_retractable(gear)
	if not prepared.get("ok", false):
		_failures.append("prepare_retractable %s: %s" % [id, prepared.get("error", "")])
		return
	var context := {rest = session.sim.state.duplicate()}
	var loaded_down := 0
	var unlocked := 0
	var spatial_nonzero := 0
	var spatial_invalid := 0
	var air_free := 0
	for i: int in _states:
		var extension := _gear_extension(i)
		var s := _ground_state(context, surfaces, lake, false)
		if i % 5 == 0:
			s[RB.POS + 2] = -float(gear.reach) - 5.0
			air_free += 1
		var air := PackedFloat64Array([_rng.randf_range(-40.0, 40.0), _rng.randf_range(-20.0, 20.0),
			_rng.randf_range(-10.0, 10.0)])
		var delta := PackedFloat64Array()
		match i % 6:
			1: delta = PackedFloat64Array([0.0, 0.0, 0.0])
			2, 3:
				delta = PackedFloat64Array([_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0),
					_rng.randf_range(-3.0, 3.0)])
				spatial_nonzero += 1
			4:
				delta = PackedFloat64Array([1.0, 2.0])
				spatial_invalid += 1
			5:
				delta = PackedFloat64Array([0.0, NAN, 0.0])
				spatial_invalid += 1
		var density := _rng.randf_range(0.7, 1.4)
		var target := 1.0 if i % 2 == 0 else 0.0
		var dt: float = [1.0 / 240.0, 0.01, 1.0, 10.0][i % 4]
		var pose: Dictionary = RetractableGear.pose(gear, extension)
		var inputs := [id, i, extension, s, air, delta, density, target, dt]
		_compare("gear_pose", _gear_pose_values(gear, extension),
			_native.gear_component(0, s, air, extension, density, delta, target, dt), inputs)
		_compare("gear_drag", RetractableGear.drag_loads(s, air, gear, extension, density, delta),
			_native.gear_component(1, s, air, extension, density, delta, target, dt), inputs)
		_compare("gear_advance", PackedFloat64Array([RetractableGear.advance(extension, target, dt, gear)]),
			_native.gear_component(2, s, air, extension, density, delta, target, dt), inputs)
		var steer := _rng.randf_range(-1.0, 1.0)
		var brake := _rng.randf_range(0.0, 1.0)
		var anchors := PackedFloat64Array()
		var speeds := PackedFloat64Array()
		for contact: Dictionary in pose.contacts:
			var frame: Dictionary = Wheels.frame(s, contact, steer, surfaces, PackedFloat64Array(), true, lake)
			anchors.append(frame.position[0] + _rng.randf_range(-0.005, 0.005))
			anchors.append(frame.position[1] + _rng.randf_range(-0.005, 0.005))
			anchors.append(1.0 if i % 2 == 0 else 0.0)
			speeds.append(frame.long_speed if i % 3 == 0 else _rng.randf_range(-20.0, 20.0))
		var wheel_reference: Dictionary = Wheels.evaluate(s, pose, steer, surfaces, anchors, speeds, brake, false, lake)
		var wheel_native: Dictionary = _native.gear_wheels_component(s, extension, steer, anchors, speeds, brake)
		_compare("gear_wheel_loads", wheel_reference.loads, wheel_native.get("loads"), inputs)
		_compare("gear_wheel_derivative", wheel_reference.derivative, wheel_native.get("derivative"), inputs)
		if extension == 1.0 and wheel_reference.loads.size() == 6:
			loaded_down += 1
		if extension < 1.0:
			unlocked += 1
	# Explicit validation edges preserve the reference's exact result shape and NaN bits.
	var body: PackedFloat64Array = session.sim.state.duplicate()
	var velocity := PackedFloat64Array([1.0, 2.0, 3.0])
	for extension: float in [-1.0, 1.000001, NAN, INF]:
		var inputs := [id, extension]
		_compare("gear_invalid_pose", _gear_pose_values(gear, extension),
			_native.gear_component(0, body, velocity, extension, 1.225, PackedFloat64Array(), 0.0, 0.01), inputs)
		_compare("gear_invalid_drag", RetractableGear.drag_loads(body, velocity, gear, extension, 1.225),
			_native.gear_component(1, body, velocity, extension, 1.225, PackedFloat64Array(), 0.0, 0.01), inputs)
		_compare("gear_invalid_advance", PackedFloat64Array([RetractableGear.advance(extension, 1.0, 0.01, gear)]),
			_native.gear_component(2, body, velocity, extension, 1.225, PackedFloat64Array(), 1.0, 0.01), inputs)
	for parameters: Array in [[0.5, 0.5, 0.01], [0.5, 1.0, 0.0], [0.5, 0.0, -0.01],
			[0.5, 1.0, NAN], [1.0 - 1.0e-12, 1.0, 1.0e-14], [1.0e-12, 0.0, 1.0e-14]]:
		_compare("gear_actuator_edges", PackedFloat64Array([RetractableGear.advance(parameters[0], parameters[1], parameters[2], gear)]),
			_native.gear_component(2, body, velocity, parameters[0], 1.225, PackedFloat64Array(), parameters[1], parameters[2]), [id, parameters])
	var invalid_gear: Dictionary = gear.duplicate(true)
	var invalid_path: PackedFloat64Array = invalid_gear.contacts[0].retraction_path.duplicate()
	invalid_path[0] = NAN
	invalid_gear.contacts[0].retraction_path = invalid_path
	if _native.prepare_retractable(invalid_gear).get("ok", false):
		_failures.append("nonfinite retraction path admitted: " + id)
	if not _native.gear_component(0, body, velocity, 0.5, 1.225, PackedFloat64Array(), 1.0, 0.01).is_empty():
		_failures.append("failed gear prepare retained a stale model: " + id)
	if loaded_down == 0 or unlocked == 0 or spatial_nonzero == 0 or spatial_invalid == 0 or air_free == 0:
		_failures.append("insufficient gear coverage: " + id)
	_report.gear_cases.append({name = id, states = _states, loaded_down = loaded_down, unlocked = unlocked,
		spatial_nonzero = spatial_nonzero, spatial_invalid = spatial_invalid, air_free = air_free,
		contacts = gear.contacts.size(), path_points = gear.contacts[0].retraction_path.size() / 3})


func _properties(session: Node, index: int) -> Dictionary:
	if session.liquid_fuel_is_active():
		var values: PackedFloat64Array = session.sim.continuous.duplicate()
		var config: Dictionary = session.aircraft.model.propulsion.liquid_fuel
		var capacity: float = float(config.capacity_kg) - float(config.unusable_kg)
		var usable: float = capacity * [0.0, 0.25, 0.5, 1.0][index % 4]
		values[session._liquid_index()] = usable
		values[session._liquid_index() + 1] = 0.0 if usable == 0.0 else 1.0
		return LiquidFlight.properties(session, values, true)
	if session.glow_is_active():
		var install: Dictionary = session.aircraft.model.propulsion.glow
		var line_capacity: float = float(install.get("feed_line", {}).get("capacity_kg", 0.0))
		var main: float = float(install.capacity_fuel_kg) * [0.0, 0.25, 0.5, 1.0][index % 4]
		var line: float = line_capacity * [0.0, 0.5, 1.0, 0.25][index % 4]
		return GlowFlight.properties(session, main + line, line)
	return {}


func _compare_hull(id: String, body: PackedFloat64Array, geometry: Dictionary, properties: Dictionary, label: String) -> Dictionary:
	var reference: Dictionary = HullContact.loads_at_properties(body, geometry, properties)
	var native: Dictionary = _native.live_hull_component(body, properties)
	var inputs := [id, label, body, properties]
	_compare("live_hull_status", var_to_bytes([reference.get("ok"), reference.get("reason")]),
		var_to_bytes([native.get("ok"), native.get("reason")]), inputs)
	_compare("live_hull_loads", reference.get("loads"), native.get("loads"), inputs)
	return reference


func _check_live_hull(id: String, session: Node) -> void:
	var source_geometry: Dictionary = session._hull_contact
	if not source_geometry.get("geometry_only", false):
		_failures.append("expected a finite-fuel geometry-only hull: " + id)
		return
	var context := {rest = session.sim.state.duplicate()}
	var surfaces: PackedFloat64Array = session.ground_surfaces
	var lake: Dictionary = session._lake
	var flat_loaded := 0
	var lake_loaded := 0
	var bank_loaded := 0
	var clear := 0
	var accepted_mass := 0
	for mode: String in ["flat", "lake"]:
		var geometry: Dictionary = source_geometry.duplicate(true)
		if mode == "flat":
			geometry.erase("lake")
			geometry.erase("lake_bounds_ne_m")
		var prepared: Dictionary = _native.prepare_live_hull(geometry)
		if not prepared.get("ok", false):
			_failures.append("prepare_live_hull %s/%s: %s" % [id, mode, prepared.get("error", "")])
			return
		for i: int in _states:
			var properties: Dictionary = _properties(session, i)
			if not properties.get("ok", false):
				_failures.append("source mass properties %s: %d" % [id, i])
				return
			accepted_mass += 1
			var body := _ground_state(context, surfaces, lake, false)
			var bank_fixture := false
			# Guarantee free flight, flat contact, lake bed contact, and conservative lake clearance.
			if i % 4 == 0:
				body[RB.POS + 2] = -float(geometry.reach) - 1.0
			elif mode == "flat":
				body[0] = _rng.randf_range(8.0, 22.0)
				body[1] = _rng.randf_range(-45.0, 45.0)
				body[2] = _rng.randf_range(-0.15, 0.15)
			else:
				if i % 3 == 1:
					# Sample halfway between matching shoreline/bank vertices;
					# these authored slopes exercise nonvertical terrain normals.
					var shore: PackedFloat64Array = lake.shoreline_ne_m
					var bank: PackedFloat64Array = lake.bank_ne_m
					var vertex: int = ((i / 3) % (shore.size() / 2)) * 2
					body[0] = (shore[vertex] + bank[vertex]) * 0.5
					body[1] = (shore[vertex + 1] + bank[vertex + 1]) * 0.5
				else:
					body[0] = 110.0 + _rng.randf_range(-2.0, 2.0)
					body[1] = 125.0 + _rng.randf_range(-2.0, 2.0)
				var terrain: Dictionary = LakeSurface.sample_covered_terrain_validated(lake, body[0], body[1])
				if not terrain.get("covered", false):
					_failures.append("lake bed fixture is not covered: " + id)
					return
				bank_fixture = terrain.get("region") == "bank" and \
					(float(terrain.slope_north) != 0.0 or float(terrain.slope_east) != 0.0)
				body[2] = float(terrain.ground_down_m) + _rng.randf_range(-0.1, 0.1)
			var reference := _compare_hull(id, body, geometry, properties, "%s-%d" % [mode, i])
			if reference.get("ok", false) and reference.loads.size() == 6:
				if mode == "flat": flat_loaded += 1
				else:
					lake_loaded += 1
					if bank_fixture: bank_loaded += 1
			elif reference.get("ok", false) and reference.loads.is_empty():
				clear += 1
		var good: Dictionary = _properties(session, 1)
		var bad_samples: Array[Dictionary] = [{}]
		var bad: Dictionary = good.duplicate(true)
		bad.ok = false
		bad_samples.append(bad)
		bad = good.duplicate(true)
		bad.cg_body_m = "invalid"
		bad_samples.append(bad)
		bad = good.duplicate(true)
		bad.mass_kg = -1.0
		bad_samples.append(bad)
		bad = good.duplicate(true)
		bad.cg_body_m[0] = NAN
		bad_samples.append(bad)
		bad = good.duplicate(true)
		bad.inertia = PackedFloat64Array([1.0, 1.0, 9.0, 0.0, 0.0, 0.0])
		bad_samples.append(bad)
		bad = good.duplicate(true)
		bad.inverse[0] *= 2.0
		bad_samples.append(bad)
		for sample: Dictionary in bad_samples:
			_compare_hull(id, session.sim.state, geometry, sample, mode + "-invalid-properties")
		var invalid_body: PackedFloat64Array = session.sim.state.duplicate()
		invalid_body[RB.RATE] = NAN
		_compare_hull(id, invalid_body, geometry, good, mode + "-invalid-body")
		invalid_body.resize(12)
		_compare_hull(id, invalid_body, geometry, good, mode + "-short-body")
		var invalid_geometry: Dictionary = geometry.duplicate(true)
		invalid_geometry.erase("points")
		if _native.prepare_live_hull(invalid_geometry).get("ok", false):
			_failures.append("incomplete hull geometry admitted: " + id + "/" + mode)
		if _native.live_hull_component(session.sim.state, good).get("ok", false):
			_failures.append("failed hull prepare retained a stale model: " + id + "/" + mode)
	if flat_loaded == 0 or lake_loaded == 0 or bank_loaded == 0 or clear == 0:
		_failures.append("insufficient live-hull branch coverage: " + id)
	_report.live_hull_cases.append({name = id, states_per_terrain = _states, valid_mass_samples = accepted_mass,
		flat_loaded = flat_loaded, lake_loaded = lake_loaded, bank_loaded = bank_loaded, unloaded = clear,
		family = "liquid" if session.liquid_fuel_is_active() else "glow"})
