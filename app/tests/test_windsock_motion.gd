extends SceneTree

const Motion = preload("res://render/windsock_motion.gd")
const WindConfig = preload("res://physics/wind_config.gd")
const Windsock = preload("res://render/windsock.gd")

const SAMPLE_HZ: float = 240.0
const STEP_S: float = 1.0 / 120.0
const FULL_FLOW_MPS: float = 7.71667

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_geometry_and_headings()
	_test_inflation_and_flow()
	_test_vane_and_reversal()
	_test_extremes_reset_and_replay()
	await _test_main_wind_callback()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_geometry_and_headings() -> void:
	var motion: Variant = Motion.new(2.5, 0.45, 0.12)
	var points: PackedVector3Array = motion.centerline_local
	_check("13 centreline points with rigid support at index 5", points.size() == 13
		and is_equal_approx(points[5].x, 2.5 * 0.375))
	var rigid: bool = true
	for i: int in 6:
		rigid = rigid and absf(points[i].y) < 1e-9 and absf(points[i].z) < 1e-9
	_check("mouth and first 3/8 stay on the rigid axis", rigid)
	_check("calm sleeve hangs more than 1 m below the mouth", points[12].y < -1.0,
		"tail y %.3f m" % points[12].y)
	_check("calm flex links preserve the 2.5 m centreline length", absf(_arc_length(points) - 2.5) < 0.002)
	var headings: Array = [
		{"name": "north", "wind": [10.0, 0.0, 0.0], "yaw": PI * 0.5},
		{"name": "east", "wind": [0.0, 10.0, 0.0], "yaw": 0.0},
		{"name": "south", "wind": [-10.0, 0.0, 0.0], "yaw": -PI * 0.5},
		{"name": "west", "wind": [0.0, -10.0, 0.0], "yaw": PI},
	]
	for item: Dictionary in headings:
		motion.reset(0.0, item.wind)
		_check("NED wind-to heading sign: %s" % item.name,
			_angle_error(float(motion.basket_yaw_rad), float(item.yaw)) < 1e-6)


func _test_inflation_and_flow() -> void:
	var gentle: Variant = Motion.new(2.5, 0.45, 0.12)
	gentle.reset(0.0, [0.0, 1.5, 0.0])
	_advance_constant(gentle, 0.0, 2.0, [0.0, 1.5, 0.0])
	_check("gentle axial flow remains short of the 15 kt full-extension anchor", float(gentle.inflation) < 0.5,
		"inflation %.4f" % float(gentle.inflation))
	var axial: Variant = Motion.new(2.5, 0.45, 0.12)
	axial.reset(0.0, [0.0, FULL_FLOW_MPS, 0.0])
	_advance_constant(axial, 0.0, 2.0, [0.0, FULL_FLOW_MPS, 0.0])
	var axial_tail: Vector3 = axial.centerline_local[12]
	_check("15 kt axial flow reaches full extension", float(axial.inflation) > 0.99,
		"inflation %.4f" % float(axial.inflation))
	_check("full axial flow settles nearly horizontal", absf(axial_tail.y) < 0.12 and absf(axial_tail.z) < 0.08,
		"tail %s" % str(axial_tail))
	_check("taut tail links preserve their total length", absf(_arc_length(axial.centerline_local) - 2.5) < 0.002)

	var vertical: Variant = Motion.new(2.5, 0.45, 0.12)
	vertical.reset(0.0, [0.0, 0.0, -15.0])
	_advance_constant(vertical, 0.0, 2.0, [0.0, 0.0, -15.0])
	_check("pure vertical upflow cannot fully inflate the sock", float(vertical.inflation) < 0.95,
		"inflation %.4f" % float(vertical.inflation))
	_check("vertical-flow centreline remains finite and inextensible",
		_state_is_finite(vertical) and absf(_arc_length(vertical.centerline_local) - 2.5) < 0.002)

	var horizontal: Variant = Motion.new(2.5, 0.45, 0.12)
	horizontal.reset(0.0, [0.0, 3.0, 0.0])
	_advance_constant(horizontal, 0.0, 2.0, [0.0, 3.0, 0.0])
	var horizontal_tail_y: float = float(horizontal.centerline_local[12].y)
	var combined: Variant = Motion.new(2.5, 0.45, 0.12)
	combined.reset(0.0, [0.0, 3.0, -8.0])
	_advance_constant(combined, 0.0, 2.0, [0.0, 3.0, -8.0])
	_check("upgust lifts the tail above the same horizontal wind",
		float(combined.centerline_local[12].y) > horizontal_tail_y + 0.05,
		"horizontal tail %.3f m, combined %.3f m" % [horizontal_tail_y, float(combined.centerline_local[12].y)])
	var taut_upgust: Variant = Motion.new(2.5, 0.45, 0.12)
	taut_upgust.reset(0.0, [0.0, FULL_FLOW_MPS, -8.0])
	_advance_constant(taut_upgust, 0.0, 2.0, [0.0, FULL_FLOW_MPS, -8.0])
	_check("full axial flow plus upgust raises the sleeve above level", float(taut_upgust.centerline_local[12].y) > 0.05,
		"tail y %.3f m" % float(taut_upgust.centerline_local[12].y))
	_check("tiny updraft changes the sleeve continuously",
		_tiny_updraft_continuity())


