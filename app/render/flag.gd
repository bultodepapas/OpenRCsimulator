## L15c: one opaque cloth surface; simulation wind is read only at Field's boundary.
extends MeshInstance3D

const Motion = preload("res://render/flag_motion.gd")
const Quality = preload("res://render/flag_quality.gd")
const Identity = preload("res://app_state/flag_identity.gd")
const Finish = preload("res://render/flag.gdshader")
const GROUP := "landscape_flags"
static var _meshes: Dictionary = {}

var _identity: RefCounted = Identity.shared()
var _motion: RefCounted
var _material: ShaderMaterial
var _profile: Dictionary = {}
var _descriptor: Dictionary = {}
var _pending: Dictionary = {}
var _desired_country := ""
var _country := ""
var _time := 0.0
var _wind := Vector3.ZERO
var _published_revision := -1
var _uploads := 0
var _failed_countries: Dictionary = {}
var _last_lod_time := -INF
var _lod_grid := Vector2i.ZERO

static func build(part: Dictionary, xf: Transform3D, seed_value: int) -> MeshInstance3D:
	var result := load("res://render/flag.gd").new() as MeshInstance3D
	result.name = "flag_%d" % seed_value
	result.transform = xf * Transform3D(Basis.IDENTITY, part.pivot)
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.set_meta("wind_cue_kind", "flag")
	result.set_meta("wind_sample_offset", Vector3(0,-0.45,0))
	result.configure()
	return result

func configure() -> void:
	_material = ShaderMaterial.new()
	_material.shader = Finish
	material_override = _material
	_descriptor = _identity.descriptor("US")
	apply_quality()
	_sync_locale()

## A request has an owner independent of the landscape. Freeing a loading field
## cannot abandon ResourceLoader's request token. This node holds no flag strongly.
class TextureRequest extends Node:
	var target: WeakRef
	var descriptor: Dictionary
	var requested := false

	func _ready() -> void:
		# Resource ownership must drain even when the SceneTree is paused.
		process_mode = Node.PROCESS_MODE_ALWAYS
		add_to_group("flag_texture_requests")
		if not is_instance_valid(target.get_ref()):
			queue_free()
			return
		var error := ResourceLoader.load_threaded_request(descriptor.front_path, "Texture2D")
		if error != OK:
			_finish(null)
			return
		requested = true

	func _process(_delta: float) -> void:
		if not requested:
			return
		var status := ResourceLoader.load_threaded_get_status(descriptor.front_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		# Collect terminal failures too: each successful request needs exactly one get.
		var texture := ResourceLoader.load_threaded_get(descriptor.front_path) as Texture2D
		requested = false
		_finish(texture)

	func _finish(texture: Texture2D) -> void:
		var flag: Node = target.get_ref()
		if is_instance_valid(flag):
			flag._texture_completed(descriptor, texture)
		queue_free()

func _enter_tree() -> void:
	# A detached landscape misses quality group notifications. Re-entry does
	# not run _ready again, and must not retain an obsolete expensive profile.
	if _material != null:
		apply_quality()

func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)
	_sync_locale()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _material != null:
		_sync_locale()

func _sync_locale() -> void:
	_desired_country = _identity.country_for_locale(TranslationServer.get_locale())
	if not is_inside_tree() or _desired_country == _country or not _pending.is_empty():
		return
	if _failed_countries.has(_desired_country):
		_desired_country = "US"
		if _country == "US" or _failed_countries.has("US"):
			return
	_pending = _identity.descriptor(_desired_country)
	var request := TextureRequest.new()
	request.name = "FlagTextureRequest"
	request.target = weakref(self)
	request.descriptor = _pending.duplicate()
	# Deferral also supports _ready during a parent's child insertion.
	get_tree().root.add_child.call_deferred(request)

func _texture_completed(descriptor: Dictionary, texture: Texture2D) -> void:
	if texture != null and descriptor.country == _desired_country:
		_descriptor = descriptor
		_country = descriptor.country
		_material.set_shader_parameter("country_texture",texture)
		_rebuild_motion()
	elif texture == null:
		_failed_countries[descriptor.country] = true
		push_warning("Country flag resource unavailable: %s" % descriptor.country)
	_pending.clear()
	if _country != _desired_country:
		_sync_locale()

func apply_quality() -> void:
	var next := Quality.profile()
	if next == _profile:
		return
	_profile = next
	_lod_grid = Vector2i(int(next.grid_x),int(next.grid_y))
	mesh = _grid(_lod_grid.x,_lod_grid.y)
	_last_lod_time = -INF
	var detailed: bool = next.mode == "detailed"
	_material.set_shader_parameter("fine_fabric", detailed)
	_material.set_shader_parameter("weave_texture", load("res://assets/landscape/windsock/Fabric001_1K-JPG_NormalGL.jpg") if detailed else null)
	_material.set_shader_parameter("weave_color", load("res://assets/landscape/windsock/Fabric001_1K-JPG_Color.jpg") if detailed else null)
	_material.set_shader_parameter("weave_roughness", load("res://assets/landscape/windsock/Fabric001_1K-JPG_Roughness.jpg") if detailed else null)
	_rebuild_motion()

func needs_wind() -> bool:
	return _profile.get("mode", "static") != "static"

