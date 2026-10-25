# UI-06: every catalog airplane can park on the default runway and explicitly start airborne.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Weather := preload("res://physics/wind_config.gd")
const Preferences := preload("res://app_state/preferences.gd")
const RB := preload("res://physics/rigid_body.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var field: Dictionary = Field.load_from().field
	var threshold: Dictionary = GroundStart.threshold(field)
	for entry in Catalog.airplane_flyable_entries():
		for weather in [Weather.defaults(), Preferences.DEFAULTS.weather_config]:
			var session := Session.new()
			session.input_enabled = false
			session.crash_auto_restart = false
			session.setup(entry.data, entry.id)
			check(entry.id + " field and weather", session.set_field(field) and session.setup_weather(weather))
			session.start_choice = Preferences.DEFAULTS.start_choice
			# X8-09: an airplane without landing gear has no runway start; it must refuse one explicitly, never fake it.
			if not Session.runway_aircraft_supported(entry.id):
				session.reset()
				check(entry.id + " gearless airplane refuses the runway start", not session.start_error.is_empty()
					and session.start_error.contains("landing gear"))
				session.free()
				continue
			session.reset()
			check(entry.id + " runway start: " + session.start_error, session.is_flyable() and session.start_error.is_empty()
				and session.trace_meta().launch_choice == "runway" and session.sim.tick == 0)
			if not session.is_flyable() or not session.start_error.is_empty():
				session.free()
				continue
			var initial: PackedFloat64Array = session.sim.state.duplicate()
			check(entry.id + " stopped at the threshold", absf(initial[0] - threshold.north) < 0.01
				and absf(initial[1] - threshold.east) < 0.01 and _speed(initial) < 1e-6 and session.sim.inputs[3] == 0.0)
			check(entry.id + " supported on landing gear", _grounded(session) and not session.gear_collapsed(initial))
			if session.gear_is_retractable():
				check(entry.id + " gear commanded down", session.sim.inputs[4] == 1.0)
			var max_speed := 0.0
			for tick in 480:
				session._physics_process(session.sim.dt())
				session.sim.step()
				max_speed = maxf(max_speed, _speed(session.sim.state))
				if session.sim.paused or not session.sim.fault_reason.is_empty(): break
			check(entry.id + " remains parked for two seconds", session.sim.tick == 480 and max_speed < 0.05
				and session.crash.is_empty() and session.prop_strike.is_empty() and _grounded(session))
			print(entry.id, " weather=", weather.get("preset", weather.get("format", "")), " idle max speed=", max_speed)
			session.reset()
			check(entry.id + " restart restores runway", session.start_error.is_empty() and session.sim.state == initial
				and session.sim.tick == 0 and session.sim.inputs[3] == 0.0)
			session.start_choice = Session.START_AIRBORNE
			session.reset()
			check(entry.id + " explicit airborne alternative", session.is_flyable() and session.start_error.is_empty()
				and session.trace_meta().launch_choice == "airborne" and -session.sim.state[2] > 5.0 and _speed(session.sim.state) > 5.0)
			session.free()
	print("Runway fleet: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] ** 2 + state[RB.VEL + 1] ** 2 + state[RB.VEL + 2] ** 2)

func _grounded(session: Node) -> bool:
	for compression in session.gear_compressions(session.sim.state):
		if compression > 0.0: return true
	return false
