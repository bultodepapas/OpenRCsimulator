extends SceneTree

const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	if not bool(loaded.get("ok", false)):
		push_error("Vehicle data failed to load: " + str(loaded.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var initialized: Dictionary = Vehicle.initialize(model, Callable(self, "_flat_road"))
	if not bool(initialized.get("ok", false)):
		push_error("Vehicle state failed to initialize: " + str(initialized.get("error", "")))
		quit(1)
		return
	var state: PackedFloat64Array = initialized.state.duplicate()
	state[Vehicle.VEL] = 8.0
	state[Vehicle.VEL + 1] = 1.0
	var attitude := M.q_from_euler(PI / 2.0, 0.0, 0.0)
	for component in 4:
		state[Vehicle.ATT + component] = attitude[component] * 1.0005
	var raw_length := Vehicle._quaternion_length(state)
	var actual := Vehicle.derivative(state, model, Vehicle.DEFAULT_CONTROLS, Callable(self, "_flat_road"))
	var expected := M.q_rotate(M.q_normalized(attitude), state.slice(Vehicle.VEL, Vehicle.VEL + 3))
	var observed := actual.slice(Vehicle.POS, Vehicle.POS + 3) if actual.size() == Vehicle.STATE_SIZE else PackedFloat64Array()
	var error := M.norm(M.sub(observed, expected)) if observed.size() == 3 else INF
	print("accepted quaternion length=%.12f; actual position rate=%s; normalized expected=%s; error=%.12f m/s" % [
		raw_length, str(observed), str(expected), error,
	])
	var fixed := actual.size() == Vehicle.STATE_SIZE and absf(raw_length - 1.0) < 1.0e-3 and error < 1.0e-12
	print("normalized mapping verified=%s" % str(fixed))
	quit(0 if fixed else 1)


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
	}
