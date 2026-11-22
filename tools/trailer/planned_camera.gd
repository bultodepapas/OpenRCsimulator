## R6 presentation camera, composed after the existing flight director.
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
func configure(flight_main: Node, recipe: Dictionary) -> String:
	if _configured or not _error.is_empty():
		return _fail("planned camera can only be configured once")
	if not is_instance_valid(flight_main):
		return _fail("planned camera requires a live Main node")
	var error := validate_recipe(recipe)
	if not error.is_empty():
		return _fail(error)
	_main = flight_main
	_recipe = recipe.duplicate(true)
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
	if typeof(recipe.get("target")) != TYPE_STRING or recipe.target != "presented_cg":
		return "planned camera target must be presented_cg"
	var fov: Variant = recipe.get("fov_deg")
	if not _is_number(fov) or not is_finite(float(fov)) or float(fov) < MIN_FOV_DEG or float(fov) > MAX_FOV_DEG:
		return "planned camera fov_deg must be finite and between 2 and 120"
	var mode: Variant = recipe.get("mode")
	if typeof(mode) != TYPE_STRING or mode not in ["fixed_world", "parallel_east"]:
		return "planned camera mode must be fixed_world or parallel_east"
	var allowed: Array = COMMON_KEYS + (FIXED_KEYS if mode == "fixed_world" else PARALLEL_KEYS)
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
	var pose_value: Variant = _main.get("_last_render_pose")
	if typeof(pose_value) != TYPE_DICTIONARY or typeof(pose_value.get("pos")) != TYPE_VECTOR3:
		_fail("planned camera cannot read the presented CG")
		return false
	var target: Vector3 = pose_value.pos
	if not _finite_vector(target):
		_fail("planned camera presented CG is not finite")
		return false
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
	# A displaced optical eye would invalidate both the requested eye and CG-centered aim.
	if not is_finite(camera.h_offset) or not is_finite(camera.v_offset) or camera.h_offset != 0.0 or camera.v_offset != 0.0:
		_fail("planned camera requires zero Camera3D optical offsets")
		return false
	var eye_ned: Array
	if _recipe.mode == "fixed_world":
		eye_ned = _recipe.eye_ned_m.duplicate()
	else:
		eye_ned = [float(_recipe.north_m), float(target.x) + float(_recipe.east_offset_m), float(_recipe.down_m)]
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
		_fail("planned camera eye and presented CG coincide")
		return false
	if horizontal_squared <= distance_squared * MIN_HORIZONTAL_FRACTION_SQUARED:
		_fail("planned camera cannot use world up for a vertical look")
		return false
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
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
		"shot_id": str(_recipe.shot_id),
		"vehicle_id": str(_recipe.vehicle_id),
		"source_plan_sha256": str(_recipe.source_plan_sha256),
		"mode": str(_recipe.mode),
		"target": "presented_cg",
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


func _fail(message: String) -> String:
	if _error.is_empty():
		_error = message
	_frame_record = {"valid": false, "error": _error}
	return _error


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _v3(value: Vector3) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z)]
