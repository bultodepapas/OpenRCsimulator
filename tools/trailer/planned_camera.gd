## Presentation camera, composed after the existing flight director.
## It reads the displayed CG and changes only Camera3D presentation properties.
extends Node

const FORMAT := "openrc-trailer-camera"
const MAX_RECIPE_BYTES := 65536
const COORDINATE_LIMIT_M := 100000.0
const MIN_FOV_DEG := 2.0
const MAX_FOV_DEG := 120.0
const MIN_DISTANCE_SQUARED := 0.000001
const MIN_HORIZONTAL_FRACTION_SQUARED := 0.0000000001
const COMMON_KEYS := ["format", "version", "shot_id", "vehicle_id", "source_plan_sha256", "mode", "target", "fov_deg"]
const FIXED_KEYS := ["eye_ned_m"]
const PARALLEL_KEYS := ["north_m", "down_m", "east_offset_m"]

var _main: Node
var _recipe: Dictionary = {}
var _error := ""
var _configured := false
var _frame_record: Dictionary = {}
var _tick_provider := Callable()


## Read and hash exactly the bounded input bytes that are validated and retained.
static func read_recipe_file(path: String) -> Dictionary:
	if path.is_empty() or not path.is_absolute_path():
		return {"ok": false, "error": "--camera-recipe must be an absolute JSON file path"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "camera recipe file cannot be opened"}
	var size := file.get_length()
	if size <= 0 or size > MAX_RECIPE_BYTES:
		file.close()
		return {"ok": false, "error": "camera recipe file must contain 1 to %d bytes" % MAX_RECIPE_BYTES}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size:
		return {"ok": false, "error": "camera recipe file could not be read completely"}
	return parse_recipe_bytes(bytes)


static func parse_recipe_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_RECIPE_BYTES:
		return {"ok": false, "error": "camera recipe file must contain 1 to %d bytes" % MAX_RECIPE_BYTES}
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return {"ok": false, "error": "camera recipe must be valid UTF-8"}
	var parser := JSON.new()
	if parser.parse(source) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "camera recipe must be a JSON object"}
	var error := validate_recipe(parser.data)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK or digest.update(bytes) != OK:
		return {"ok": false, "error": "camera recipe bytes could not be hashed"}
	return {"ok": true, "recipe": parser.data.duplicate(true), "sha256": digest.finish().hex_encode()}


## The caller validates the selected flight identity before starting Main.
## This method does not enter the tree or touch the camera or simulation.
func configure(flight_main: Node, recipe: Dictionary, tick_provider: Callable = Callable()) -> String:
	if _configured or not _error.is_empty():
		return _fail("planned camera can only be configured once")
	if not is_instance_valid(flight_main):
		return _fail("planned camera requires a live Main node")
	var error := validate_recipe(recipe)
	if not error.is_empty():
		return _fail(error)
	_main = flight_main
	_recipe = recipe.duplicate(true)
	_tick_provider = tick_provider
	_configured = true
	process_priority = 20 # Main (0), existing flight director (10), this camera (20), planar reflection (100).
	return ""


static func validate_recipe(recipe: Dictionary) -> String:
	if typeof(recipe.get("format")) != TYPE_STRING or recipe.format != FORMAT:
		return "planned camera format is invalid"
	var version: Variant = recipe.get("version")
	if not _is_number(version) or not is_finite(float(version)) or float(version) != 1.0:
		return "planned camera version must be 1"
	for field: String in ["shot_id", "vehicle_id"]:
		if typeof(recipe.get(field)) != TYPE_STRING or str(recipe[field]).strip_edges().is_empty():
			return "planned camera " + field + " must be a nonempty string"
	var source_hash: Variant = recipe.get("source_plan_sha256")
	if typeof(source_hash) != TYPE_STRING or not _is_sha256(source_hash):
		return "planned camera source_plan_sha256 must contain 64 hexadecimal characters"
	var target: Variant = recipe.get("target")
	if typeof(target) != TYPE_STRING or target not in ["presented_cg", "presented_cg_water_plane"]:
		return "planned camera target must be presented_cg or presented_cg_water_plane"
	if target == "presented_cg_water_plane" and not _bounded_coordinate(recipe.get("water_down_m")):
		return "presented_cg_water_plane requires finite bounded water_down_m"
	if target == "presented_cg" and recipe.has("water_down_m"):
		return "presented_cg does not accept water_down_m"
	var fov: Variant = recipe.get("fov_deg")
	if not _is_number(fov) or not is_finite(float(fov)) or float(fov) < MIN_FOV_DEG or float(fov) > MAX_FOV_DEG:
		return "planned camera fov_deg must be finite and between 2 and 120"
	var mode: Variant = recipe.get("mode")
	if typeof(mode) != TYPE_STRING or mode not in ["fixed_world", "parallel_east"]:
		return "planned camera mode must be fixed_world or parallel_east"
	var allowed: Array = COMMON_KEYS + (FIXED_KEYS if mode == "fixed_world" else PARALLEL_KEYS)
	if target == "presented_cg_water_plane":
		allowed.append("water_down_m")
	for key: Variant in recipe:
		if typeof(key) != TYPE_STRING or key not in allowed:
			return "planned camera has an unsupported field: " + str(key)
	if mode == "fixed_world":
		var eye: Variant = recipe.get("eye_ned_m")
		if typeof(eye) != TYPE_ARRAY or eye.size() != 3:
			return "fixed_world requires eye_ned_m as [north, east, down]"
		for component: Variant in eye:
			if not _bounded_coordinate(component):
				return "fixed_world eye_ned_m must contain finite bounded numbers"
	else:
		for field: String in PARALLEL_KEYS:
			if not _bounded_coordinate(recipe.get(field)):
				return "parallel_east " + field + " must be a finite bounded number"
	return ""


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


