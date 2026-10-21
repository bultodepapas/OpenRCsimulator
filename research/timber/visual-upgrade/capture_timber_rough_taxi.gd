## Controlled native capture of real FlightSession taxi slip on the default field's rough surface.
## GroundStart solves the initial contact pose; throttle is then advanced through ordinary external-session ticks.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Motion := preload("res://aircraft/timber_visual_motion.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const Frames := preload("res://render/frames.gd")

const AIRCRAFT_ID := "turbo-lumber-evolution"
const ROUGH_START_NORTH_M := 23.0
const ROUGH_START_EAST_M := 0.0
const ROUGH_START_HEADING_RAD := PI / 2.0
const TAXI_THROTTLE := 1.0
const NATURAL_TAXI_TICKS := 120
const CAPTURE_FRAMES := 42
const MAX_SLIP_MPS := 0.75
const MAX_SIDE_SLIP_MPS := 0.65
const CAPTURE_SLIP_OVERRIDE_MPS := 1.25

var _session: Node
var _airplane: Dictionary = {}
var _motion: Node
var _ground: Node
var _stage: Node3D
var _cg_model := Vector3.ZERO
var _report := {}


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var entry: Dictionary = Catalog.entry(AIRCRAFT_ID)
	_session = Session.new()
	_session.input_enabled = false
	_session.setup(str(entry.data))
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false) or not _session.set_field(field_result.field):
		_fail("could not install the production default field", {"errors": str(field_result.get("errors", []))})
		return
	_session.start_choice = Session.START_RUNWAY
	_session.reset()
	if not _session.configure_external_driver():
		_fail("could not configure deterministic external ticks")
		return
	var start_result: Dictionary = _session.try_runway_start(
		ROUGH_START_NORTH_M, ROUGH_START_EAST_M, ROUGH_START_HEADING_RAD)
	if not start_result.get("ok", false):
		_fail("rough-ground contact equilibrium was refused", {"detail": str(start_result)})
		return
	# The native capture may lose OS focus. Its controlled external-tick fixture owns
	# this synthetic session, so explicitly resume before driving and rendering it.
	_session.sim.set_paused(false)
	if not _session.is_flyable():
		_fail("rough-ground session is not flyable", {"start_error": str(_session.start_error)})
		return

	var initial_contacts := _contact_sample()
	if not _all_main_contacts_are_rough(initial_contacts):
		_fail("chosen contact pose is not fully over the default rough surface", {"contacts": initial_contacts})
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 960)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	_stage = Node3D.new()
	viewport.add_child(_stage)
	_airplane = Airplane.build(AIRCRAFT_ID)
	if _airplane.is_empty():
		_fail("could not build the production Timber render")
		return
	_stage.add_child(_airplane.root)
	var datum: Vector2 = Airplane.datum(AIRCRAFT_ID)
	_cg_model = Frames.cg_in_model_frame(
		_session.aircraft.model.cg_le, datum.x, datum.y)
	_apply_airplane_pose()
	_ground = GroundGear.attach(_airplane, _session)
	_motion = Motion.attach(_airplane, _session)
	if _motion == null:
		_fail("Timber motion observer did not attach")
		return
	_ground._process(0.0)
	_motion._process(0.0)
	var natural_taxi := _run_natural_taxi()
	if not natural_taxi.get("ok", false):
		_report = natural_taxi
		_fail("natural rough-ground taxi rollout did not remain flyable", natural_taxi)
		return
	_apply_airplane_pose()
	_ground._process(0.0)
	_motion._process(0.0)
	var taxi_contacts := _contact_sample()
	if not _all_main_contacts_are_rough(taxi_contacts):
		_fail("taxi rollout left the default rough surface", {"contacts": taxi_contacts})
		return
	_add_rough_contact_patch(taxi_contacts)
	var contact_index := _loaded_main_contact_index(taxi_contacts)
	if contact_index < 0:
		_fail("taxi sample has no loaded main wheel contact", {"contacts": taxi_contacts})
		return
	_add_camera_and_lights(contact_index)
	var state_before: PackedFloat64Array = _session.sim.state.duplicate()
	var continuous_before: PackedFloat64Array = _session.sim.continuous.duplicate()
	var contact_sample: Dictionary = taxi_contacts[contact_index]
	var wheel_state_index: int = _session.wheel_index() + contact_index
	if wheel_state_index < 0 or wheel_state_index >= continuous_before.size():
		_fail("could not locate the selected wheel rim-speed state", {"index": wheel_state_index})
		return
	var continuous_fixture: PackedFloat64Array = continuous_before.duplicate()
	continuous_fixture[wheel_state_index] = float(contact_sample.body_long_speed_mps) + CAPTURE_SLIP_OVERRIDE_MPS
	_session.sim.continuous = continuous_fixture
	var contacts: Array = _session.current_landing_gear().get("contacts", [])
	var compression: PackedFloat64Array = _session.gear_compressions(state_before)
	_ground._process(0.0)
	_apply_airplane_pose()
	_ground._process(0.0)
	_motion._process(0.0)
	_motion._update_contact_dust(state_before, contacts, compression)
	var emitter: CPUParticles3D = _motion._dust_emitters[contact_index]
	if not emitter.emitting:
		_session.sim.continuous = continuous_before
		_fail("controlled wheel-slip fixture did not activate dust", {"contact": contact_sample})
		return
	var sample_at_emission: Dictionary = _contact_sample()[contact_index].duplicate(true)
	var image_path := ProjectSettings.globalize_path(
		"res://../research/timber/visual-upgrade/timber-rough-ground-taxi.png")
	for _frame in CAPTURE_FRAMES:
		await process_frame
	var capture_sample: Dictionary = _contact_sample()[contact_index].duplicate(true)
	var dust_emitting_at_capture := emitter.emitting
	var ground_contact_render := _ground_contact_render_position(contact_index)
	var emitter_position_render := emitter.global_position
	var image: Image = viewport.get_texture().get_image()
	if image.is_empty():
		_fail("SubViewport returned an empty rough-taxi capture", natural_taxi)
		return
	var save_error: Error = image.save_png(image_path)
	if save_error != OK:
		_fail("could not save rough-taxi capture", {"error": save_error, "path": image_path})
		return
	_session.sim.continuous = continuous_before
	var telemetry_restored := _same_floats(continuous_before, _session.sim.continuous)
	var state_unchanged := _same_floats(state_before, _session.sim.state)
	emitter.emitting = false
	var final_sample := _contact_sample()
	_report = {
		"schema": "timber-rough-ground-taxi-capture-v1",
		"capture_image": "research/timber/visual-upgrade/timber-rough-ground-taxi.png",
		"capture_frames_after_slip_sample": CAPTURE_FRAMES,
		"capture_render_resolution_px": [viewport.size.x, viewport.size.y],
		"fixture": {
			"type": "real_taxi_rollout_with_controlled_slip_capture",
			"field_id": _session.ground_field_id,
			"start_north_m": ROUGH_START_NORTH_M,
			"start_east_m": ROUGH_START_EAST_M,
			"heading_rad": ROUGH_START_HEADING_RAD,
			"surface": "rough",
			"rolling_factor": 7.5,
			"synthetic_aircraft_state": false,
			"state_source": "FlightSession.try_runway_start contact equilibrium followed by ordinary externally stepped Simulation ticks",
			"control_input": {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": TAXI_THROTTLE},
			"natural_taxi_ticks": natural_taxi.ticks,
			"natural_taxi_distance_m": natural_taxi.distance_m,
			"natural_taxi_speed_mps": natural_taxi.speed_mps,
			"natural_max_longitudinal_slip_mps": natural_taxi.maximum_longitudinal_slip_mps,
			"natural_max_lateral_speed_mps": natural_taxi.maximum_lateral_slip_mps,
			"controlled_slip_fixture": {
				"kind": "temporary main-wheel rim-speed telemetry override",
				"rim_speed_offset_mps": CAPTURE_SLIP_OVERRIDE_MPS,
				"synthetic_pose": false,
				"synthetic_forces": false,
				"scope": "one frozen capture sample only; original continuous state restored after PNG capture",
			},
		},
		"contact_evaluator": "FlightSession ground surface table + GroundWheels.frame on the production Turbo Lumber model",
		"dust_gate": {
			"minimum_normal_load_n": 2.0,
			"minimum_longitudinal_slip_mps": MAX_SLIP_MPS,
			"minimum_lateral_slip_mps": MAX_SIDE_SLIP_MPS,
			"minimum_rough_rolling_factor": 5.0,
		},
		"sample_at_emission": sample_at_emission,
		"sample_at_capture": capture_sample,
		"dust_source": {
			"position_render_m": [emitter_position_render.x, emitter_position_render.y, emitter_position_render.z],
			"ground_contact_position_render_m": [ground_contact_render.x, ground_contact_render.y, ground_contact_render.z],
			"normal_offset_m": emitter_position_render.distance_to(ground_contact_render),
			"direction_world": [emitter.direction.x, emitter.direction.y, emitter.direction.z],
			"trail_direction_basis": "away from wheel along the measured ground-frame travel heading, with upward component",
		},
		"post_capture_contact_sample": final_sample,
		"simulation_fault": str(_session.sim.fault_reason),
		"crash": _session.crash.duplicate(true),
		"dust_emitting_at_capture": dust_emitting_at_capture,
		"particle_count": emitter.amount,
		"temporary_wheel_telemetry_restored": telemetry_restored,
		"aircraft_body_state_unchanged_by_capture_fixture": state_unchanged,
	}
	_write_report()
	print("rough-ground taxi capture: %s; tick=%d; dust=%s" % [
		image_path, _session.sim.tick, str(dust_emitting_at_capture)])
	quit(0 if dust_emitting_at_capture else 1)


func _run_natural_taxi() -> Dictionary:
	var initial_state: PackedFloat64Array = _session.sim.state.duplicate()
	var maximum_long_slip := 0.0
	var maximum_lateral_slip := 0.0
	for _tick_index in NATURAL_TAXI_TICKS:
		var staged: Dictionary = _session.prepare_external_tick({
			"roll": 0.0,
			"pitch": 0.0,
			"yaw": 0.0,
			"throttle": TAXI_THROTTLE,
		})
		if not staged.get("ok", false) or not _session.step_external_tick():
			return {"ok": false,
				"maximum_longitudinal_slip_mps": maximum_long_slip,
				"maximum_lateral_slip_mps": maximum_lateral_slip,
				"reason": "FlightSession rejected a taxi tick",
				"tick": _session.sim.tick,
				"fault": str(_session.sim.fault_reason),
				"crash": _session.crash.duplicate(true)}
		_apply_airplane_pose()
		_ground._process(_session.sim.dt())
		_motion._process(_session.sim.dt())
		var contacts := _contact_sample()
		for sample: Dictionary in contacts:
			if str(sample.contact_name) not in ["main_left", "main_right"]:
				continue
			maximum_long_slip = maxf(maximum_long_slip, absf(float(sample.longitudinal_slip_mps)))
			maximum_lateral_slip = maxf(maximum_lateral_slip, absf(float(sample.lateral_speed_mps)))
		if not _session.crash.is_empty() or not str(_session.sim.fault_reason).is_empty():
			return {"ok": false,
				"maximum_longitudinal_slip_mps": maximum_long_slip,
				"maximum_lateral_slip_mps": maximum_lateral_slip,
				"reason": "taxi terminated during natural rollout",
				"tick": _session.sim.tick,
				"fault": str(_session.sim.fault_reason),
				"crash": _session.crash.duplicate(true)}
	var final_state: PackedFloat64Array = _session.sim.state
	var north_delta := final_state[0] - initial_state[0]
	var east_delta := final_state[1] - initial_state[1]
	return {"ok": true,
		"ticks": _session.sim.tick,
		"distance_m": sqrt(north_delta * north_delta + east_delta * east_delta),
		"speed_mps": sqrt(final_state[3] * final_state[3] + final_state[4] * final_state[4]),
		"maximum_longitudinal_slip_mps": maximum_long_slip,
		"maximum_lateral_slip_mps": maximum_lateral_slip,
		"tick": _session.sim.tick}


func _contact_sample() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var state: PackedFloat64Array = _session.sim.state
	var contacts: Array = _session.current_landing_gear().get("contacts", [])
	var speeds: PackedFloat64Array = _session.sim.continuous.slice(
		_session.wheel_index(), _session.wheel_index() + _session.wheel_count())
	var steer := float(_session.sim.aux[_session.AUX_SERVO + 2])
	var compression_values: PackedFloat64Array = _session.gear_compressions(state)
	for contact_index in contacts.size():
		var contact: Dictionary = contacts[contact_index]
		var frame: Dictionary = GroundWheels.frame(state, contact, steer,
			_session.ground_surfaces, PackedFloat64Array(), false, {})
		var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
		var surface_index := GroundWheels.surface_at(
			_session.ground_surfaces, float(position[0]), float(position[1]))
		var wheel_speed := float(speeds[contact_index]) if contact_index < speeds.size() else 0.0
		var long_speed := float(frame.get("long_speed", 0.0))
		var side_speed := float(frame.get("side_speed", 0.0))
		samples.append({
			"contact_index": contact_index,
			"contact_name": str(contact.get("name", "")),
			"surface_index": surface_index,
			"position_ned_m": Array(position),
			"rolling_factor": float(_session.ground_surfaces[surface_index + 5]),
			"compression_m": float(compression_values[contact_index]),
			"normal_load_n": float(frame.get("normal_load", 0.0)),
			"body_long_speed_mps": long_speed,
			"wheel_rim_speed_mps": wheel_speed,
			"longitudinal_slip_mps": long_speed - wheel_speed,
			"lateral_speed_mps": side_speed,
		})
	return samples


func _loaded_main_contact_index(samples: Array[Dictionary]) -> int:
	for sample_index in samples.size():
		var sample: Dictionary = samples[sample_index]
		if str(sample.contact_name) in ["main_left", "main_right"] \
				and float(sample.normal_load_n) >= 2.0 and float(sample.compression_m) > 0.0:
			return sample_index
	return -1


func _same_floats(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _all_main_contacts_are_rough(samples: Array[Dictionary]) -> bool:
	var main_count := 0
	for sample: Dictionary in samples:
		if str(sample.contact_name) in ["main_left", "main_right"]:
			main_count += 1
			if float(sample.rolling_factor) < 5.0:
				return false
	return main_count == 2


func _apply_airplane_pose() -> void:
	var state: PackedFloat64Array = _session.sim.state
	var cg_position := Frames.ned_to_render([state[0], state[1], state[2]])
	var attitude: PackedFloat64Array = state.slice(6, 10)
	var basis := Frames.quat_to_render(attitude)
	_airplane.root.transform = Frames.root_transform(basis, cg_position, _cg_model)


func _add_rough_contact_patch(samples: Array[Dictionary]) -> void:
	var center := Vector3.ZERO
	var count := 0
	for sample: Dictionary in samples:
		if str(sample.contact_name) not in ["main_left", "main_right"]:
			continue
		var contact: Dictionary = _session.current_landing_gear().contacts[int(sample.contact_index)]
		var frame: Dictionary = GroundWheels.frame(_session.sim.state, contact,
			float(_session.sim.aux[_session.AUX_SERVO + 2]), _session.ground_surfaces,
			PackedFloat64Array(), false, {})
		var point: PackedFloat64Array = frame.position
		var normal: PackedFloat64Array = frame.normal
		var compression := float(frame.compression)
		var ground_ned := [point[0] + normal[0] * compression,
			point[1] + normal[1] * compression,
			point[2] + normal[2] * compression]
		center += Frames.ned_to_render(ground_ned)
		count += 1
	if count > 0:
		center /= float(count)
	var patch := MeshInstance3D.new()
	patch.name = "RoughSurfaceCapturePatch"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 2.4)
	patch.mesh = plane
	patch.position = center + Vector3(0.0, -0.006, 0.0)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.25, 0.20)
	material.roughness = 1.0
	patch.material_override = material
	_stage.add_child(patch)


