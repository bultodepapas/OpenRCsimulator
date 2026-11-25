extends SceneTree
## NK-5c: the native configuration guard walks the prepared aircraft dictionary through primed per-leaf fast paths
## (the parent container captured once, String keys looked up as the equal StringName, expected scalars captured as
## raw values). Every in-place mutation of a nested leaf must still refuse the configuration, and restoring the
## original value must accept it again: floats (including the sign of zero), ints, bools, strings, packed elements,
## a changed value type, a removed or added key and an array element. Skips (passes) without a verified library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var _checks := 0
var _failures := 0
var _covered := {}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60"]:
		var session: Node = Flight.new()
		session.input_enabled = true
		session.crash_auto_restart = false
		session.soft_hull_contacts = true
		session.setup_stage_backend(NativeStage.BACKEND_NATIVE)
		session.setup(str(Catalog.entry(id).data), id)
		session.set_field(field)
		session.set_lake_context(lake)
		session.reset()
		if session.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK5C_GUARD_LEAVES_SKIP %s: %s" % [id, str(session.stage_backend_status())])
			session.free()
			continue
		_check(id + " initial configuration matches", _matches(session))
		_walk(session, id, session.aircraft, [], 0)
		_check(id + " still matches after every restore", _matches(session))
		session.free()
	for kind: String in ["float", "zero_sign", "int", "bool", "string", "packed", "type", "erase", "add", "array"]:
		if not _covered.has(kind):
			print("NK5C_GUARD_LEAVES coverage missing: " + kind)
	print("native guard leaves: %d checks, %d failed, covered %s" % [_checks, _failures, str(_covered.keys())])
	quit(1 if _failures > 0 else 0)


func _matches(session: Node) -> bool:
	return session._native_stage.configuration_matches(session)


## Mutate the first few leaves of each kind found below depth 1 (inside the aircraft and its model).
func _walk(session: Node, id: String, value: Variant, path: Array, depth: int) -> void:
	if depth > 12:
		return
	if value is Dictionary:
		var dict: Dictionary = value
		if depth >= 1 and int(_covered.get("erase_" + id, 0)) < 2 and dict.size() > 1:
			var key: Variant = dict.keys()[dict.size() - 1]
			var saved: Variant = dict[key]
			dict.erase(key)
			_mutation(session, id, "erase", path + [key], func() -> void: dict[key] = saved)
		if depth >= 1 and int(_covered.get("add_" + id, 0)) < 2:
			dict["nk5c_probe"] = 1
			_mutation(session, id, "add", path + ["nk5c_probe"], func() -> void: dict.erase("nk5c_probe"))
		for key: Variant in dict.keys():
			_leaf(session, id, dict, key, path + [key], depth)
	elif value is Array:
		var array: Array = value
		for index: int in array.size():
			if array[index] is Dictionary or array[index] is Array:
				_walk(session, id, array[index], path + [index], depth + 1)
			elif int(_covered.get("array_" + id, 0)) < 2 and (array[index] is float or array[index] is int):
				var saved: Variant = array[index]
				array[index] = saved + 1
				_mutation(session, id, "array", path + [index], func() -> void: array[index] = saved)


func _leaf(session: Node, id: String, dict: Dictionary, key: Variant, path: Array, depth: int) -> void:
	var saved: Variant = dict[key]
	if saved is Dictionary or saved is Array:
		_walk(session, id, saved, path, depth + 1)
		return
	if depth < 1:
		return
	match typeof(saved):
		TYPE_FLOAT:
			if _take("float", id):
				dict[key] = saved + 0.5
				_mutation(session, id, "float", path, func() -> void: dict[key] = saved)
			if saved == 0.0 and _take("zero_sign", id):
				dict[key] = -saved if not is_nan(saved) else saved
				_mutation(session, id, "zero_sign", path, func() -> void: dict[key] = saved)
			if _take("type", id):
				dict[key] = int(saved) if is_finite(saved) else 0
				_mutation(session, id, "type", path, func() -> void: dict[key] = saved)
		TYPE_INT:
			if _take("int", id):
				dict[key] = saved + 1
				_mutation(session, id, "int", path, func() -> void: dict[key] = saved)
		TYPE_BOOL:
			if _take("bool", id):
				dict[key] = not saved
				_mutation(session, id, "bool", path, func() -> void: dict[key] = saved)
		TYPE_STRING:
			if _take("string", id):
				dict[key] = saved + "x"
				_mutation(session, id, "string", path, func() -> void: dict[key] = saved)
		TYPE_PACKED_FLOAT64_ARRAY:
			var packed: PackedFloat64Array = saved
			if not packed.is_empty() and _take("packed", id):
				var changed: PackedFloat64Array = packed.duplicate()
				changed[changed.size() - 1] = changed[changed.size() - 1] + 1.0
				dict[key] = changed
				_mutation(session, id, "packed", path, func() -> void: dict[key] = saved)


func _take(kind: String, id: String) -> bool:
	var count: int = int(_covered.get(kind + "_" + id, 0))
	if count >= 3:
		return false
	_covered[kind + "_" + id] = count + 1
	return true


func _mutation(session: Node, id: String, kind: String, path: Array, restore: Callable) -> void:
	_covered[kind] = true
	if not _covered.has(kind + "_" + id):
		_covered[kind + "_" + id] = 1
	elif kind in ["erase", "add", "array"]:
		_covered[kind + "_" + id] = int(_covered[kind + "_" + id]) + 1
	_check("%s %s %s refuses" % [id, kind, str(path)], not _matches(session))
	restore.call()
	_check("%s %s %s restored matches" % [id, kind, str(path)], _matches(session))


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + label)
