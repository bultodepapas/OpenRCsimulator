## Synthetic composition tests; existing pack authoring is used as software data,
## never as calibrated wheel hardware or a finite-source launch qualification.
extends "res://tests/test_aircraft_ground_electric.gd"
const Candidate := preload("res://physics/aircraft_ground_electric.gd")
const CandidateSource := preload("res://physics/aircraft_ground_source.gd")
const Battery := preload("res://physics/aircraft_ground_battery.gd")
const Pack := preload("res://physics/battery/pack_ecm.gd")
const Supervisor := preload("res://physics/battery/esc_supervisor.gd")
# Complete fixed-law output identities captured BEFORE shared-assembly changes.
# SHA256 of Godot Variant byte serialization encoded as hex; pinned engine law.
const FIXED_PREPARED_HEX_SHA256 := "55c9bc8e3d999080afa8ddd30bfd26a82e3bf37abd02504ca7fec7f0d2b78b76"
const FIXED_RESULTS_HEX_SHA256 := [
	"ea0e39db53693ad30e4da1a36960e3b351f7d7a4e22d0fa756edc86637c266ab",
	"93b792e6ec421bc88ab0ab55cade79eb5338b7c3cd10e1b80fbcd57325e1ddd6",
	"988e1e14508a1b11cdbb8767b078b05ce4702a228a1b16d27294f72ace2eaccc"]
var maximum_motor_port_residual_w := 0.0
var maximum_pack_port_residual_w := 0.0
var maximum_stage_mechanical_residual_w := 0.0