func _add_camera_and_lights(contact_index: int) -> void:
	var contact: Dictionary = _session.current_landing_gear().contacts[contact_index]
	var role := "left" if str(contact.name) == "main_left" else "right"
	var wheel: Node3D = _airplane.gear[role]
	var focus := wheel.global_position
	var frame := GroundWheels.frame(_session.sim.state, contact,
		float(_session.sim.aux[_session.AUX_SERVO + 2]), _session.ground_surfaces,
		PackedFloat64Array(), false, {})
	var heading_ned: PackedFloat64Array = frame.heading
	var rearward := -Frames.ned_to_render(Array(heading_ned)).normalized()
	var surface_normal := Frames.ned_to_render(Array(frame.normal)).normalized()
	var side := surface_normal.cross(rearward).normalized()
	var camera := Camera3D.new()
	camera.position = focus + rearward * 0.18 + surface_normal * 0.13 + side * 0.09
	camera.fov = 47.0
	_stage.add_child(camera)
	camera.look_at(focus + surface_normal * 0.015, surface_normal)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key.light_energy = 0.95
	key.shadow_enabled = true
	_stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = focus + Vector3(-0.25, 0.30, 0.20)
	fill.omni_range = 1.4
	fill.light_energy = 0.25
	_stage.add_child(fill)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.80, 0.86, 0.90)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_stage.add_child(world_environment)


