extends SceneTree
## F5b: FlightSession.flap_angle_deg() is flap_state()'s angle_deg (0.0 where flap_state reports none), bit for bit,
## on every tick of flights that move their flaps, and 0.0 on an aircraft without flaps. The renderer's per-frame pose
## reads it instead of flap_state(), whose overspeed advisory solves air data.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	var with_flaps := 0
	for id: String in ["f4u-corsair-250", "p51d-mustang-120", "jensen-das-ugly-stik-60"]:
		var s: Node = Flight.new()
		s.input_enabled = true
		s.crash_auto_restart = false
		s.start_choice = Flight.START_AIRBORNE
		s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
		s.set_field(field)
		s.reset()
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = 0.02, yaw = 0.0, throttle = 0.7}
		var compared := 0
		var mismatched := 0
		var moving := 0
		for tick in 1440:
			if s.flaps_available():
				s.set_flaps([0.0, 1.0, 0.5, 0.0][(tick / 240) % 4])
			s._physics_process(s.sim.dt())
			s.sim._physics_process(s.sim.dt())
			var reference := float(s.flap_state().get("angle_deg", 0.0))
			var answer: float = s.flap_angle_deg()
			compared += 1
			moving += int(reference != 0.0)
			if var_to_bytes(answer) != var_to_bytes(reference):
				mismatched += 1
		if s.flaps_available():
			with_flaps += 1
			_check("%s: flap_angle_deg equals flap_state's angle on every tick" % id, mismatched == 0 and moving > 300,
				"%d mismatched, %d deflected of %d" % [mismatched, moving, compared])
		else:
			_check("%s: without flaps both report 0.0" % id, mismatched == 0 and moving == 0, str(mismatched))
		s.free()
	_check("the flights include aircraft with flaps", with_flaps >= 1, str(with_flaps))
	print("flap angle accessor: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
