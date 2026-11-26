extends SceneTree
## NK-5c: the native configuration guard walks the prepared aircraft dictionary through primed per-leaf fast paths
## (the parent container captured once, String keys looked up as the equal StringName, expected scalars captured as
## raw values). Every in-place mutation of a nested leaf must still refuse the configuration, and restoring the
## original value must accept it again: floats (including the sign of zero), ints, bools, strings, packed elements,
## a changed value type, a removed or added key and an array element. Skips (passes) without a verified library.
## NK-5h: the guard's per-tick plan settles nested leaves with one engine deep equality per root against a preparation
## snapshot, keeping bitwise watches where that equality is weaker (zeros, Callables) and the identity of every container
## holding one. It must still refuse an in-place write through an alias into a packed array and the sign of a zero
## inside one. A nested container replaced by an equal copy is accepted only when it holds no zero or Callable (content
## is what the stage reads); a change inside the copy, including a zero's sign, refuses. A configured NaN keeps the full
## leaf walk.

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
		_check(id + " the per-tick plan is active", _plan_ready(session))
		_walk(session, id, session.aircraft, [], 0)
		_weather_leaves(session, id)
		_check(id + " still matches after every restore", _matches(session))
		session.free()
	_nan_fallback(field, lake)
	for kind: String in ["float", "zero_sign", "int", "bool", "string", "packed", "type", "erase", "add", "array",
			"packed_inplace", "packed_zero_sign", "container_copy", "container_copy_zero", "nan_fallback",
			"weather_float", "weather_zero_sign"]:
		if not _covered.has(kind):
			print("NK5C_GUARD_LEAVES coverage missing: " + kind)
	print("native guard leaves: %d checks, %d failed, covered %s" % [_checks, _failures, str(_covered.keys())])
	quit(1 if _failures > 0 else 0)


func _matches(session: Node) -> bool:
	return session._native_stage.configuration_matches(session)


func _plan_ready(session: Node) -> bool:
	return bool(session._native_stage._native.configuration_guard_plan_ready())


## NK-5h: the weather guard runs the same plan. In-place edits of the live weather configuration still refuse.
func _weather_leaves(session: Node, id: String) -> void:
	_check(id + " the weather guard plan is active", bool(session._native_stage._native.weather_guard_plan_ready()))
	var config: Variant = session._weather.get("_config")
	if not config is Dictionary:
		print("NK5H_WEATHER_SKIP %s: no _config dictionary" % id)
		return
	var nonzero: Array = _find_float(config, false)
	if not nonzero.is_empty():
		var holder: Variant = nonzero[0]
		var old: float = holder[nonzero[1]]
		holder[nonzero[1]] = old + 0.5
		_covered["weather_float"] = true
		_check(id + " an in-place weather float edit refuses", not _matches(session))
		holder[nonzero[1]] = old
		_check(id + " the restored weather matches", _matches(session))
	var zero: Array = _find_float(config, true)
	if not zero.is_empty():
		var holder: Variant = zero[0]
		var old: float = holder[zero[1]]
		holder[zero[1]] = -old
		_covered["weather_zero_sign"] = true
		_check(id + " an in-place weather zero sign flip refuses", not _matches(session))
		holder[zero[1]] = old
		_check(id + " the restored weather zero matches", _matches(session))


## [container, key or index] of a float leaf (a ±0 one when `zero`, else a nonzero one), or [].
func _find_float(value: Variant, zero: bool) -> Array:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if typeof(value[key]) == TYPE_FLOAT and (value[key] == 0.0) == zero:
				return [value, key]
		for key: Variant in (value as Dictionary).keys():
			var found := _find_float(value[key], zero)
			if not found.is_empty():
				return found
	elif value is Array:
		for index: int in (value as Array).size():
			if typeof(value[index]) == TYPE_FLOAT and (value[index] == 0.0) == zero:
				return [value, index]
			var found := _find_float(value[index], zero)
			if not found.is_empty():
				return found
	return []