func _rebuild_motion() -> void:
	var length_m: float = _descriptor.length_m
	var height_m: float = _descriptor.height_m
	_material.set_shader_parameter("cloth_size", Vector2(length_m,height_m))
	if needs_wind():
		if _motion == null:
			_motion = Motion.new(length_m,height_m,_profile.mode)
			_motion.reset(_time,_wind)
		else:
			var resized: bool = _motion.resize(length_m,height_m)
			var changed_mode: bool = _motion.set_mode(_profile.mode)
			if not resized or not changed_mode:
				# Unusual changes near the mast use the validated calm pose atomically.
				_motion = Motion.new(length_m,height_m,_profile.mode)
				_motion.reset(_time,_wind)
	else:
		_motion = null
		var points := PackedVector3Array()
		for row in 5:
			for col in 9:
				var u := col / 8.0
				points.append(Vector3(length_m*u*0.35,-height_m*row/4.0-length_m*u*0.8,0.03*sin(u*PI)))
		_material.set_shader_parameter("cloth_points",points)
		_material.set_shader_parameter("cloth_energy",0.0)
	custom_aabb = AABB(Vector3(-length_m-0.2,-height_m-length_m-0.2,-length_m-0.2),Vector3(2*length_m+0.4,height_m+2*length_m+0.4,2*length_m+0.4))
	_published_revision = -1
	publish()

func advance_wind(time_s: float, wind_ned: Array) -> void:
	if _motion == null or not _valid(time_s,wind_ned):
		return
	var basis_world := global_basis if is_inside_tree() else basis
	var next_wind := basis_world.inverse() * Vector3(wind_ned[1],-wind_ned[2],-wind_ned[0])
	if _motion.update_to(time_s,next_wind):
		_time = time_s
		_wind = next_wind

func reset_wind(time_s: float, wind_ned: Array) -> void:
	if _motion == null or not _valid(time_s,wind_ned):
		return
	_time = time_s
	var basis_world := global_basis if is_inside_tree() else basis
	_wind = basis_world.inverse() * Vector3(wind_ned[1],-wind_ned[2],-wind_ned[0])
	_motion.reset(time_s,_wind)
	_published_revision = -1
	publish()

func publish() -> void:
	_update_lod()
	if _motion == null or _published_revision == int(_motion.revision):
		return
	_material.set_shader_parameter("cloth_points",_motion.points)
	_material.set_shader_parameter("cloth_phase",_motion.phase)
	_material.set_shader_parameter("cloth_energy",_motion.energy)
	_published_revision = _motion.revision
	_uploads += 1

## Only mesh density and microtexture change with distance, never the cloth state.
func _update_lod() -> void:
	if not is_inside_tree() or _profile.mode != "detailed":
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var clock := Time.get_ticks_msec() * 0.001
	if clock-_last_lod_time < 0.1:
		return
	_last_lod_time = clock
	var size_y := float(get_viewport().get_visible_rect().size.y)
	# A nominal camera-facing height, not the changing cloth footprint. Using
	# the projection handles KEEP_WIDTH, orthographic size and offset frusta.
	# Camera-space depth avoids reducing detail at the same depth off axis.
	var pixels := 0.5 * size_y * float(_descriptor.height_m) * absf(camera.get_camera_projection().y.y)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		var camera_transform := camera.get_camera_transform()
		var depth := camera_transform.basis.z.dot(camera_transform.origin-global_position)
		# Conservatively retain detail near/behind the near plane; never divide
		# by zero when the camera crosses the hoist during a paused inspection.
		pixels /= maxf(depth, maxf(camera.near, 0.001))
	# Hysteresis avoids mesh thrashing while moving around a threshold.
	var next := _lod_grid
	if pixels < 24.0: next = Vector2i(8,4)
	elif pixels > 32.0 and pixels < 90.0: next = Vector2i(16,8)
	elif pixels > 110.0: next = Vector2i(int(_profile.grid_x),int(_profile.grid_y))
	next.x = mini(next.x,int(_profile.grid_x))
	next.y = mini(next.y,int(_profile.grid_y))
	if next != _lod_grid:
		_lod_grid = next
		mesh = _grid(next.x,next.y)
		_material.set_shader_parameter("fine_fabric",next.x > 8)

func diagnostics() -> Dictionary:
	return {country=_country,pending_country=_pending.get("country",""),profile=_profile.duplicate(),
		uploads=_uploads,lod_grid=_lod_grid,motion=_motion.state_snapshot() if _motion != null else {},
		length_m=_descriptor.length_m,height_m=_descriptor.height_m}

static func _valid(time_s: float, wind: Array) -> bool:
	if not is_finite(time_s) or time_s < 0.0 or wind.size()!=3:
		return false
	for value: Variant in wind:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	return true

static func _grid(columns: int, rows: int) -> ArrayMesh:
	var key := Vector2i(columns,rows)
	if _meshes.has(key):
		return _meshes[key]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows+1:
		for col in columns+1:
			var uv := Vector2(col/float(columns),row/float(rows))
			vertices.append(Vector3(uv.x,-uv.y,0))
			normals.append(Vector3.BACK)
			uvs.append(uv)
	for row in rows:
		for col in columns:
			var a := row*(columns+1)+col
			indices.append_array(PackedInt32Array([a,a+1,a+columns+1,a+1,a+columns+2,a+columns+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_meshes[key]=result
	return result
