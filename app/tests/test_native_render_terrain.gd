extends SceneTree
## NK-8b: FlightSession.render_terrain_sample equals GroundTerrain.sample(north, east, ground_surfaces) bit for bit:
## 20,000 points over and beyond the production field (edges, far away, non-finite coordinates) on a native session,
## the native answer used; after the field's surfaces change, the prepared table follows; a session without a field
## and the hook off keep the GDScript sample. Skips (passes) without the verified library.

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)


func _session(field: Dictionary) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup("res://data/aircraft/f4u_corsair_250.json", "f4u-corsair-250")
	root.add_child(s)
	s.set_process(false)
	s.set_physics_process(false)
	if not field.is_empty():
		s.set_field(field)
	return s


## Points; how many differ from GroundTerrain.sample; how many the native stage answered.
func _compare(s: Node, count: int) -> Array:
	var mismatched := 0
	var native := 0
	for i: int in count:
		var north: float = _rng.randf_range(-400.0, 400.0)
		var east: float = _rng.randf_range(-400.0, 400.0)
		match i % 10:
			0: north = _rng.randf_range(-5000.0, 5000.0)
			1: east = [NAN, INF, -INF][i % 3]
			2: north = snappedf(north, 8.0) # cell and rectangle edges
			3: east = -0.0
		var expected: PackedFloat64Array = GroundTerrain.sample(north, east, s.ground_surfaces)
		if s._native_stage != null and s.native_render_terrain_enabled \
				and s._native_stage.render_terrain_sample(north, east, s.ground_surfaces).size() == 3:
			native += 1
		if var_to_bytes(s.render_terrain_sample(north, east)) != var_to_bytes(expected):
			mismatched += 1
	return [mismatched, native]


func _run() -> void:
	if not NativeStage.library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stage_terrain_sample"):
		print("NK8B_SKIP no native library with the render terrain sample")
		quit(0)
		return
	_rng.seed = 8282
	var field: Dictionary = FieldLoader.load_from().field
	var s := _session(field)
	var native_ok: bool = s.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE and not s.ground_surfaces.is_empty()
	_check("a native session with the production field's surfaces", native_ok)
	var result := _compare(s, 20000)
	_check("20,000 render samples equal GroundTerrain.sample (%d answered natively)" % result[1],
		result[0] == 0 and result[1] == 20000, str(result[0]))
	# A changed table re-prepares the stage; the answer follows the table, never the old preparation.
	var changed: PackedFloat64Array = s.ground_surfaces.duplicate()
	s.ground_surfaces = changed
	result = _compare(s, 2000)
	_check("after the surfaces are set again the samples still equal (%d native)" % result[1], result[0] == 0,
		str(result[0]))
	s.native_render_terrain_enabled = false
	result = _compare(s, 2000)
	_check("the hook off samples in GDScript", result[0] == 0)
	s.free()
	var bare := _session({})
	result = _compare(bare, 2000)
	_check("without a field (the flat fixture) the GDScript sample answers", result[0] == 0 and result[1] == 0,
		"%s" % [result])
	bare.free()
	print("native render terrain: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