func _ground_contact_render_position(contact_index: int) -> Vector3:
	var contacts: Array = _session.current_landing_gear().get("contacts", [])
	if contact_index < 0 or contact_index >= contacts.size():
		return Vector3.ZERO
	var render_state: PackedFloat64Array = _session.sim.interpolated(Engine.get_physics_interpolation_fraction())
	var frame: Dictionary = GroundWheels.frame(render_state, contacts[contact_index],
		float(_session.sim.aux[_session.AUX_SERVO + 2]), _session.ground_surfaces,
		PackedFloat64Array(), false, {})
	var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
	var normal: PackedFloat64Array = frame.get("normal", PackedFloat64Array())
	var compression := maxf(0.0, float(frame.get("compression", 0.0)))
	return Frames.ned_to_render([
		position[0] + normal[0] * compression,
		position[1] + normal[1] * compression,
		position[2] + normal[2] * compression,
	])


func _write_report() -> void:
	var output := ProjectSettings.globalize_path(
		"res://../docs/research/timber-integration/TT-20/rough-ground-taxi.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("could not write rough taxi report: ", output)
		return
	file.store_string(JSON.stringify(_report, "\t") + "\n")


func _fail(message: String, details: Dictionary = {}) -> void:
	printerr("rough-ground taxi capture failed: ", message, " ", JSON.stringify(details))
	_report = {"schema": "timber-rough-ground-taxi-capture-v1", "failure": message, "details": details}
	_write_report()
	quit(1)
