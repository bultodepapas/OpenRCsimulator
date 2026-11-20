# Source-pinned characterization, not a fracture or recoverability test.
# Copy into app/tests and run as res://tests/probe_nonfatal_water_prop_draft.gd.
# Water: accepted Simulation tick with one synthetic hull point and no forces;
# prop: direct production boundary guard with an injected auxiliary RPM/pose.
# Wave: direct query, independent sinusoidal gap-rate calculation. No fluid
# particle velocity, real aircraft recovery, blade phase, or damage is claimed.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Hull := preload("res://physics/hull_contact.gd")
const Loader := preload("res://data/lake_loader.gd")
const Surface := preload("res://physics/lake_surface.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const Session := preload("res://sim/flight_session.gd")

const DT := 1.0 / 240.0
const N := 110.0
const E := 125.0
const MASS := 5.0
var checks := 0
var failures := 0
var _inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var _point := PackedFloat64Array([0.0, 0.0, 0.0])


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok   " if passed else "FAIL ") + label + (" " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from("res://data/fields/lake.json")
	check("authored lake loaded", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		quit(1)
		return
	var calm: Dictionary = loaded.lake.duplicate(true)
	calm.waves = []
	calm.identity = Loader.identity(calm)
	for speed: float in [10.0, 300.0 / 3.6]:
		# Gap positive means above water; negative means already below the plane.
		_water_tick(calm, speed, 0.001, false)
		_water_tick(calm, speed, 0.0, true)
		_water_tick(calm, speed, -0.00001, true)
	_prop_case(299.999, 10.0, 0.001, true, false)
	_prop_case(300.0, 10.0, 0.001, true, true)
	_prop_case(5000.0, 10.0, 0.000001, true, true)
	_prop_case(5000.0, 300.0 / 3.6, 0.000001, true, true)
	_prop_case(5000.0, 10.0, -0.001, true, false)
	_prop_case(5000.0, 10.0, 0.001, false, false)
	_wave_gap_rate(loaded.lake, calm)
	print("NONFATAL CHARACTERIZATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _state(position: PackedFloat64Array, velocity: PackedFloat64Array,
		rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(position, velocity, PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), rates)


func _water_tick(lake: Dictionary, speed: float, gap_m: float, expect_event: bool) -> void:
	# Follow test_lake_session's synthetic collision fixture, but allow the
	# production integrator and normal post-tick callback to create the sweep.
	var session := Session.new()
	session.physics_enabled = false
	session.crash_auto_restart = false
	session.input_enabled = false
	root.add_child(session)
	session.setup()
	session.aircraft.model.crash_hull = _point.duplicate()
	session.aircraft.model.landing_gear = {}
	session._prop_disc = {}
	var installed: bool = session.set_lake_context(lake)
	check("water fixture installs callback", installed and session.sim.model.post_tick.is_valid())
	if not installed or not session.sim.model.post_tick.is_valid():
		session.free()
		return
	session.sim.continuous = PackedFloat64Array()
	for field: String in ["step_policy", "stage", "block_loads", "block_derivative", "stage_rotor_momentum", "block_aux"]:
		session.sim.model.set(field, Callable())
	session.sim.gravity = 0.0
	session.sim.model.loads = func(_body: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return aux.duplicate()
	session.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	var initial := _state(PackedFloat64Array([N, E, float(lake.water_level_down_m) - gap_m]),
		PackedFloat64Array([0.0, speed, 0.0]))
	var installed_state: bool = session.sim.reset(initial)
	check("water synthetic state resets", installed_state, session.sim.fault_reason)
	if not installed_state:
		session.free()
		return
	session.sim.set_paused(false)
	session.sim.step()
	var event: LakeCollision.WaterEvent = session.last_lake_event()
	var accepted: bool = session.sim.tick == 1 and session.sim.fault_reason.is_empty()
	var terminal: bool = event != null and event.trigger == "water" and event.terminal \
		and not session.crash.is_empty() and session.sim.paused and not session.engine_running
	var clear: bool = event == null and session.crash.is_empty() and not session.sim.paused
	var normal_speed: float = event.normal_speed_mps if event != null else -1.0
	print("WATER ", JSON.stringify({"speed_mps": speed, "gap_m": gap_m, "synthetic_point": true,
		"accepted_tick": session.sim.tick, "event": event != null, "terminal": terminal,
		"normal_speed_mps": normal_speed, "fault": session.sim.fault_reason}))
	check("water accepted tick commits", accepted)
	check("water current classification speed %.6f gap %.8f" % [speed, gap_m],
		terminal if expect_event else clear)
	if expect_event and event != null:
		check("tangent current event has zero point normal speed", absf(normal_speed) <= 1.0e-8)
	session.free()


func _prop_case(rpm: float, speed: float, desired_depth: float, source_on: bool, expected: bool) -> void:
	# Direct boundary/telemetry characterization only: it does not step the
	# shaft, prove coast behavior or claim a physical blade hit at known phase.
	var session := Session.new()
	session.input_enabled = false
	session.soft_hull_contacts = true
	session.setup()
	root.add_child(session)
	var body := _state(PackedFloat64Array([0.0, 0.0, -20.0]),
		PackedFloat64Array([speed, 0.0, 0.0]), PackedFloat64Array([0.0, 2.0, 0.0]))
	var first: Dictionary = Hull.prop_disc_depth(body, session._prop_disc)
	body[RB.POS + 2] += -float(first.depth) + desired_depth
	var geom: Dictionary = Hull.prop_disc_depth(body, session._prop_disc)
	var isolated: bool = absf(float(geom.depth) - desired_depth) < 1.0e-9 \
		and Hull.contacts(body, body, session._hull_contact).is_empty() and not session.gear_collapsed(body)
	var installed: bool = session.sim.reset(body)
	check("prop fixture is isolated and resets", isolated and installed)
	if not isolated or not installed:
		session.free()
		return
	session.engine_running = source_on
	session.sim.aux[Session.AUX_RPM] = rpm
	session._check_prop_strike()
	var struck: bool = not session.prop_strike.is_empty()
	var linear := PackedFloat64Array([speed, 0.0, 0.0])
	var point_arm: PackedFloat64Array = M.sub(geom.point_ned, body.slice(RB.POS, RB.POS + 3))
	var rigid_point_velocity: PackedFloat64Array = M.add(linear, M.cross(
		PackedFloat64Array([0.0, 2.0, 0.0]), point_arm))
	var recorded: PackedFloat64Array = session.prop_strike.get("velocity_ned", PackedFloat64Array())
	print("PROP ", JSON.stringify({"rpm_aux_injected": rpm, "speed_mps": speed,
		"depth_m": float(geom.depth), "source_on_injected": source_on, "struck": struck,
		"source_after": session.engine_running, "reference_velocity_ned": Array(linear),
		"rigid_point_velocity_ned_excluding_blade_spin": Array(rigid_point_velocity),
		"recorded_velocity_ned": Array(recorded)}))
	check("prop current guard classification rpm %.3f depth %.8f source %s" % [rpm, desired_depth, str(source_on)],
		struck == expected and (session.engine_running == (source_on and not expected)))
	if struck:
		check("prop payload uses reference velocity", recorded == linear and M.norm(M.sub(rigid_point_velocity, linear)) > 0.01)
	session.free()


func _wave_gap_rate(source: Dictionary, calm: Dictionary) -> void:
	# The interior is beyond shore fade. One wave starts at phase pi, so its
	# surface rises through a stationary point during this 1/240 s interval.
	# The oracle is the analytic derivative of this explicitly authored sine,
	# not a claim about water-particle velocity or measured hydrodynamic loads.
	var wave_lake: Dictionary = source.duplicate(true)
	var amplitude := 0.03
	var wavelength := 12.0
	var period := 4.0
	var phase_offset: float = PI - TAU * N / wavelength
	wave_lake.waves = [{"amplitude_m": amplitude, "wavelength_m": wavelength,
		"period_s": period, "heading_rad": 0.0, "phase_rad": phase_offset}]
	wave_lake.identity = Loader.identity(wave_lake)
	var surface_start: float = Surface.water_height_down(wave_lake, N, E, 0.0)
	var surface_end: float = Surface.water_height_down(wave_lake, N, E, DT)
	var point_down: float = surface_start - 0.0001
	var stationary := _state(PackedFloat64Array([N, E, point_down]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var event: LakeCollision.WaterEvent = LakeCollision.first_hit(wave_lake, stationary, stationary,
		_point, {}, 1, DT, MASS, _inertia)
	var clear_calm: LakeCollision.WaterEvent = LakeCollision.first_hit(calm, stationary, stationary,
		_point, {}, 1, DT, MASS, _inertia)
	check("wave starts above point gap and rises across it", surface_start - point_down > 0.0 \
		and surface_end - point_down < 0.0)
	check("stationary point wave contacts; calm control remains clear", event != null and clear_calm == null)
	if event == null:
		return
	var event_time: float = event.time_fraction * DT
	var phase: float = TAU * N / wavelength - TAU * event_time / period + phase_offset
	var down_rate: float = amplitude * TAU / period * cos(phase)
	var north_slope: float = -amplitude * TAU / wavelength * cos(phase)
	var analytic_normal_closing: float = -down_rate / sqrt(1.0 + north_slope * north_slope)
	print("WAVE ", JSON.stringify({"event_time_s": event_time, "initial_gap_m": surface_start - point_down,
		"reported_normal_speed_mps": event.normal_speed_mps,
		"analytic_interface_normal_closing_mps": analytic_normal_closing,
		"reported_velocity_ned": Array(event.velocity_ned), "terminal": event.terminal}))
	check("stationary point reported speed ignores rising-interface rate",
		absf(event.normal_speed_mps) < 1.0e-10 and analytic_normal_closing > 0.04 and event.terminal)