## Replace a nested dictionary by an equal deep copy, then change values inside the copy.
func _container_copy(session: Node, id: String, dict: Dictionary, key: Variant, saved: Dictionary, path: Array) -> void:
	var copy: Dictionary = saved.duplicate(true)
	dict[key] = copy
	var retained := _holds_retained(saved)
	_covered["container_copy_zero" if not _find_zero(saved).is_empty() else "container_copy"] = true
	_check("%s an equal copy of %s %s" % [id, str(path), "refuses: it holds a zero or Callable" if retained else "matches"],
		_matches(session) != retained)
	# The NK-5h review counterexample: a zero's sign flipped inside an equal copy must refuse.
	var zero: Array = _find_zero(copy)
	if not zero.is_empty():
		var holder: Dictionary = zero[0]
		var old: float = holder[zero[1]]
		holder[zero[1]] = -old
		_check("%s a flipped zero inside the copy of %s refuses" % [id, str(path)], not _matches(session))
		holder[zero[1]] = old
	for inner: Variant in copy.keys():
		if typeof(copy[inner]) == TYPE_FLOAT and copy[inner] != 0.0:
			var old: float = copy[inner]
			copy[inner] = old + 0.25
			_check("%s a change inside the copy of %s refuses" % [id, str(path)], not _matches(session))
			copy[inner] = old
			break
	dict[key] = saved
	_check("%s the original %s matches again" % [id, str(path)], _matches(session))


## Whether a value holds a leaf the plan keeps a bitwise watch for: a ±0 float, a packed float array with a zero, a
## Callable.
func _holds_retained(value: Variant) -> bool:
	if value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			if _holds_retained(item):
				return true
		return false
	if value is Array:
		for item: Variant in value:
			if _holds_retained(item):
				return true
		return false
	match typeof(value):
		TYPE_FLOAT: return value == 0.0
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: return value.find(0.0) >= 0
		TYPE_CALLABLE: return true
	return false


## [dictionary, key] of a ±0 float somewhere inside `value`, or [].
func _find_zero(value: Variant) -> Array:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if typeof(value[key]) == TYPE_FLOAT and value[key] == 0.0:
				return [value, key]
		for key: Variant in (value as Dictionary).keys():
			var found := _find_zero(value[key])
			if not found.is_empty():
				return found
	elif value is Array:
		for item: Variant in value:
			var found := _find_zero(item)
			if not found.is_empty():
				return found
	return []


## A NaN anywhere in the guarded configuration keeps the full leaf walk, which still refuses a changed leaf.
func _nan_fallback(field: Dictionary, lake: Dictionary) -> void:
	var session: Node = Flight.new()
	session.input_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	session.setup(str(Catalog.entry("jensen-das-ugly-stik-60").data), "jensen-das-ugly-stik-60")
	session.set_field(field)
	session.set_lake_context(lake)
	session.aircraft["nk5h_nan"] = NAN
	session.reset()
	if session.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
		print("NK5H_NAN_FALLBACK_SKIP: %s" % str(session.stage_backend_status()))
		session.free()
		return
	_covered["nan_fallback"] = true
	_check("a configured NaN keeps the full leaf walk", not _plan_ready(session) and _matches(session))
	var model: Dictionary = session.aircraft.model
	var mass: Variant = model.get("mass")
	if typeof(mass) == TYPE_FLOAT:
		model["mass"] = mass + 0.5
		_check("the full walk still refuses a changed leaf", not _matches(session))
		model["mass"] = mass
		_check("and accepts it restored", _matches(session))
	session.free()


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
			elif int(_covered.get("array_" + id, 0)) < 2 and array[index] is String:
				var saved: String = array[index]
				array[index] = saved + "x"
				_mutation(session, id, "array", path + [index], func() -> void: array[index] = saved)


func _leaf(session: Node, id: String, dict: Dictionary, key: Variant, path: Array, depth: int) -> void:
	var saved: Variant = dict[key]
	if saved is Dictionary and depth >= 1 and _plan_ready(session):
		var zero: Array = _find_zero(saved)
		if (not zero.is_empty() and _take("container_copy_zero", id)) or (zero.is_empty() and _take("container_copy", id)):
			_container_copy(session, id, dict, key, saved, path)
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
			# An in-place write through an alias: the snapshot must hold its own buffer.
			if not packed.is_empty() and _take("packed_inplace", id):
				var alias: PackedFloat64Array = dict[key]
				var old: float = alias[0]
				alias[0] = old + 1.0
				if (dict[key] as PackedFloat64Array)[0] == old + 1.0:
					_mutation(session, id, "packed_inplace", path, func() -> void: alias[0] = old)
				else:
					alias[0] = old
			var zero_at: int = packed.find(0.0)
			if zero_at >= 0 and _take("packed_zero_sign", id):
				var flipped: PackedFloat64Array = packed.duplicate()
				flipped[zero_at] = -flipped[zero_at]
				dict[key] = flipped
				_mutation(session, id, "packed_zero_sign", path, func() -> void: dict[key] = saved)


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
