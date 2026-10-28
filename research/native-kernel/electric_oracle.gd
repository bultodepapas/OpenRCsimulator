## NK-3 electric components: compare the prepared motor, OCV and pack ECM stages
## against the live GDScript source. No session backend is admitted by this oracle.
extends "oracle.gd"

const Propulsion := preload("res://physics/propulsion.gd")
const PackEcm := preload("res://physics/battery/pack_ecm.gd")
const ElectricDynamics := preload("res://physics/dynamics.gd")

const ELECTRIC_IDS := ["turbo-lumber-evolution", "skywalker-x8"]
const ECM_FIELDS := ["kind", "series", "branches", "group_capacity_c", "initial_soc", "weak_capacity_factor",
	"weak_resistance_factor", "weak_soc_offset", "interconnect_ohm", "auxiliary_current_a",
	"cooling_airflow_fraction", "thermal_capacity_j_per_k", "h_still_w_per_k",
	"h_forced_w_per_k_sqrt_mps", "lvc_filter_s", "soc_knots", "temperature_knots_k", "ocv", "r0", "rc_r", "rc_tau"]


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/electric_motor.gd", "res://physics/electric_supply.gd",
			"res://physics/battery/pack_ecm.gd", "res://physics/battery/battery_data.gd",
			"res://physics/battery/esc_supervisor.gd", "res://physics/aircraft_data.gd",
			"res://physics/rotor_coupling.gd", "res://physics/rigid_body.gd",
			"res://data/aircraft/turbo_lumber_evolution.json", "res://data/aircraft/skywalker_x8.json",
			"res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json",
			"res://data/aircraft/battery/skywalker_x8_6s_pack.json",
			"res://data/batteries/packs/lipo-4s1p-3200-30c-class.json",
			"res://data/batteries/packs/lipo-6s1p-5000-30c-class.json",
			"res://data/batteries/cells/lipo-bak503562-galeotti-v1.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-electric-oracle v1"
	if _states < 1:
		_failures.append("electric oracle needs at least one state per configuration")
		return
	var cases: Array[Dictionary] = []
	for id: String in ELECTRIC_IDS:
		for mode: String in ["ideal", "pack"]:
			var path: String = Catalog.data_for(id, mode)
			var loaded: Dictionary = AircraftData.load_file(path)
			if not loaded.get("ok", false) or not Propulsion.is_electric(loaded.get("model", {}).get("propulsion", {})):
				_failures.append("electric catalog model failed: " + id + "/" + mode)
				continue
			cases.append({name = id + "/" + mode, prop = loaded.model.propulsion.duplicate(true)})
	if cases.size() != 4:
		return
	var ocv_prop: Dictionary = cases[0].prop.duplicate(true)
	ocv_prop.battery = {kind = "ocv_resistance", capacity_ah = 2.0, resistance_ohm = 0.05,
		auxiliary_current_a = 0.3, initial_soc = 0.9,
		ocv_points = PackedFloat64Array([0.0, 12.0, 0.5, 14.8, 1.0, 16.8])}
	ocv_prop.esc = {kind = "ideal_motoring", command_mapping = "identity"}
	cases.append({name = "synthetic_ocv", prop = ocv_prop})
	for branches: int in [0, 2]:
		var prop: Dictionary = cases[1].prop.duplicate(true)
		var original_r: PackedFloat64Array = prop.battery.rc_r[0].duplicate()
		var original_tau: PackedFloat64Array = prop.battery.rc_tau[0].duplicate()
		prop.battery.branches = branches
		prop.battery.rc_r = []
		prop.battery.rc_tau = []
		for _k: int in branches:
			prop.battery.rc_r.append(original_r.duplicate())
			prop.battery.rc_tau.append(original_tau.duplicate())
		cases.append({name = "synthetic_ecm_%d_branches" % branches, prop = prop})
	_report.electric_cases = []
	for test: Dictionary in cases:
		_check_case(str(test.name), test.prop)
	_report.electric_coupled_cases = []
	for id: String in ELECTRIC_IDS:
		for mode: String in ["ideal", "pack"]:
			_check_coupled_case(id, mode)


func _snapshot(prop: Dictionary) -> Dictionary:
	var battery: Dictionary = prop.battery
	var fields: Array = []
	match str(battery.kind):
		"fixed_voltage": fields = ["kind", "voltage_v"]
		"ocv_resistance": fields = ["kind", "capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc", "ocv_points"]
		"pack_ecm": fields = ECM_FIELDS
	var selected := {}
	for field: String in fields:
		if not battery.has(field):
			return {}
		selected[field] = battery[field]
	return {format = "openrc-nk3-electric-snapshot-v1", motor = prop.motor.duplicate(true), battery = selected,
		esc = {kind = prop.esc.kind, command_mapping = prop.esc.command_mapping}}