func _tiny_updraft_continuity() -> bool:
	var still_air: Variant = Motion.new(2.5, 0.45, 0.12)
	var tiny_upflow: Variant = Motion.new(2.5, 0.45, 0.12)
	still_air.reset(0.0, [0.0, 3.0, 0.0])
	tiny_upflow.reset(0.0, [0.0, 3.0, -0.01])
	_advance_constant(still_air, 0.0, 1.0, [0.0, 3.0, 0.0])
	_advance_constant(tiny_upflow, 0.0, 1.0, [0.0, 3.0, -0.01])
	return absf(float(still_air.inflation) - float(tiny_upflow.inflation)) < 0.002 \
		and _angle_error(float(still_air.basket_yaw_rad), float(tiny_upflow.basket_yaw_rad)) < 1e-4 \
		and _state_is_finite(tiny_upflow)


func _test_vane_and_reversal() -> void:
	var light: Variant = Motion.new(2.5, 0.45, 0.12)
	light.reset(0.0, [0.0, 0.8, 0.0])
	_advance_constant(light, 0.0, 2.0, [0.8, 0.0, 0.0])
	_check("0.8 m/s wind still turns the vane", _angle_error(float(light.basket_yaw_rad), 0.0) > 0.2,
		"yaw %.3f rad" % float(light.basket_yaw_rad))

	var reversal: Variant = Motion.new(2.5, 0.45, 0.12)
	reversal.reset(0.0, [0.0, FULL_FLOW_MPS, 0.0])
	_advance_constant(reversal, 0.0, 2.0, [0.0, FULL_FLOW_MPS, 0.0])
	var extended_inflation: float = float(reversal.inflation)
	_advance_constant(reversal, 2.0, 0.1, [0.0, -FULL_FLOW_MPS, 0.0])
	var mid_yaw: float = float(reversal.basket_yaw_rad)
	_check("direction reversal starts deflation before the basket turns", float(reversal.inflation) < extended_inflation - 0.01)
	_check("basket retains inertia during the reversal mid-turn", _angle_error(mid_yaw, PI) > 0.3)
	_advance_constant(reversal, 2.1, 2.0, [0.0, -FULL_FLOW_MPS, 0.0])
	_check("reversed basket settles toward west and re-inflates",
		_angle_error(float(reversal.basket_yaw_rad), PI) < 0.08 and float(reversal.inflation) > 0.9)

	var crossflow: Variant = Motion.new(2.5, 0.45, 0.12)
	crossflow.reset(0.0, [0.0, FULL_FLOW_MPS, 0.0])
	_advance_constant(crossflow, 0.0, 2.0, [0.0, FULL_FLOW_MPS, 0.0])
	var before_crossflow: float = float(crossflow.inflation)
	_advance_constant(crossflow, 2.0, 0.1, [FULL_FLOW_MPS, 0.0, 0.0])
	_check("crossflow unloads the mouth while the basket turns", float(crossflow.inflation) < before_crossflow - 0.01)


