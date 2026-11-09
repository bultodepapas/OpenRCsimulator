extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Flight := preload("res://sim/flight_session.gd")
const Hull := preload("res://physics/hull_contact.gd")
const Field := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Pack := preload("res://physics/battery/pack_ecm.gd")
const Supervisor := preload("res://physics/battery/esc_supervisor.gd")
const PATH := "res://data/aircraft/battery/stik_electric_6s_pack.json"
const BASIC := "res://data/aircraft/jensen_ugly_stik_60.json"
var checks := 0
var failures := 0

func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func hub(raw: Dictionary) -> PackedFloat64Array:
	var first := PackedFloat64Array([0.0, 0.0, 0.0])
	var mass := 0.0
	for item: Dictionary in raw.inventory:
		mass += float(item.mass.value)
		for axis: int in 3: first[axis] += float(item.mass.value) * float(item.position.value[axis])
	for axis: int in 3:
		first[axis] = first[axis] / mass + float(raw.propulsion.propeller.thrust_line_offset.value[axis])
	return first

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var basic: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASIC))
	check("donor gear is byte-identical", raw.landing_gear == basic.landing_gear)
	check("donor 12-inch prop diameter retained", raw.propulsion.propeller.diameter.value == basic.propulsion.propeller.diameter.value)
	var a := hub(raw)
	var b := hub(basic)
	check("donor fixed-frame prop hub is retained", absf(a[0] - b[0]) < 1e-10 and absf(a[1] - b[1]) < 1e-10 and absf(a[2] - b[2]) < 1e-10)
	var field: Dictionary = Field.load_from().field
	var s := Flight.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.setup(PATH, "stik-electric-6s")
	root.add_child(s)
	check("default field accepted", s.set_field(field))
	s.start_choice = Flight.START_RUNWAY
	s.reset()
	check("pack runway equilibrium admitted", s.is_flyable() and s.start_error.is_empty(), s.start_error)
	if s.is_flyable() and s.start_error.is_empty():
		var disc := Hull.prop_disc(s.aircraft.model.propulsion)
		var initial: PackedFloat64Array = s.sim.state.duplicate()
		var clearance := -float(Hull.prop_disc_depth(initial, disc).depth)
		var compressions: PackedFloat64Array = s.gear_compressions(initial)
		var max_compression := 0.0
		for compression: float in compressions: max_compression = maxf(max_compression, compression)
		check("loaded stationary prop clears ground", clearance > 0.05, str(clearance))
		check("normal static compression below bottom-out", max_compression < 0.12 and max_compression > 0.0, str(compressions))
		check("finite policy owns the required two contact pieces", Ground.substeps(initial, s.current_landing_gear(), s.sim.dt(), s.ground_surfaces, {}) == 2 and s._substeps(initial, s.sim.continuous, 0.0) == 1)
		var owned_policy: Callable = s.sim.model.step_policy
		s.sim.model.step_policy = Callable()
		check("removed policy exposes the true contact requirement", s._substeps(initial, s.sim.continuous, 0.0) == 2)
		s.sim.step()
		check("without a custom policy the kernel performs its normal refinement", s.sim.tick == 1 and s.sim.fault_reason.is_empty(), s.sim.fault_reason)
		s.sim.model.step_policy = owned_policy
		s.reset()
		s.sim.model.step_policy = func(values: PackedFloat64Array, _at: float, _dt: float, _f: Callable, _first: PackedFloat64Array) -> PackedFloat64Array: return values
		check("arbitrary replacement policy exposes true contact requirement", s._substeps(s.sim.state, s.sim.continuous, 0.0) == 2)
		var before := var_to_bytes([s.sim.state, s.sim.continuous, s.sim.aux, s.sim.tick])
		s.sim.step()
		check("kernel still rejects arbitrary policy and rolls back", s.sim.tick == 0 and s.sim.fault_reason.contains("cannot honour 2 contact substeps") and before == var_to_bytes([s.sim.state, s.sim.continuous, s.sim.aux, s.sim.tick]), s.sim.fault_reason)
		s.sim.model.step_policy = owned_policy
		s.reset()
		var combined := initial.duplicate()
		combined.append_array(s.sim.continuous)
		var base: int = RB.SIZE + s._rotor_index() + 1
		var battery: Dictionary = s.aircraft.model.propulsion.battery
		combined[base + Pack.phase_index(battery)] = float(Supervisor.PHASE_DEBOUNCE)
		combined[base + Pack.timer_index(battery)] = 0.5 - s.sim.dt() * 0.25
		combined[base + Pack.sense_index(battery)] = 17.0
		var zero := func(values: PackedFloat64Array, _at: float) -> PackedFloat64Array:
			var out := PackedFloat64Array()
			out.resize(values.size())
			return out
		var outer: Dictionary = s._electric_step(combined, 0.0, s.sim.dt(), zero, zero.call(combined, 0.0))
		var endpoint: PackedFloat64Array = outer.get("state", PackedFloat64Array())
		check("supervisor decides once at the outer endpoint", endpoint.size() == combined.size() and int(endpoint[base + Pack.phase_index(battery)]) == Supervisor.PHASE_SOFT_CUT and endpoint[base + Pack.limit_index(battery)] == 1.0 and endpoint[base + Pack.timer_index(battery)] == 0.0, str(outer))
		print("STIK_GROUND_REST clearance=", clearance, " compression=", compressions)
		s.sim.set_paused(false)
		for tick: int in 240:
			s._physics_process(s.sim.dt())
			s.sim.step()
			if not s.sim.fault_reason.is_empty() or not s.crash.is_empty(): break
		check("one second parked idle remains supported", s.sim.tick == 240 and s.sim.fault_reason.is_empty() and s.crash.is_empty() and s.prop_strike.is_empty(), s.sim.fault_reason)
		s.reset()
		check("reset recovers identical runway pose", s.start_error.is_empty() and s.sim.state == initial and s.sim.tick == 0)
		s.sim.set_paused(false)
		var min_clearance := clearance
		for tick: int in 480:
			s.sim.inputs[3] = 1.0
			s._physics_process(s.sim.dt())
			if not s.crash.is_empty(): break
			s.sim.step()
			min_clearance = minf(min_clearance, -float(Hull.prop_disc_depth(s.sim.state, disc).depth))
			if not s.sim.fault_reason.is_empty(): break
		check("two-second full-duty roll avoids crash and prop strike", s.sim.tick == 480 and s.sim.fault_reason.is_empty() and s.crash.is_empty() and s.prop_strike.is_empty() and min_clearance > 0.0,
			"tick %d, clearance %.6f, fault %s, crash %s" % [s.sim.tick, min_clearance, s.sim.fault_reason, str(s.crash)])
		print("STIK_GROUND_ROLL min_clearance=", min_clearance)
		# Force a disc-ground intersection on a spinning aircraft to exercise the
		# real strike latch and reset. It is a controlled test state, not a landing.
		var strike_state: PackedFloat64Array = s.sim.state.duplicate()
		var depth: Dictionary = Hull.prop_disc_depth(strike_state, disc)
		strike_state[RB.POS + 2] += -float(depth.depth) + 0.001
		check("controlled strike state installs", s.sim.reset(strike_state))
		s.engine_running = true
		s.sim.aux[Flight.AUX_RPM] = 5000.0
		s._check_prop_strike()
		check("prop strike stops electrical power nonterminally", not s.prop_strike.is_empty() and not s.engine_running and s.crash.is_empty(), str(s.prop_strike))
		s.reset()
		check("runway reset clears strike and restarts source", s.start_error.is_empty() and s.prop_strike.is_empty() and s.engine_running)
		var saved: Dictionary = s.checkpoint()
		var twin := Flight.new()
		twin.input_enabled = false
		twin.crash_auto_restart = false
		twin.soft_hull_contacts = true
		twin.setup(PATH, "stik-electric-6s")
		root.add_child(twin)
		twin.set_field(field)
		twin.start_choice = Flight.START_RUNWAY
		twin.reset()
		check("ground checkpoint restores", twin.restore_checkpoint(bytes_to_var(var_to_bytes(saved))))
		for tick: int in 120:
			s.sim.inputs[3] = 0.4
			twin.sim.inputs[3] = 0.4
			s.sim.step()
			twin.sim.step()
			if not s.sim.fault_reason.is_empty() or not twin.sim.fault_reason.is_empty(): break
		check("two-piece ground replay is exact", s.sim.tick == 120 and twin.sim.tick == 120 and s.sim.fault_reason.is_empty() and twin.sim.fault_reason.is_empty() and var_to_bytes(s.checkpoint()) == var_to_bytes(twin.checkpoint()), s.sim.fault_reason + " " + twin.sim.fault_reason)
		twin.free()
	s.free()
	var frozen: Dictionary = Data.load_file(PATH)
	frozen.model.propulsion.battery.initial_soc = 0.0
	var empty := Flight.new()
	empty.input_enabled = false
	empty.setup(PATH, "stik-electric-6s", frozen)
	if empty.is_flyable():
		var point: Dictionary = empty.electrical_state()
		check("depleted start never supplies current", point.get("ok", false) and point.get("exhausted", false) and point.get("pack_current_a", -1.0) == 0.0, str(point))
	else:
		check("depleted start refuses rather than substituting a charged aircraft", not empty.start_error.is_empty() or not empty.aircraft.get("errors", []).is_empty(), empty.start_error)
	empty.free()
	print("STIK_GROUND_TEST %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