func _valid_block(battery: Dictionary, block: PackedFloat64Array) -> bool:
	if battery.kind == "fixed_voltage":
		return block.is_empty()
	var is_pack: bool = battery.kind == "pack_ecm"
	var expected: int = PackEcm.block_size(battery) if is_pack else 3
	if block.size() != expected:
		return false
	for value: float in block:
		if not is_finite(value):
			return false
	if is_pack:
		var phase: float = block[PackEcm.phase_index(battery)]
		var cells: float = block[PackEcm.cells_index(battery)]
		var limit: float = block[PackEcm.limit_index(battery)]
		if block[PackEcm.temperature_index(battery)] <= 0.0 or limit < 0.0 or limit > 1.0 \
				or phase != floorf(phase) or phase < 0.0 or phase > 3.0 or cells != floorf(cells) or cells < 1.0 \
				or block[PackEcm.timer_index(battery)] < 0.0:
			return false
	var initial: float = PackEcm.weak_initial_charge_c(battery) if is_pack else 3600.0 * float(battery.capacity_ah) * float(battery.initial_soc)
	return block[0] <= initial and block[1] >= 0.0 and block[2] >= 0.0


func _reference(prop: Dictionary, rpm: float, duty: float, block: PackedFloat64Array,
		enabled: bool, ambient: float, cooling: float) -> Dictionary:
	var battery: Dictionary = prop.battery
	if not _valid_block(battery, block):
		return {ok = false}
	var point: Dictionary
	var rates := PackedFloat64Array()
	var pack_current: float
	match str(battery.kind):
		"fixed_voltage":
			point = Propulsion.electric_source_state(rpm, duty, prop, enabled)
			if not point.get("ok", false):
				return {ok = false}
			pack_current = float(point.battery_current_a)
		"ocv_resistance":
			var soc: float = maxf(0.0, block[0] / (3600.0 * float(battery.capacity_ah)))
			point = Propulsion.electric_source_state(rpm, duty, prop, enabled, soc, block[0] < 0.0)
			if not point.get("ok", false):
				return {ok = false}
			pack_current = float(point.pack_current_a)
			rates = PackedFloat64Array([-pack_current, point.pack_terminal_power_w, point.pack_loss_w])
		"pack_ecm":
			point = Propulsion.electric_pack_state(rpm, duty, prop, enabled, block, ambient, cooling, block[0] < 0.0)
			if not point.get("ok", false):
				return {ok = false}
			pack_current = float(point.pack_current_a)
			rates = point.rates
		_:
			return {ok = false}
	return {ok = true, values = PackedFloat64Array([point.shaft_torque_nm, point.motor_current_a,
		pack_current, point.bus_voltage_v]), rates = rates}


func _block_for(battery: Dictionary, index: int) -> PackedFloat64Array:
	if battery.kind == "fixed_voltage":
		return PackedFloat64Array()
	var pack: bool = battery.kind == "pack_ecm"
	var initial: float = PackEcm.weak_initial_charge_c(battery) if pack else 3600.0 * float(battery.capacity_ah) * float(battery.initial_soc)
	var block := PackedFloat64Array()
	block.resize(PackEcm.block_size(battery) if pack else 3)
	block[0] = _rng.randf_range(0.0, initial)
	block[1] = _rng.randf_range(0.0, 1e5)
	block[2] = _rng.randf_range(0.0, 1e4)
	if index % 13 == 0:
		block[0] = [0.0, -0.001, initial, initial + 1.0][(index / 13) % 4]
	if pack:
		var branches: int = battery.branches
		for k: int in 2 * branches:
			block[PackEcm.RC + k] = _rng.randf_range(-0.2, 0.2)
		block[PackEcm.temperature_index(battery)] = _rng.randf_range(260.0, 330.0)
		block[PackEcm.sense_index(battery)] = _rng.randf_range(5.0, 26.0)
		block[PackEcm.limit_index(battery)] = _rng.randf_range(0.0, 1.0)
		block[PackEcm.phase_index(battery)] = float(_rng.randi_range(0, 3))
		block[PackEcm.timer_index(battery)] = _rng.randf_range(0.0, 5.0)
		block[PackEcm.cells_index(battery)] = float(battery.series)
	return block