func _initialize() -> void:
	_fixture()
	_electric_fixture()
	if not failed:
		_fixed_parity()
		_selector_refusals()
		for path: String in ["res://data/aircraft/synthetic_stik_electric_4s_battery.json", "res://data/aircraft/battery/skywalker_x8_6s_pack.json"]:
			var loaded := Data.load_file(path)
			check("existing finite pack configuration loads", loaded.ok, str(loaded.get("errors", [])))
			if not loaded.ok: continue
			var installation := model.duplicate(true)
			installation.propulsion.battery = loaded.model.propulsion.battery.duplicate(true)
			installation.propulsion.esc = loaded.model.propulsion.esc.duplicate(true)
			_pack_parity(installation.propulsion)
			_finite_composition(installation)
			_boundaries(installation.propulsion)
			if Prop.has_pack_ecm(installation.propulsion): _outer_supervisor(installation.propulsion)
	print("FINITE_BATTERY_PARITY ", JSON.stringify({maximum_motor_port_residual_w = maximum_motor_port_residual_w,
		maximum_pack_port_residual_w = maximum_pack_port_residual_w, maximum_stage_mechanical_residual_w = maximum_stage_mechanical_residual_w}))
	print("Aircraft ground finite battery: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _fixed_parity() -> void:
	var replacement := Candidate.prepare(profile, model, materials)
	check("fixed-voltage preparation remains byte identical", var_to_bytes(replacement) == var_to_bytes(electric)
		and var_to_bytes(replacement).hex_encode().sha256_text() == FIXED_PREPARED_HEX_SHA256)
	for index: int in 3:
		var rpm: float = [0.0, 3000.0, 8000.0][index]
		var body := _body(-2.0)
		var values := _values(rpm)
		var air := Air.compute(body, M.v3(1.0, -2.0, 0.3), 1.18)
		var a := Electric.evaluate(electric, body, values, 0.0, air, 1.18, defs, .4, true, provider, 9.80665,
			PackedFloat64Array([0.0, 0.0, 0.0]), NAN, 0.0)
		var b := Candidate.evaluate(replacement, body, values, 0.0, air, 1.18, defs, .4, true, provider, 9.80665,
			PackedFloat64Array([0.0, 0.0, 0.0]), NAN, 0.0)
		check("fixed-voltage complete evaluation remains byte identical", a.ok and b.ok and var_to_bytes(a) == var_to_bytes(b)
			and var_to_bytes(b).hex_encode().sha256_text() == FIXED_RESULTS_HEX_SHA256[index])


func _selector_refusals() -> void:
	var body := _body(-2.0)
	var values := _values()
	var air := Air.compute(body, M.v3(1.0, -2.0, .3), 1.18)
	for selector: Variant in [null, [], {}, true, false, 3, 0.0, NAN, PackedFloat64Array([1.0]), "unknown"]:
		var malformed := electric.duplicate(true)
		malformed.law = selector
		check("malformed prepared law type/selector refuses without engine diagnostics", not Candidate._prepared(malformed)
			and not Candidate.evaluate(malformed, body, values, 0.0, air, 1.18, defs, .4, true,
				provider, 9.80665, PackedFloat64Array([0.0, 0.0, 0.0])).ok
			and not Candidate.evaluate_dynamic(malformed, body, values, 0.0, air, 1.18, defs, .4, true,
				provider, 9.80665, PackedFloat64Array([0.0, 0.0, 0.0]), 291.0, 2.7).ok)


func _raw_point(prop: Dictionary, rpm: float, duty: float, enabled: bool, block: PackedFloat64Array,
		available := false) -> Dictionary:
	if Prop.has_pack_ecm(prop): return Prop.electric_pack_state(rpm, duty, prop, enabled, block, 291.0, 2.7, available)
	return Prop.electric_source_state(rpm, duty, prop, enabled,
		maxf(0.0, block[0] / (3600.0 * prop.battery.capacity_ah)), available)


func _pack_parity(prop: Dictionary) -> void:
	var made := Battery.initial_block(prop, 291.0)
	check("existing normalized finite battery initializes", made.ok)
	if not made.ok: return
	var block: PackedFloat64Array = made.block
	check("battery block has exact existing size and initial charge", block.size() == Battery.block_size(prop)
		and block[0] == Battery.initial_charge_c(prop))
	if Prop.has_pack_ecm(prop):
		var old := Pack.initial_block(prop.battery, prop.motor, prop.esc.low_voltage_cutoff, 291.0)
		check("pack initial block is byte identical to existing owner", var_to_bytes(old.block) == var_to_bytes(block))
		block[Pack.RC] = .015
		block[Pack.RC + prop.battery.branches] = .025
	for rpm: float in [0.0, 3000.0, 20000.0]:
		for duty: float in [0.0, .4, 1.0]:
			for enabled: bool in [false, true]:
				var before := var_to_bytes([prop, block])
				var raw := _raw_point(prop, rpm, duty, enabled, block)
				var adapted := Battery.evaluate(prop, rpm, duty, enabled, block, 291.0, 2.7)
				check("existing finite source map succeeds", raw.ok and adapted.ok)
				if not raw.ok or not adapted.ok: continue
				var same := true
				for key: Variant in raw:
					if var_to_bytes(raw[key]) != var_to_bytes(adapted[key]): same = false
				check("ALL existing source map fields retained byte exactly", same)
				var expected_rates: PackedFloat64Array = raw.rates if raw.has("rates") else PackedFloat64Array([-raw.pack_current_a, raw.pack_terminal_power_w, raw.pack_loss_w])
				check("charge/energy/loss and RC/thermal/filter rates retained byte exactly", var_to_bytes(expected_rates) == var_to_bytes(adapted.rates))
				var wrench := Prop.loads(M.v3(7.0, -1.0, 2.0), rpm, prop, 1.18)
				var split := CandidateSource.electric_dynamic(prop, rpm, duty, enabled, wrench, block, 291.0, 2.7)
				check("source uses current alone and full QP bearing capacity", split.ok
					and split.internal_drive_torque_nm == 60.0 / TAU / prop.motor.kv_rpm_per_volt * raw.motor_current_a
					and split.shaft_friction_capacity_nm == 60.0 / TAU / prop.motor.kv_rpm_per_volt * prop.motor.no_load_current_a)
				if split.ok:
					check("finite torque adapter has an explicit distinct law", split.law == CandidateSource.DYNAMIC_LAW)
					maximum_motor_port_residual_w = maxf(maximum_motor_port_residual_w, absf(split.electrical_balance_residual_w))
					check("electrical motor port residual independent of mechanical bearing ledger", absf(split.electrical_balance_residual_w) < 1e-9)
					var motor_port: Dictionary = raw.source if raw.has("source") else raw
					maximum_pack_port_residual_w = maxf(maximum_pack_port_residual_w, absf(raw.pack_terminal_power_w
						- motor_port.bus_power_w - raw.bus_voltage_v * raw.auxiliary_current_a))
					check("pack terminal port includes motor plus auxiliary exactly once", absf(raw.pack_terminal_power_w
						- motor_port.bus_power_w - raw.bus_voltage_v * raw.auxiliary_current_a) < 1e-9)
				check("pack adapter/torque split cannot mutate source or state", before == var_to_bytes([prop, block]))


func _dynamic_values(bound: Dictionary, prop: Dictionary, rpm: float) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	values.resize(bound.continuous_size)
	values[bound.rotor_index] = rpm
	var block: PackedFloat64Array = Battery.initial_block(prop, 291.0).block
	for i in block.size(): values[bound.rotor_index + 1 + i] = block[i]
	for i in bound.ground.radii_m.size(): values[bound.wheel_index + i] = .2 * (i + 1)
	return values


func _finite_composition(installation: Dictionary) -> void:
	var bound := Candidate.prepare_dynamic(profile, installation, materials)
	check("common finite battery stage prepares without launch claim", bound.ok and not bound.get("launch_available", true), str(bound.get("reason", "")))
	if not bound.ok: return
	check("existing wash/RPM/battery/wheel order retained", bound.rotor_index == bound.wash_count
		and bound.wheel_index == bound.wash_count + 1 + Battery.block_size(installation.propulsion))
	for down: float in [-2.0, -.19]:
		var body := RB.make_state(M.v3(0.0, 0.0, down), M.v3(5.0, .2, .1), M.q_from_euler(.01, 0.0, .05), M.v3(.3, -.1, .2))
		# Simulation RK stages are nonunit; geometry uses a local normalized q.
		for i in 4: body[RB.ATT + i] *= 1.00002
		var values := _dynamic_values(bound, installation.propulsion, 3000.0)
		var air := Air.compute(body, M.v3(1.0, -2.0, .3), 1.18)
		var before := var_to_bytes([bound, body, values, air, provider])
		var result := Candidate.evaluate_dynamic(bound, body, values, 0.0, air, 1.18, defs, .4, true, provider, 9.80665,
			PackedFloat64Array([0.0, 0.0, 0.0]), 291.0, 2.7, NAN, 0.0)
		check("finite loaded/airborne nonunit RK stage evaluates", result.ok, str(result.get("reason", "")))
		if not result.ok: continue
		check("entire aircraft stage is read-only", before == var_to_bytes([bound, body, values, air, provider]))
		var expected_rates := _raw_point(installation.propulsion, 3000.0, .4, true,
			values.slice(bound.rotor_index + 1, bound.wheel_index))
		var rates: PackedFloat64Array = expected_rates.rates if expected_rates.has("rates") else PackedFloat64Array([-expected_rates.pack_current_a, expected_rates.pack_terminal_power_w, expected_rates.pack_loss_w])
		check("battery derivatives occupy exactly preexisting slots", var_to_bytes(result.derivative.slice(bound.rotor_index + 1, bound.wheel_index)) == var_to_bytes(rates))
		var local := Prop.stage_air_velocity(body, air, installation.propulsion)
		var old_prop := Prop.loads(local.velocity_body, 3000.0, installation.propulsion, 1.18)
		var tq := Prop.thrust_torque(local.velocity_body, 3000.0, installation.propulsion, 1.18)
		var loads := Dynamics.loads_from_air(body, installation, defs, 3000.0, 1.18, air, NAN,
			values.slice(0, bound.wash_count), 0.0, old_prop, tq.slice(0, 2))
		check("one shared aero/prop/wash assembly retains external wrench", _near(loads, result.external_loads_o, 1e-12))
		var stage: Dictionary = result.rotor.stage
		var angular_rate: PackedFloat64Array = result.rotor.angular_acceleration.duplicate()
		angular_rate.append_array(result.rotor.spin_acceleration)
		var power: float = bound.properties.mass_kg * M.dot(body.slice(RB.VEL, RB.VEL + 3), result.body_derivative.slice(RB.VEL, RB.VEL + 3))
		for i in stage.velocity.size():
			for j in stage.velocity.size(): power += stage.matrix[i * stage.velocity.size() + j] * stage.velocity[j] * angular_rate[i]
		var potential_rate: float = result.ground.potential_rate_w - bound.properties.mass_kg * 9.80665 * result.body_derivative[RB.POS + 2]
		maximum_stage_mechanical_residual_w = maxf(maximum_stage_mechanical_residual_w, absf(power + potential_rate
			+ result.ground.dissipation_w - result.sample.external_power_w))
		check("independent common kinetic gradient closes source/normal/gravity power", absf(power + potential_rate
			+ result.ground.dissipation_w - result.sample.external_power_w) < 1e-8)
		check("bearing row remains exclusively common QP, independent of pack state", result.rows.labels[-1].kind == "internal_shaft_friction"
			and result.rows.limit_rates[-1] == result.source.shaft_friction_capacity_nm)
		var state := body.duplicate()
		state.append_array(values)
		var sample := func(_s: PackedFloat64Array, _t: float) -> Dictionary: return result.sample
		check("old source-free policy explicitly refuses finite source pending locator", not Step._sample(sample, state, 0.0).ok)
		check("fixed public API cannot consume finite binding", not Candidate.evaluate(bound, body, values, 0.0, air, 1.18,
			defs, .4, true, provider, 9.80665, PackedFloat64Array([0.0, 0.0, 0.0])).ok)


func _boundaries(prop: Dictionary) -> void:
	var block: PackedFloat64Array = Battery.initial_block(prop, 291.0).block
	block[0] = 0.0
	var off := Battery.evaluate(prop, 3000.0, 1.0, true, block, 291.0, 2.7)
	check("ordinary zero charge disconnects all electrical load", off.ok and off.pack_current_a == 0.0
		and off.rates[0] == 0.0 and off.rates[1] == 0.0)
	var stopped := CandidateSource.electric_dynamic(prop, 0.0, 1.0, true,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), block, 291.0, 2.7)
	check("exhausted stationary shaft retains full common static-bearing capacity", stopped.ok
		and stopped.internal_drive_torque_nm == 0.0
		and stopped.shaft_friction_capacity_nm == 60.0 / TAU / prop.motor.kv_rpm_per_volt * prop.motor.no_load_current_a)
	var left := Battery.evaluate(prop, 3000.0, 1.0, true, block, 291.0, 2.7, true, true)
	check("connected zero left limit requires explicit trial authorization", left.ok and left.pack_current_a > 0.0 and left.trial_extension_only)
	check("connected left limit cannot masquerade as accepted", not Battery.evaluate(prop, 3000.0, 1.0, true, block, 291.0, 2.7, true).ok)
	block[0] = -1e-12
	check("negative charge ordinary/implicit trial refuses", not Battery.valid(prop, block)
		and not Battery.evaluate(prop, 3000.0, 1.0, true, block, 291.0, 2.7, false, true).ok)
	var trial := Battery.evaluate(prop, -.01, 1.0, true, block, 291.0, 2.7, true, true)
	check("negative charge/RPM trial is explicit and evaluates zero-RPM left map", trial.ok and trial.trial_extension_only)
	check("trial endpoint cannot be supervised/committed", not Battery.supervise_endpoint(prop, block, .4, 1.0 / 240.0).ok)
	for kind: String in ["shape", "nonfinite", "energy", "charge", "phase", "cells"]:
		var bad: PackedFloat64Array = Battery.initial_block(prop, 291.0).block
		match kind:
			"shape": bad.append(0.0)
			"nonfinite": bad[0] = NAN
			"energy": bad[1] = -1.0
			"charge": bad[0] *= 1.1
			"phase":
				if Prop.has_pack_ecm(prop): bad[Pack.phase_index(prop.battery)] = .5
				else: continue
			"cells":
				if Prop.has_pack_ecm(prop): bad[Pack.cells_index(prop.battery)] = 25.0
				else: continue
		check("malformed finite state refuses: " + kind, not Battery.evaluate(prop, 3000.0, .4, true, bad, 291.0, 2.7).ok)