static func _bounded_coordinate(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and absf(float(value)) <= COORDINATE_LIMIT_M


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for i: int in value.length():
		if "0123456789abcdefABCDEF".find(value.substr(i, 1)) < 0:
			return false
	return true


func configuration_error() -> String:
	return _error


func _process(_delta: float) -> void:
	apply_frame()


## Returns false permanently after a failure. The caller must mark that take incomplete.
func apply_frame() -> bool:
	if not _error.is_empty():
		return false
	if not _configured or not is_instance_valid(_main):
		_fail("planned camera has no configured live Main")
		return false
	# Capture the actual engine process generation before placement. This is not
	# inferred from motion: a stationary subject still requires a new application.
	var process_frame := Engine.get_process_frames()
	var sim_tick: Variant = null
	if _tick_provider.is_valid():
		sim_tick = _tick_provider.call()
		if typeof(sim_tick) != TYPE_INT or int(sim_tick) < 0:
			_fail("planned camera cannot read a valid simulation tick")
			return false
	var pose_value: Variant = _main.get("_last_render_pose")
	if typeof(pose_value) != TYPE_DICTIONARY or typeof(pose_value.get("pos")) != TYPE_VECTOR3:
		_fail("planned camera cannot read the presented CG")
		return false
	var presented_cg: Vector3 = pose_value.pos
	if not _finite_vector(presented_cg):
		_fail("planned camera presented CG is not finite")
		return false
	var target := presented_cg
	if _recipe.target == "presented_cg_water_plane":
		target.y = -float(_recipe.water_down_m)
	var rig: Variant = _main.get("_rig")
	if not rig is Object or not is_instance_valid(rig):
		_fail("planned camera requires a live camera rig")
		return false
	var camera_value: Variant = rig.get("camera")
	if not camera_value is Camera3D or not is_instance_valid(camera_value):
		_fail("planned camera requires a live Camera3D")
		return false
	var camera: Camera3D = camera_value
	if not camera.is_inside_tree() or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		_fail("planned camera requires an in-tree perspective Camera3D")
		return false
	# A displaced optical eye would invalidate both the requested eye and the aim.
	if not is_finite(camera.h_offset) or not is_finite(camera.v_offset) or camera.h_offset != 0.0 or camera.v_offset != 0.0:
		_fail("planned camera requires zero Camera3D optical offsets")
		return false
	var eye_ned: Array
	if _recipe.mode == "fixed_world":
		eye_ned = _recipe.eye_ned_m.duplicate()
	else:
		eye_ned = [float(_recipe.north_m), float(presented_cg.x) + float(_recipe.east_offset_m), float(_recipe.down_m)]
	for component: Variant in eye_ned:
		if not _bounded_coordinate(component):
			_fail("planned camera computed eye is outside the finite coordinate bounds")
			return false
	# NED (north, east, down) -> render (east, -down, -north).
	var eye := Vector3(float(eye_ned[1]), -float(eye_ned[2]), -float(eye_ned[0]))
	var dx := float(target.x) - float(eye.x)
	var dy := float(target.y) - float(eye.y)
	var dz := float(target.z) - float(eye.z)
	var distance_squared := dx * dx + dy * dy + dz * dz
	var horizontal_squared := dx * dx + dz * dz
	if not is_finite(distance_squared) or distance_squared <= MIN_DISTANCE_SQUARED:
		_fail("planned camera eye and aim coincide")
		return false
	if horizontal_squared <= distance_squared * MIN_HORIZONTAL_FRACTION_SQUARED:
		_fail("planned camera cannot use world up for a vertical look")
		return false
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT # The recipe's FOV is vertical.
	camera.fov = float(_recipe.fov_deg)
	var transform := camera.get_camera_transform()
	if not _finite_vector(transform.origin) or not _finite_vector(transform.basis.x) \
			or not _finite_vector(transform.basis.y) or not _finite_vector(transform.basis.z) \
			or absf(transform.basis.determinant()) < 0.00000001:
		_fail("planned camera produced an invalid optical transform")
		return false
	var quaternion := transform.basis.get_rotation_quaternion().normalized()
	if not is_finite(quaternion.x) or not is_finite(quaternion.y) or not is_finite(quaternion.z) \
			or not is_finite(quaternion.w) or not is_finite(camera.fov):
		_fail("planned camera produced a nonfinite rotation or FOV")
		return false
	_frame_record = {
		"valid": true,
		"process_frame": process_frame,
		"sim_tick": sim_tick,
		"shot_id": str(_recipe.shot_id),
		"vehicle_id": str(_recipe.vehicle_id),
		"source_plan_sha256": str(_recipe.source_plan_sha256),
		"mode": str(_recipe.mode),
		"target": str(_recipe.target),
		"water_down_m": float(_recipe.water_down_m) if _recipe.target == "presented_cg_water_plane" else null,
		"presented_cg_render_m": _v3(presented_cg),
		"presented_cg_ned_m": [-float(presented_cg.z), float(presented_cg.x), -float(presented_cg.y)],
		"target_render_m": _v3(target),
		"target_ned_m": [-float(target.z), float(target.x), -float(target.y)],
		"requested_eye_ned_m": [float(eye_ned[0]), float(eye_ned[1]), float(eye_ned[2])],
		"actual_eye_render_m": _v3(transform.origin),
		"actual_quaternion_xyzw": [float(quaternion.x), float(quaternion.y), float(quaternion.z), float(quaternion.w)],
		"requested_fov_deg": float(_recipe.fov_deg),
		"actual_fov_deg": float(camera.fov),
		"projection": int(camera.projection),
		"keep_aspect": int(camera.keep_aspect),
	}
	return true


func frame_record() -> Dictionary:
	return _frame_record.duplicate(true)


## Check the admitted recipe against both the recorded presentation and the live
## camera/pose. In particular, a water-plane aim must not stand in for the CG.
static func frame_evidence_error(evidence: Dictionary, recipe: Dictionary, pose: Variant, camera: Camera3D,
		expected_sim_tick: Variant = null) -> String:
	if not validate_recipe(recipe).is_empty():
		return "The planned camera recipe is invalid."
	if typeof(evidence.get("valid")) != TYPE_BOOL or not evidence.valid:
		return "No valid planned camera evidence was recorded for the presented frame."
	if typeof(evidence.get("process_frame")) != TYPE_INT \
			or int(evidence.process_frame) != Engine.get_process_frames():
		return "Planned camera evidence is from a different engine process frame."
	if expected_sim_tick != null and (typeof(expected_sim_tick) != TYPE_INT or int(expected_sim_tick) < 0 \
			or typeof(evidence.get("sim_tick")) != TYPE_INT or int(evidence.sim_tick) != int(expected_sim_tick)):
		return "Planned camera evidence is from a different simulation tick."
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return "The planned camera is unavailable."
	if typeof(pose) != TYPE_DICTIONARY or typeof(pose.get("pos")) != TYPE_VECTOR3 \
			or not _finite_vector(pose.pos):
		return "The latest presented CG is unavailable or nonfinite."
	if evidence.get("target") != recipe.target or evidence.get("mode") != recipe.mode \
			or evidence.get("shot_id") != recipe.shot_id or evidence.get("vehicle_id") != recipe.vehicle_id \
			or evidence.get("source_plan_sha256") != recipe.source_plan_sha256:
		return "Planned camera evidence does not match the admitted recipe."
	if not evidence.has("water_down_m"):
		return "Planned camera evidence omits the water plane."
	if recipe.target == "presented_cg_water_plane":
		if not _is_number(evidence.water_down_m) or not is_finite(float(evidence.water_down_m)) \
				or float(evidence.water_down_m) != float(recipe.water_down_m):
			return "Planned camera evidence does not match the admitted water plane."
	elif evidence.water_down_m != null:
		return "CG-targeted camera evidence cannot specify a water plane."
	for field: String in ["presented_cg_render_m", "presented_cg_ned_m", "target_render_m", "target_ned_m",
			"requested_eye_ned_m", "actual_eye_render_m"]:
		if not _number_array(evidence.get(field), 3):
			return "Planned camera evidence has an invalid " + field + "."
	if not _number_array(evidence.get("actual_quaternion_xyzw"), 4):
		return "Planned camera evidence has an invalid rotation."
	for field: String in ["requested_fov_deg", "actual_fov_deg"]:
		if not _is_number(evidence.get(field)) or not is_finite(float(evidence[field])):
			return "Planned camera evidence has an invalid FOV."
	if typeof(evidence.get("projection")) != TYPE_INT or typeof(evidence.get("keep_aspect")) != TYPE_INT \
			or int(evidence.projection) != Camera3D.PROJECTION_PERSPECTIVE \
			or int(evidence.keep_aspect) != Camera3D.KEEP_HEIGHT \
			or camera.projection != Camera3D.PROJECTION_PERSPECTIVE or camera.keep_aspect != Camera3D.KEEP_HEIGHT \
			or camera.h_offset != 0.0 or camera.v_offset != 0.0 \
			or not is_equal_approx(float(evidence.requested_fov_deg), float(recipe.fov_deg)) \
			or not is_equal_approx(float(evidence.actual_fov_deg), float(recipe.fov_deg)) \
			or not is_equal_approx(float(camera.fov), float(recipe.fov_deg)):
		return "Planned camera projection, vertical FOV or optical offsets changed after placement."
	var cg: Vector3 = pose.pos
	var aim := cg
	if recipe.target == "presented_cg_water_plane":
		aim.y = -float(recipe.water_down_m)
	var expected_eye_ned: Vector3
	if recipe.mode == "fixed_world":
		expected_eye_ned = _array_to_vector(recipe.eye_ned_m)
	else:
		expected_eye_ned = Vector3(float(recipe.north_m), float(cg.x) + float(recipe.east_offset_m), float(recipe.down_m))
	var expected_eye := Vector3(expected_eye_ned.y, -expected_eye_ned.z, -expected_eye_ned.x)
	var actual := camera.get_camera_transform()
	if not _finite_vector(actual.origin) or not _finite_vector(actual.basis.x) \
			or not _finite_vector(actual.basis.y) or not _finite_vector(actual.basis.z) \
			or not is_finite(actual.basis.determinant()) or absf(actual.basis.determinant()) < 0.00000001:
		return "The planned camera transform is invalid."
	var quaternion_values: Array = evidence.actual_quaternion_xyzw
	var recorded_rotation := Quaternion(float(quaternion_values[0]), float(quaternion_values[1]),
		float(quaternion_values[2]), float(quaternion_values[3]))
	var current_rotation := actual.basis.get_rotation_quaternion().normalized()
	var view_direction := aim - actual.origin
	var view_length_squared := view_direction.length_squared()
	var rotation_length_squared := recorded_rotation.length_squared()
	var rotation_dot := recorded_rotation.dot(current_rotation)
	if not _finite_vector(view_direction) or not is_finite(view_length_squared) \
			or view_length_squared <= MIN_DISTANCE_SQUARED or not is_finite(rotation_length_squared) \
			or not is_finite(rotation_dot):
		return "The planned camera direction or recorded rotation is invalid."
	var aim_dot := (-actual.basis.z.normalized()).dot(view_direction.normalized())
	if not _array_to_vector(evidence.presented_cg_render_m).is_equal_approx(cg) \
			or not _array_to_vector(evidence.presented_cg_ned_m).is_equal_approx(Vector3(-cg.z, cg.x, -cg.y)) \
			or not _array_to_vector(evidence.target_render_m).is_equal_approx(aim) \
			or not _array_to_vector(evidence.target_ned_m).is_equal_approx(Vector3(-aim.z, aim.x, -aim.y)) \
			or not _array_to_vector(evidence.requested_eye_ned_m).is_equal_approx(expected_eye_ned) \
			or not _array_to_vector(evidence.actual_eye_render_m).is_equal_approx(actual.origin) \
			or not actual.origin.is_equal_approx(expected_eye) \
			or absf(rotation_length_squared - 1.0) > 0.00001 \
			or absf(rotation_dot) < 0.99999 or not is_finite(aim_dot) or aim_dot < 0.99999:
		return "Camera transform, aim or presented CG changed after planned placement."
	return ""


static func _number_array(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != count:
		return false
	for item: Variant in value:
		if not _is_number(item) or not is_finite(float(item)):
			return false
	return true


static func _array_to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _fail(message: String) -> String:
	if _error.is_empty():
		_error = message
	_frame_record = {"valid": false, "error": _error}
	return _error


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _v3(value: Vector3) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z)]