func _check_case(name: String, prop: Dictionary) -> void:
	var snapshot: Dictionary = _snapshot(prop)
	var prepared: Dictionary = _native.prepare_electric(snapshot)
	if not prepared.get("ok", false):
		_failures.append("electric prepare %s failed: %s" % [name, prepared.get("error", "")])
		return
	var accepted: int = 0
	var rejected: int = 0
	for i: int in _states:
		var rpm: float = _rng.randf_range(0.0, 25000.0)
		var duty: float = _rng.randf_range(0.0, 1.0)
		var enabled: bool = i % 5 != 0
		var ambient: float = _rng.randf_range(250.0, 330.0)
		var cooling: float = _rng.randf_range(0.0, 30.0)
		var block: PackedFloat64Array = _block_for(prop.battery, i)
		if i % 17 == 0:
			rpm = [0.0, 0.5, 1.0, 20000.0][(i / 17) % 4]
		if i % 19 == 0:
			duty = [0.0, 0.5, 1.0][_rng.randi_range(0, 2)]
		if i % 31 == 0:
			match (i / 31) % 6:
				0: rpm = _special()
				1: duty = _special()
				2:
					if not block.is_empty(): block[_rng.randi_range(0, block.size() - 1)] = _special()
				3: ambient = _special()
				4: cooling = _special()
				5:
					if prop.battery.kind == "pack_ecm": block[PackEcm.phase_index(prop.battery)] = 0.5
		var reference: Dictionary = _reference(prop, rpm, duty, block, enabled, ambient, cooling)
		var native: Dictionary = _native.electric_component(rpm, duty, block, enabled, ambient, cooling)
		var ref_ok: bool = reference.get("ok", false)
		var native_ok: bool = native.get("ok", false)
		_compare("electric_validity", PackedFloat64Array([1.0 if ref_ok else 0.0]),
			PackedFloat64Array([1.0 if native_ok else 0.0]), [name, i, rpm, duty, block, enabled, ambient, cooling])
		if ref_ok and native_ok:
			_compare("electric_values", reference.values, native.values, [name, i, rpm, duty, block, enabled, ambient, cooling])
			_compare("electric_rates", reference.rates, native.rates, [name, i, rpm, duty, block, enabled, ambient, cooling])
			accepted += 1
		else:
			rejected += 1
		_tally("electric_" + name, "states")
	if accepted == 0 or rejected == 0:
		_failures.append("electric case %s did not exercise accepted and rejected stages" % name)
	_report.electric_cases.append({name = name, kind = prop.battery.kind, states = _states,
		accepted = accepted, rejected = rejected})
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.motor.resistance_ohm = 0.0
	if _native.prepare_electric(malformed).get("ok", false):
		_failures.append("electric invalid motor was admitted: " + name)
	if _native.electric_component(0.0, 0.0, PackedFloat64Array(), true, 288.15, 0.0).get("ok", false):
		_failures.append("electric failed prepare retained a stale model: " + name)
	malformed = snapshot.duplicate(true)
	malformed.esc.command_mapping = "unsupported"
	if _native.prepare_electric(malformed).get("ok", false):
		_failures.append("electric unsupported ESC was admitted: " + name)
	malformed = snapshot.duplicate(true)
	malformed.battery.unknown = 1.0
	if _native.prepare_electric(malformed).get("ok", false):
		_failures.append("electric unknown battery field was admitted: " + name)


