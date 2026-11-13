## Real extension test: no automatic route is qualified by this harness alone.
## Run through tools/godot/run_checked.py with --path app and --extension=<descriptor>.
extends SceneTree

const Domain := preload("res://sim/native_macos_domain.gd")

var _native: Object
var _checks := 0
var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _prepare(world: Dictionary, field: Dictionary) -> bool:
	return bool(_native.prepare_macos_domain_guard(world, field).get("ok", false))


func _frozen(value: Dictionary) -> Dictionary:
	return Domain._detached_read_only(value)


func _assert_alias(kind: String, replacement: Variant) -> void:
	var world := _frozen({bins = {cell = {
		"byte": PackedByteArray([1, 2]), "int32": PackedInt32Array([1, 2]),
		"int64": PackedInt64Array([1, 2]), "float32": PackedFloat32Array([1.0, 2.0]),
		"float64": PackedFloat64Array([1.0, 2.0])}}})
	var field := _frozen({id = "default"})
	_check(_prepare(world, field), kind + ": prepare")
	_check(_native.macos_domain_guard_matches(world, field), kind + ": initial match")
	match kind:
		"byte":
			var byte_alias: PackedByteArray = world.bins.cell[kind]
			byte_alias[0] = int(replacement)
		"int32":
			var int32_alias: PackedInt32Array = world.bins.cell[kind]
			int32_alias[0] = int(replacement)
		"int64":
			var int64_alias: PackedInt64Array = world.bins.cell[kind]
			int64_alias[0] = int(replacement)
		"float32":
			var float32_alias: PackedFloat32Array = world.bins.cell[kind]
			float32_alias[0] = float(replacement)
		"float64":
			var float64_alias: PackedFloat64Array = world.bins.cell[kind]
			float64_alias[0] = float(replacement)
	var changed: bool = world.bins.cell[kind][0] == replacement
	if kind == "int64":
		# This is the actual M1 failure: prove the test reaches a shared in-place write.
		_check(changed, "int64 alias mutates a packed leaf inside the frozen dictionary")
	_check(_native.macos_domain_guard_matches(world, field) == (not changed),
		kind + ": packed alias change is detected when the live leaf changes")


func _assert_refused(world: Dictionary, field: Dictionary, label: String) -> void:
	_check(not _prepare(world, field), label + ": refused")
	_check(not _native.macos_domain_guard_matches(world, field), label + ": disarmed")


func _run() -> void:
	var extension := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--extension="):
			extension = argument.trim_prefix("--extension=")
	if extension.is_empty():
		printerr("FAIL native extension path is required")
		quit(1)
		return
	var status: int = OK if GDExtensionManager.is_extension_loaded(extension) \
		else GDExtensionManager.load_extension(extension)
	if status != OK or not ClassDB.class_exists("OpenRCNativeKernel"):
		printerr("FAIL cannot load native domain guard: ", status)
		quit(1)
		return
	_native = ClassDB.instantiate("OpenRCNativeKernel")
	if _native == null or not _native.has_method("prepare_macos_domain_guard") \
			or not _native.has_method("macos_domain_guard_matches"):
		printerr("FAIL native domain guard methods missing")
		quit(1)
		return
	for case: Array in [["byte", 9], ["int32", 9], ["int64", 9], ["float32", 9.0], ["float64", 9.0]]:
		_assert_alias(case[0], case[1])

	var world := _frozen({nested = [PackedInt64Array([3, 7])], bins = {cell = PackedInt64Array([4, 8])}})
	var field := _frozen({nested = {value = PackedFloat64Array([2.0])}})
	var prepared: Dictionary = _native.prepare_macos_domain_guard(world, field)
	_check(prepared.get("ok", false) and prepared.get("packed_leaves", 0) == 3 \
		and prepared.get("packed_bytes", 0) == 40, "dictionary and array leaves counted")
	_check(_native.macos_domain_guard_matches(world, field), "independent context matches")
	_check(not _native.macos_domain_guard_matches(world.duplicate(true), field), "equal replacement world refused")
	_check(not _native.macos_domain_guard_matches(world, field.duplicate(true)), "equal replacement field refused")
	var array_alias: PackedInt64Array = world.nested[0]
	array_alias[1] = 19
	var array_changed: bool = world.nested[0][1] == 19
	_check(_native.macos_domain_guard_matches(world, field) == (not array_changed),
		"packed mutation through array parent detected if shared")
	_check(_prepare(world, field) and _native.macos_domain_guard_matches(world, field), "fresh capture matches current values")
	var field_alias: PackedFloat64Array = field.nested.value
	field_alias[0] = 11.0
	var field_changed: bool = field.nested.value[0] == 11.0
	_check(_native.macos_domain_guard_matches(world, field) == (not field_changed),
		"packed mutation in field detected if shared")

	_assert_refused({plain = 1}, field, "mutable root")
	var mutable_child := {value = 1}
	var frozen_parent := {nested = mutable_child}
	frozen_parent.make_read_only()
	_assert_refused(frozen_parent, field, "mutable dictionary child")
	var mutable_array := [1]
	frozen_parent = {nested = mutable_array}
	frozen_parent.make_read_only()
	_assert_refused(frozen_parent, field, "mutable array child")
	_assert_refused(_frozen({unsupported = PackedStringArray(["a"])}), field, "unsupported packed type")
	var unknown := RefCounted.new()
	var object_parent := {unsupported = unknown}
	object_parent.make_read_only()
	_assert_refused(object_parent, field, "unsupported object")
	var deep: Variant = 1
	for i: int in range(40):
		var parent: Array = [deep]
		parent.make_read_only()
		deep = parent
	var deep_root := {nested = deep}
	deep_root.make_read_only()
	_assert_refused(deep_root, field, "depth bound")

	if _failures.is_empty():
		print("MACOS_DOMAIN_GUARD verdict=pass checks=", _checks)
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL ", failure)
		print("MACOS_DOMAIN_GUARD verdict=fail checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)