func _test_extremes_reset_and_replay() -> void:
	var motion: Variant = Motion.new(2.5, 0.45, 0.12)
	motion.reset(0.0, [0.0, FULL_FLOW_MPS, 0.0])
	_advance_constant(motion, 0.0, 1.0, [0.0, FULL_FLOW_MPS, 0.0])
	var paused: Dictionary = motion.state_snapshot()
	motion.update_to(1.0, [0.0, -FULL_FLOW_MPS, 0.0])
	_check("same-time wind updates pause the motion state", _same_snapshot(paused, motion.state_snapshot()))
	motion.reset(0.0, [10.0, 0.0, 0.0])
	_check("reset clears inflation and fixed-step history", float(motion.inflation) == 0.0
		and int(motion.simulated_step_index) == 0 and float(motion.simulated_time_s) == 0.0)
	_check("reset aligns to its supplied current wind", _angle_error(float(motion.basket_yaw_rad), PI * 0.5) < 1e-6)
	_check("finite extreme wind is safely bounded", motion.update_to(2.0 / SAMPLE_HZ,
		[1.0e300, -1.0e300, 1.0e300]) and _state_is_finite(motion))
	_check("extreme input retains bounded centreline length", absf(_arc_length(motion.centerline_local) - 2.5) < 0.002)

	var cue: Dictionary = {id = "MotionGroupingSock", north = 0.0, east = 0.0, length = 2.5,
		pole_height = 3.0, throat_diameter = 0.45, tail_diameter = 0.12}
	var low_sock: Node3D = Windsock.build(cue)
	var medium_sock: Node3D = Windsock.build(cue)
	var high_sock: Node3D = Windsock.build(cue)
	var low_fps: Variant = low_sock.get_meta("windsock_motion")
	var high_fps: Variant = high_sock.get_meta("windsock_motion")
	var medium_fps: Variant = medium_sock.get_meta("windsock_motion")
	var low_frames: int = 0
	var high_frames: int = 0
	var previous_low: int = 0
	var previous_high: int = 0
	for tick: int in range(1, 4 * int(SAMPLE_HZ) + 1):
		var time_s: float = float(tick) / SAMPLE_HZ
		var wind: Array = _tape_wind(tick)
		Windsock.advance(low_sock, time_s, wind)
		Windsock.advance(medium_sock, time_s, wind)
		Windsock.advance(high_sock, time_s, wind)
		if tick % 4 == 0:
			Windsock.update(medium_sock, time_s, wind)
		var low_sample: int = int(floor(float(tick) * 30.0 / SAMPLE_HZ))
		var high_sample: int = int(floor(float(tick) * 144.0 / SAMPLE_HZ))
		if low_sample > previous_low:
			Windsock.update(low_sock, time_s, wind)
			low_frames += 1
			previous_low = low_sample
		if high_sample > previous_high:
			Windsock.update(high_sock, time_s, wind)
			high_frames += 1
			previous_high = high_sample
	_check("same 240 Hz wind tape has frame reads at both 30 and 144 fps", low_frames > 100 and high_frames > low_frames)
	_check("30/60/144 fps grouping leaves replay state identical", _same_snapshot(low_fps.state_snapshot(), high_fps.state_snapshot())
		and _same_snapshot(medium_fps.state_snapshot(), high_fps.state_snapshot()))
	_check("grouped update() calls do not attach scene processing", not low_sock.is_processing()
		and not low_sock.is_physics_processing() and not high_sock.is_processing() and not high_sock.is_physics_processing())
	low_sock.free()
	medium_sock.free()
	high_sock.free()


func _tape_wind(tick: int) -> Array:
	if tick < 120:
		return [0.0, 0.0, 0.0]
	if tick < 360:
		return [0.0, 8.0, 0.0]
	if tick < 600:
		return [8.0, 0.0, 0.0]
	if tick < 720:
		return [0.0, 0.0, -8.0]
	return [0.0, 0.0, 0.0]