## The preview is a supported FlightSession entry: pre-reaction loads are
## explicit stage inputs, so these comparisons isolate the actual session's
## source, stop-friction and rotor response without approximating its airframe.
func _check_coupled_case(id: String, mode: String) -> void:
	var name := id + "/" + mode
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(Catalog.data_for(id, mode), id)
	if not session.is_flyable() or session.sim.state.size() != 13:
		_failures.append("coupled electric session failed: " + name)
		session.free()
		return
	var prop: Dictionary = session.aircraft.model.propulsion
	var geometry := {}
	for key: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
		if prop.has(key): geometry[key] = prop[key]
	var prop_prep: Dictionary = _native.prepare_propeller(geometry)
	var electric_prep: Dictionary = _native.prepare_electric(_snapshot(prop))
	if not prop_prep.get("ok", false) or not electric_prep.get("ok", false):
		_failures.append("coupled electric native preparation failed: " + name)
		session.free()
		return
	var initial: PackedFloat64Array = session.sim.continuous.duplicate()
	var at: int = session._rotor_index()
	var block_size: int = session._battery_block_size()
	if initial.size() != at + 1 + block_size + session.wheel_count():
		_failures.append("coupled electric state layout differs: " + name)
		session.free()
		return
	var base_block: PackedFloat64Array = initial.slice(at + 1, at + 1 + block_size)
	var inertia: PackedFloat64Array = session.sim.inertia
	var inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var rotor_inertia: float = prop.rotor_inertia
	var locked := 0
	var forward := 0
	var reverse := 0
	var negative := 0
	var accepted := 0
	var rejected := 0
	for i: int in _states:
		var body: PackedFloat64Array = session.sim.state.duplicate()
		for k: int in 3:
			body[RB.VEL + k] = _rng.randf_range(-20.0, 30.0)
			body[RB.RATE + k] = _rng.randf_range(-4.0, 4.0)
		var boundary: int = i % 11
		var trial_rpm: float = _rng.randf_range(0.5, prop.max_rpm)
		if boundary <= 2:
			trial_rpm = 0.0
			for k: int in 3: body[RB.RATE + k] = 0.0
		elif boundary == 3:
			trial_rpm = -_rng.randf_range(0.001, 30.0)
		elif i % 71 == 0:
			trial_rpm = _special()
		var values: PackedFloat64Array = initial.duplicate()
		values[at] = trial_rpm
		var block: PackedFloat64Array = base_block.duplicate() if boundary <= 2 else _block_for(prop.battery, i)
		for k: int in block.size(): values[at + 1 + k] = block[k]
		session.sim.inputs[3] = _rng.randf_range(0.0, 1.0)
		session.engine_running = i % 5 != 0
		var duty: float = session.propulsion_throttle()
		var enabled: bool = session.propulsion_power_enabled()
		var air: Dictionary = session.air_data(body, 0.0)
		var flow: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
		if not flow.get("ok", false):
			_failures.append("reference electric inflow invalid: %s state %d" % [name, i])
			continue
		var local: PackedFloat64Array = flow.velocity_body
		var rho: float = session.air_density(body)
		var charge: float = session.engine_charge_ratio(body)
		var ambient: float = session._pack_ambient_k(body)
		var cooling: float = float(prop.battery.cooling_airflow_fraction) * M.norm(air.v_air) if mode == "pack" else 0.0
		var external := PackedFloat64Array()
		for k: int in 6: external.append(_rng.randf_range(-15.0, 15.0))
		if boundary <= 2:
			var source: Dictionary = _reference(prop, 0.0, duty, block, enabled, ambient, cooling)
			if not source.get("ok", false):
				_failures.append("valid electric boundary source failed: " + name)
				break
			var kt: float = 60.0 / (TAU * float(prop.motor.kv_rpm_per_volt))
			var friction: float = kt * float(prop.motor.no_load_current_a)
			var drive: float = kt * float(source.values[1])
			var required: float = drive if boundary == 0 else (drive - 2.0 * friction if boundary == 1 else drive + 2.0 * friction)
			var target_alpha: PackedFloat64Array = M.scale(axis, required / rotor_inertia)
			var target_moment: PackedFloat64Array = RB.inertia_mul(inertia, target_alpha)
			for k: int in 3: external[3 + k] = target_moment[k]
		var preview := {air = air, pre_reaction_loads = external, wheel_derivative = PackedFloat64Array()}
		var reference: Dictionary = session._coupled_response(body, values, 0.0, {}, true, preview)
		var stage := PackedFloat64Array([trial_rpm, local[0], local[1], local[2], rho, charge, duty, ambient, cooling])
		var native: Dictionary = _native.electric_coupling_component(body, stage, block, inertia, inverse, external, enabled)
		var inputs := [name, i, body, stage, block, external, enabled]
		var ref_ok: bool = reference.get("ok", false)
		var native_ok: bool = native.get("ok", false)
		_compare("electric_coupled_validity", PackedFloat64Array([1.0 if ref_ok else 0.0]),
			PackedFloat64Array([1.0 if native_ok else 0.0]), inputs)
		if ref_ok and native_ok:
			var rotor: PackedFloat64Array = ElectricDynamics.rotor_momentum(session.aircraft.model, maxf(0.0, trial_rpm))
			var expected := PackedFloat64Array([reference.spin_acceleration])
			expected.append_array(reference.reaction)
			expected.append_array(rotor)
			expected.append(reference.rpm_rate)
			expected.append_array(reference.loads)
			_compare("electric_coupled_values", expected, native.values, inputs)
			var rates := PackedFloat64Array()
			session._append_battery_rates(rates, reference)
			_compare("electric_coupled_battery_rates", rates, native.rates, inputs)
			accepted += 1
		else:
			rejected += 1
		if boundary == 0 and ref_ok and reference.spin_acceleration == 0.0: locked += 1
		if boundary == 1 and ref_ok and reference.spin_acceleration > 0.0: forward += 1
		if boundary == 2 and not ref_ok: reverse += 1
		if boundary == 3 and ref_ok: negative += 1
		_tally("electric_coupled_" + name, "states")
	if accepted == 0 or rejected == 0 or locked == 0 or forward == 0 or reverse == 0 or negative == 0:
		_failures.append("coupled electric %s missed a required stop-boundary or validity branch" % name)
	_report.electric_coupled_cases.append({name = name, states = _states, accepted = accepted, rejected = rejected,
		locked = locked, forward_breakaway = forward, reverse_refused = reverse, negative_trial = negative})
	session.free()
