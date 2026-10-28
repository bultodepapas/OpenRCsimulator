## NK-3 electric components: compare the prepared motor, OCV and pack ECM stages
## against the live GDScript source. No session backend is admitted by this oracle.
extends "oracle.gd"

const Propulsion := preload("res://physics/propulsion.gd")
const PackEcm := preload("res://physics/battery/pack_ecm.gd")

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
