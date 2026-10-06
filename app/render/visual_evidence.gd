# VQ-01b evidence only. No simulation mutation and no provenance guessed from a filename.
extends RefCounted

const BuildInfo = preload("res://app_state/build_info.gd")
const Frames = preload("res://render/frames.gd")
const POSES: Dictionary = {
	"level": [0.0, 0.0], "inverted": [0.0, 180.0],
	"knife_left": [0.0, -90.0], "knife_right": [0.0, 90.0],
	"climb": [45.0, 0.0], "dive": [-45.0, 0.0],
}
## Where the airplane sits as seen from the pilot's eyes: elevation above them and azimuth from north (degrees).
## VQ-01b's defaults (10° up, due north) stay; L6c lowers the elevation to put trees, the treetop edge or grass
## behind the airplane. Design values, not flight states; −2° at 100 m already puts the CG 1.8 m below the eyes.
const DEFAULT_ELEVATION_DEG: float = 10.0
const DEFAULT_AZIMUTH_DEG: float = 0.0
const ELEVATION_RANGE_DEG: Array = [-2.0, 45.0]


static func validate_pose(args: Dictionary) -> String:
	if not args.has("visual_pose") and not args.has("visual_distance") and not args.has("visual_elevation") and not args.has("visual_azimuth"):
		return ""
	if not args.has("capture") or not args.has("scripted"):
		return "visual poses require --capture --scripted (synthetic inspection only)"
	if not POSES.has(str(args.get("visual_pose", ""))):
		return "unknown --visual_pose"
	var value: String = str(args.get("visual_distance", ""))
	if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float() < 5.0 or value.to_float() > 1000.0:
		return "--visual_distance must be finite and between 5 and 1000 metres"
	if args.has("visual_elevation"):
		var elevation: String = str(args.visual_elevation)
		if not elevation.is_valid_float() or not is_finite(elevation.to_float()) or elevation.to_float() < ELEVATION_RANGE_DEG[0] or elevation.to_float() > ELEVATION_RANGE_DEG[1]:
			return "--visual_elevation must be finite and between %d and %d degrees" % [ELEVATION_RANGE_DEG[0], ELEVATION_RANGE_DEG[1]]
	if args.has("visual_azimuth"):
		var azimuth: String = str(args.visual_azimuth)
		if not azimuth.is_valid_float() or not is_finite(azimuth.to_float()) or azimuth.to_float() < 0.0 or azimuth.to_float() >= 360.0:
			return "--visual_azimuth must be finite and between 0 and 360 degrees"
	if args.has("inspect") or args.has("look_az"):
		return "visual poses require the pilot camera: no --inspect or --look_az"
	# The view is part of the case: VQ-01b's shared fixture pins --autozoom=0; L6c's game view declares --autozoom=1.
	if not str(args.get("autozoom", "")) in ["0", "1"]:
		return "visual poses require an explicit --autozoom=0 (fixed 50° fixture) or --autozoom=1 (the game's view)"
	return ""


## Six render-only poses, side-on with the nose to the pilot's right: at `distance` from the pilot's eyes,
## `elevation_deg` above them and `azimuth_deg` from north (the defaults: 10° up, due north, heading east).
## Distances, angles and attitudes are test design values, not measured flight states.
static func synthetic_pose(pose_name: String, distance: float, eye_height: float,
		elevation_deg: float = DEFAULT_ELEVATION_DEG, azimuth_deg: float = DEFAULT_AZIMUTH_DEG) -> Dictionary:
	var angles: Array = POSES[pose_name]
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	return {
		pos = Frames.ned_to_render([distance * cos(el) * cos(az), distance * cos(el) * sin(az), -(eye_height + distance * sin(el))]),
		basis = Frames.attitude_to_render(az + PI / 2.0, deg_to_rad(angles[0]), deg_to_rad(angles[1])),
	}


static func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func transform(value: Transform3D) -> Dictionary:
	return {position = vector(value.origin), basis_columns = [vector(value.basis.x), vector(value.basis.y), vector(value.basis.z)]}


static func provenance() -> Dictionary:
	var build: Dictionary = BuildInfo.current()
	var revision: String = OS.get_environment("OPENRC_CODE_REVISION")
	if revision == "":
		revision = str(build.commit) if build.commit != "" else "unavailable"
	var hashes: Dictionary = {}
	# Include source, shaders, generated geometry, physical data and assets. Exclude generated captures,
	# import caches and test output. Exported packs may omit sources: report that limitation explicitly.
	for directory in ["res://assets/landscape/trees", "res://render", "res://aircraft", "res://data", "res://ui", "res://app_state", "res://sim", "res://physics", "res://input", "res://i18n"]:
		_hash_directory(directory, hashes)
	for path in ["res://main.gd", "res://main.tscn", "res://spec.gd", "res://project.godot", "res://app_root.gd", "res://app_root.tscn", "res://tests/fixtures/atmosphere_field.gd", "res://tests/fixtures/atmosphere_field.tscn"]:
		if FileAccess.file_exists(path):
			hashes[path] = FileAccess.get_sha256(path)
	return {build = build, code_revision = revision, source_sha256 = hashes,
		source_scope = "runtime source tree; imported/exported resources may omit original files", source_tree_available = hashes.has("res://main.gd")}


static func _hash_directory(path: String, hashes: Dictionary) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename in directory.get_files():
		if filename.ends_with(".uid") or filename.ends_with(".import"):
			continue
		var resource: String = path.path_join(filename)
		hashes[resource] = FileAccess.get_sha256(resource)
	for child in directory.get_directories():
		if not child.begins_with("."):
			_hash_directory(path.path_join(child), hashes)