func _test_main_wind_callback() -> void:
	var saved_environment: Dictionary = {}
	for key: String in ["OPENRC_SCENERY", "OPENRC_SCENERY_AUDIO", "OPENRC_SCENERY_BIRDS"]:
		saved_environment[key] = OS.get_environment(key)
		OS.set_environment(key, "off")
	var main: Node = load("res://main.tscn").instantiate() as Node
	main.call("set_user_args", PackedStringArray([
		"--weather=turbulent", "--scenery=off", "--soundscape=off", "--smoke=off", "--crash-effects=off",
	]))
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var sim: Variant = session.get("sim") if session != null else null
	var field: Node3D = main.get("_field_node") as Node3D
	var cues: Array = field.get_meta("wind_cues", []) if field != null else []
	_check("production Main connects the real 240 Hz session wind callback",
		sim != null and sim.is_connected("stepped", Callable(main, "_advance_windsock")) and cues.size() == 1)
	if sim != null and cues.size() == 1:
		var sock: Node3D = cues[0] as Node3D
		var motion: Variant = sock.get_meta("windsock_motion")
		session.call("reset")
		var startup_wind: PackedFloat64Array = session.call("wind_at", 0.0)
		_check("session reset aligns the basket with the committed startup wind",
			_angle_error(float(motion.basket_yaw_rad), atan2(startup_wind[0], startup_wind[1])) < 1e-5
			and float(motion.inflation) == 0.0 and float(motion.simulated_time_s) == 0.0)
		var initial_index: int = int(motion.simulated_step_index)
		var aux_before: PackedFloat64Array = sim.get("aux").duplicate()
		var time_s: float = float(sim.call("time"))
		var first_wind: PackedFloat64Array = session.call("wind_at", time_s)
		var second_wind: PackedFloat64Array = session.call("wind_at", time_s)
		_check("seeded OU wind sample is repeatable and read-only",
			WindConfig.has_turbulence(session.call("weather_configuration"))
			and _same_f64(first_wind, second_wind) and _same_f64(aux_before, sim.get("aux")))
		for _tick: int in 240:
			sim.call("step")
		var final_time: float = float(sim.call("time"))
		_check("Main feeds FlightSession.wind_at into windsock motion on simulation ticks",
			int(motion.simulated_step_index) > initial_index
			and absf(float(motion.simulated_time_s) - final_time) <= STEP_S + 1e-8,
			"motion %.6f s / session %.6f s" % [float(motion.simulated_time_s), final_time])
		var physical_before: PackedFloat64Array = sim.get("state").duplicate()
		aux_before = sim.get("aux").duplicate()
		main.call("_advance_windsock", int(sim.get("tick")), final_time, sim.get("state"),
			sim.get("last_loads"), sim.get("inputs"), sim.get("aux"))
		_check("windsock observer preserves physical state and turbulence history",
			_same_f64(physical_before, sim.get("state")) and _same_f64(aux_before, sim.get("aux")))
	else:
		_check("production Main session and field are available", false)
	main.set_process(false)
	main.set_physics_process(false)
	if session != null:
		session.set_process(false)
		session.set_physics_process(false)
	if sim != null:
		sim.set_process(false)
		sim.set_physics_process(false)
	if main.get_parent() == root:
		root.remove_child(main)
	main.free()
	for key: String in saved_environment:
		if str(saved_environment[key]).is_empty(): OS.unset_environment(key)
		else: OS.set_environment(key, str(saved_environment[key]))
	await process_frame


func _advance_constant(motion: Variant, start_s: float, duration_s: float, wind_ned: Array) -> void:
	var count: int = int(round(duration_s * SAMPLE_HZ))
	for sample: int in range(1, count + 1):
		motion.update_to(start_s + float(sample) / SAMPLE_HZ, wind_ned)


func _arc_length(points: PackedVector3Array) -> float:
	var total_m: float = 0.0
	for i: int in range(1, points.size()):
		total_m += points[i].distance_to(points[i - 1])
	return total_m


func _state_is_finite(motion: Variant) -> bool:
	if not is_finite(float(motion.basket_yaw_rad)) or not is_finite(float(motion.inflation)):
		return false
	for point: Vector3 in motion.centerline_local:
		if not point.is_finite():
			return false
	return true


func _same_snapshot(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["simulated_time_s", "simulated_step_index", "basket_yaw_rad", "yaw_rate_rad_s", "inflation"]:
		if not is_equal_approx(float(a[key]), float(b[key])):
			return false
	var left: PackedVector3Array = a.centerline_local
	var right: PackedVector3Array = b.centerline_local
	if left.size() != right.size():
		return false
	for i: int in left.size():
		if left[i] != right[i]:
			return false
	return true


func _same_f64(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true


func _angle_error(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
