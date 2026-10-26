## Finite electric source state adapter. No integrator, shaft clamp or projection.
## The existing pack laws own charge/terminal-energy/loss rates. Sampled ESC
## decisions occur once AFTER an accepted outer tick, never at RK/root pieces.
extends RefCounted

const Propulsion := preload("res://physics/propulsion.gd")
const Pack := preload("res://physics/battery/pack_ecm.gd")
const Supervisor := preload("res://physics/battery/esc_supervisor.gd")
const LAW := "finite-battery-existing-pack-state-adapter-v1"


static func block_size(prop: Dictionary) -> int:
	if not Propulsion.has_dynamic_battery(prop): return 0
	return Pack.block_size(prop.battery) if Propulsion.has_pack_ecm(prop) else 3


static func initial_charge_c(prop: Dictionary) -> float:
	if not Propulsion.has_dynamic_battery(prop): return NAN
	return Pack.weak_initial_charge_c(prop.battery) if Propulsion.has_pack_ecm(prop) \
		else 3600.0 * float(prop.battery.capacity_ah) * float(prop.battery.initial_soc)


## prop is the normalized, admitted AircraftData installation; no raw authoring
## conversion or alternate pack parameter defaults are introduced here.
static func initial_block(prop: Dictionary, ambient_k: float) -> Dictionary:
	if not Propulsion.has_dynamic_battery(prop) or not is_finite(ambient_k) or ambient_k <= 0.0:
		return _failure("finite battery and finite positive ambient temperature required")
	if Propulsion.has_pack_ecm(prop):
		if Supervisor.validate(prop.esc.get("low_voltage_cutoff")) != "":
			return _failure("invalid existing ESC supervisor profile")
		return Pack.initial_block(prop.battery, prop.motor, prop.esc.low_voltage_cutoff, ambient_k)
	var block := PackedFloat64Array([initial_charge_c(prop), 0.0, 0.0])
	if not valid(prop, block): return _failure("invalid initial finite source block")
	return {ok = true, block = block}


static func valid(prop: Dictionary, block: PackedFloat64Array, trial := false) -> bool:
	var size := block_size(prop)
	if size < 3 or block.size() != size: return false
	for value: float in block:
		if not is_finite(value): return false
	var q0 := initial_charge_c(prop)
	if not is_finite(q0) or q0 < 0.0 or block[0] > q0 or (not trial and block[0] < 0.0) \
		or block[1] < 0.0 or block[2] < 0.0: return false
	if Propulsion.has_pack_ecm(prop):
		var b: Dictionary = prop.battery
		var phase: float = block[Pack.phase_index(b)]
		var cells: float = block[Pack.cells_index(b)]
		var limit: float = block[Pack.limit_index(b)]
		if block[Pack.temperature_index(b)] <= 0.0 or limit < 0.0 or limit > 1.0 \
			or phase != floorf(phase) or phase < float(Supervisor.PHASE_NORMAL) or phase > float(Supervisor.PHASE_HARD_CUT) \
			or cells != floorf(cells) or cells < 1.0 or cells > Supervisor.MAX_CELLS \
			or block[Pack.timer_index(b)] < 0.0: return false
	return true


## Connected left limit is an EXPLICIT algebraic trial mode. A negative charge
## or shaft RPM can never become an accepted state. Q=0 ordinary mode disconnects
## motor AND pack auxiliaries; RC/thermal/filter states retain existing dynamics.
static func evaluate(prop: Dictionary, rpm: float, duty: float, enabled: bool,
		block: PackedFloat64Array, ambient_k: float, cooling_speed_mps: float,
		connected_left_limit := false, trial_extension := false) -> Dictionary:
	if not valid(prop, block, trial_extension) or not is_finite(rpm) \
		or (rpm < 0.0 and not trial_extension) or not is_finite(duty) or duty < 0.0 or duty > 1.0 \
		or not is_finite(ambient_k) or ambient_k <= 0.0 or not is_finite(cooling_speed_mps) or cooling_speed_mps < 0.0 \
		or (connected_left_limit and not trial_extension) or (block[0] < 0.0 and not connected_left_limit):
		return _failure("invalid finite source state or unowned trial continuation")
	var map_rpm := maxf(0.0, rpm)
	var point: Dictionary
	if Propulsion.has_pack_ecm(prop):
		point = Propulsion.electric_pack_state(map_rpm, duty, prop, enabled, block,
			ambient_k, cooling_speed_mps, connected_left_limit)
	else:
		var soc := maxf(0.0, block[0] / (3600.0 * float(prop.battery.capacity_ah)))
		point = Propulsion.electric_source_state(map_rpm, duty, prop, enabled, soc, connected_left_limit)
		if point.get("ok", false):
			point.rates = PackedFloat64Array([-point.pack_current_a, point.pack_terminal_power_w, point.pack_loss_w])
	if not point.get("ok", false): return _failure("existing finite pack map refused", point)
	point.trial_extension_only = rpm < 0.0 or block[0] < 0.0 or connected_left_limit
	return point


## Returns a COPY. Caller invokes exactly once for the entire accepted outer dt.
## Cell detection remains the connection-time value. No continuous field changes.
static func supervise_endpoint(prop: Dictionary, block: PackedFloat64Array, duty: float,
		outer_dt_s: float) -> Dictionary:
	if not valid(prop, block) or not is_finite(duty) or duty < 0.0 or duty > 1.0 \
		or not is_finite(outer_dt_s) or outer_dt_s <= 0.0 or outer_dt_s > 1.0:
		return _failure("invalid accepted outer endpoint")
	var out := block.duplicate()
	if Propulsion.has_pack_ecm(prop):
		var b: Dictionary = prop.battery
		var profile: Dictionary = prop.esc.get("low_voltage_cutoff", {})
		if Supervisor.validate(profile) != "": return _failure("invalid existing ESC supervisor profile")
		var decision := Supervisor.step(profile, out[Pack.limit_index(b)], int(out[Pack.phase_index(b)]),
			out[Pack.timer_index(b)], int(out[Pack.cells_index(b)]), out[Pack.sense_index(b)], duty, outer_dt_s)
		out[Pack.limit_index(b)] = decision[0]
		out[Pack.phase_index(b)] = decision[1]
		out[Pack.timer_index(b)] = decision[2]
	return {ok = true, block = out}


static func _failure(reason: String, context: Dictionary = {}) -> Dictionary:
	return {ok = false, law = LAW, reason = reason, context = context}
