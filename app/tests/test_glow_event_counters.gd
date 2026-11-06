## FUEL-12-R4 / A4: count accepted connected segments, never root trials.
extends "res://tests/test_glow_flight_physics.gd"
const Session := preload("res://sim/flight_session.gd")

var _evidence: Dictionary = {}

func _initialize() -> void:
	for path: String in ["res://data/aircraft/stik_glow_55ax_2t.json", "res://data/aircraft/stik_glow_fs64v_4t.json"]:
		var loaded: Dictionary = AircraftData.load_file(path)
		_check(path + " loads", loaded.ok)
		if loaded.ok:
			_cases(loaded.model)
			_cases(loaded.model, false)
	_public_fill_witnesses()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(_evidence, "\t", true, true) + "\n")
	print("Glow event counters: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _cases(model: Dictionary, prepared: bool = true) -> void:
	var owner := _owner(model, 6000.0, true, 0.75)
	var body := _body(PackedFloat64Array([15.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var initial: PackedFloat64Array = Flight.initial(owner, PackedFloat64Array([6000.0]), body)
	if not prepared: owner.set_meta(Flight.EVALUATOR_IDENTITY_META, {})
	var cycle: float = model.propulsion.glow.profile.identity.cycle_revolutions
	var source: Dictionary = Flight.point(owner, body, initial, 0.0)
	_check("fixture fires every available opportunity", source.ok and source.firing_fraction == 1.0)
	for spec: Array in [["before", cycle - 0.1, 0.004, 0.0025, 1],
		["at", cycle - 0.25, 0.004, 0.0025, 1],
		["after", cycle - 0.35, 0.004, 0.0025, 0],
		["multiple", cycle - 0.1, 0.06, 0.045, 5 if cycle == 1.0 else 3],
		["event-free", cycle - 0.1, 0.004, 1.0, 1]]:
		var values := initial.duplicate()
		values[6] = spec[1]
		values[1] = model.propulsion.glow.unusable_fuel_kg - source.rates.fuel_kg * spec[3]
		var start := body.duplicate()
		start.append_array(values)
		var saved := start.to_byte_array()
		var dt: float = spec[2]
		var rate: Callable = func(state: PackedFloat64Array, at: float) -> PackedFloat64Array:
			var sample: Dictionary = Flight.point(owner, state.slice(0, RB.SIZE), state.slice(RB.SIZE), at)
			if not sample.ok: return PackedFloat64Array([NAN])
			var result := PackedFloat64Array()
			result.resize(state.size())
			result[RB.SIZE + 1] = sample.rates.fuel_kg
			result[RB.SIZE + 6] = 100.0
			result[RB.SIZE + 13] = sample.source.shaft_torque_nm
			result[RB.SIZE + 16] = sample.source.chemical_power_w
			return result
		var result: Variant = Flight.step(start, 0.0, dt, rate, PackedFloat64Array(), owner)
		var tag: String = model.propulsion.glow.profile.family + "/" + str(spec[0]) + ("" if prepared else "/fallback")
		var ok: bool = result is Dictionary and result.has("state")
		_check(tag + " accepted", ok)
		_check(tag + " input immutable", start.to_byte_array() == saved)
		if not ok: continue
		var end: PackedFloat64Array = result.state
		_evidence[tag] = {state_hex = end.to_byte_array().hex_encode(), events = result.events}
		_check(tag + " preserves pre-stop fires", int(end[RB.SIZE + 10]) == int(spec[4]), str(end.slice(RB.SIZE + 6, RB.SIZE + 12)))
		var opportunities: int = int(floor((float(spec[1]) + 100.0 * dt) / cycle))
		_check(tag + " counts all mechanical opportunities", int(end[RB.SIZE + 9]) == opportunities)
		if spec[0] == "before":
			var half: Dictionary = Flight.step(start, 0.0, dt * 0.5, rate, PackedFloat64Array(), owner)
			var twice: Dictionary = Flight.step(half.state, dt * 0.5, dt * 0.5, rate, PackedFloat64Array(), owner)
			_check(tag + " split/full fire count agrees", twice.state[RB.SIZE + 10] == end[RB.SIZE + 10])
	owner.free()

func _public_fill_witnesses() -> void:
	# No injected phase/RPM: public fill/reset places a real crank opportunity
	# before exhaustion within the same accepted 240 Hz flight tick.
	for spec: Array in [["stik_glow_55ax_2t", 7.86168e-7, 1],
		["stik_glow_fs64v_4t", 2.15e-6, 2], ["gp_extra_300s_60", 9.5e-7, 1]]:
		var session := Session.new()
		session.input_enabled = false
		session.crash_auto_restart = false
		session.setup("res://data/aircraft/" + str(spec[0]) + ".json")
		var install: Dictionary = session.aircraft.model.propulsion.glow
		_check(str(spec[0]) + " public near-reserve fill", session.set_fuel_start_fill(
			(float(install.unusable_fuel_kg) + float(spec[1])) / float(install.capacity_fuel_kg)))
		session.reset()
		var checkpoint: Dictionary = session.checkpoint()
		for tick: int in 32: session.sim.step()
		var state: Dictionary = session.glow_state()
		_check(str(spec[0]) + " real flight retains pre-exhaustion fires", session.sim.fault_reason.is_empty()
			and session.sim.tick == 32 and state.fire_count == int(spec[2]) and state.stop_reason == "fuel_exhausted",
			"fires=%s reason=%s" % [state.fire_count, state.stop_reason])
		var expected := var_to_bytes([session.sim.state, session.sim.continuous, session.sim.aux, session.sim.modes])
		_check(str(spec[0]) + " restores new-law checkpoint", session.restore_checkpoint(checkpoint))
		for tick: int in 32: session.sim.step()
		_check(str(spec[0]) + " new-law counter replay is exact", session.sim.fault_reason.is_empty()
			and var_to_bytes([session.sim.state, session.sim.continuous, session.sim.aux, session.sim.modes]) == expected)
		session.free()