func _outer_supervisor(prop: Dictionary) -> void:
	var fixture := prop.duplicate(true)
	fixture.esc.low_voltage_cutoff.debounce_s = 0.0
	var b: Dictionary = fixture.battery
	var block: PackedFloat64Array = Battery.initial_block(fixture, 291.0).block
	block[Pack.sense_index(b)] = 0.0
	var before := var_to_bytes([fixture, block])
	var direct := Supervisor.step(fixture.esc.low_voltage_cutoff, block[Pack.limit_index(b)], int(block[Pack.phase_index(b)]),
		block[Pack.timer_index(b)], int(block[Pack.cells_index(b)]), block[Pack.sense_index(b)], .7, 1.0 / 240.0)
	var result := Battery.supervise_endpoint(fixture, block, .7, 1.0 / 240.0)
	check("once per outer tick agrees exactly with existing ESC decision", result.ok
		and result.block[Pack.limit_index(b)] == direct[0] and result.block[Pack.phase_index(b)] == direct[1]
		and result.block[Pack.timer_index(b)] == direct[2])
	var unchanged := true
	for i in block.size():
		if i not in [Pack.limit_index(b), Pack.phase_index(b), Pack.timer_index(b)] and result.block[i] != block[i]: unchanged = false
	check("supervisor changes only three sampled slots, no RC/thermal/energy/cells", unchanged)
	check("supervisor is read-only and returns no aliases", before == var_to_bytes([fixture, block]))
	var half := Battery.supervise_endpoint(fixture, block, .7, 1.0 / 480.0)
	var twice := Battery.supervise_endpoint(fixture, half.block, .7, 1.0 / 480.0)
	check("discriminating case rejects mistaken per-subpiece sampling parity", var_to_bytes(twice.block) != var_to_bytes(result.block))
	var stage := Battery.evaluate(fixture, 3000.0, .7, true, block, 291.0, 2.7)
	check("all four sampled ESC/cell derivative slots remain zero", stage.ok
		and stage.rates[Pack.limit_index(b)] == 0.0 and stage.rates[Pack.phase_index(b)] == 0.0
		and stage.rates[Pack.timer_index(b)] == 0.0 and stage.rates[Pack.cells_index(b)] == 0.0)
