## Real extension test: no automatic route is qualified by this harness alone.
## Run through tools/godot/run_checked.py with --path app and --extension=<descriptor>.
extends SceneTree

const Domain := preload("res://sim/native_macos_domain.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const STOCK_GUARD_CALLS := 2400
const STOCK_GUARD_WARMUP := 16

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
	else:
		_check(changed, kind + ": alias actually mutates its live packed leaf")
	_check(_native.macos_domain_guard_matches(world, field) == (not changed),
		kind + ": packed alias change is detected when the live leaf changes")


func _assert_resize(kind: String) -> void:
	var world := _frozen({bins = {cell = {
		"byte": PackedByteArray([1, 2]), "int32": PackedInt32Array([1, 2]),
		"int64": PackedInt64Array([1, 2]), "float32": PackedFloat32Array([1.0, 2.0]),
		"float64": PackedFloat64Array([1.0, 2.0])}}})
	var field := _frozen({id = "default"})
	var before: PackedByteArray = var_to_bytes(world.bins.cell[kind])
	_check(_prepare(world, field), kind + ": resize fixture prepares")
	var resized := false
	match kind:
		"byte":
			var byte_alias: PackedByteArray = world.bins.cell[kind]
			resized = byte_alias.resize(1024) == OK and byte_alias.size() == 1024
		"int32":
			var int32_alias: PackedInt32Array = world.bins.cell[kind]
			resized = int32_alias.resize(1024) == OK and int32_alias.size() == 1024
		"int64":
			var int64_alias: PackedInt64Array = world.bins.cell[kind]
			resized = int64_alias.resize(1024) == OK and int64_alias.size() == 1024
		"float32":
			var float32_alias: PackedFloat32Array = world.bins.cell[kind]
			resized = float32_alias.resize(1024) == OK and float32_alias.size() == 1024
		"float64":
			var float64_alias: PackedFloat64Array = world.bins.cell[kind]
			resized = float64_alias.resize(1024) == OK and float64_alias.size() == 1024
	var live_changed: bool = var_to_bytes(world.bins.cell[kind]) != before
	_check(resized, kind + ": alias resize completes")
	_check(_native.macos_domain_guard_matches(world, field) == (not live_changed),
		kind + ": resize is detected whenever it changes the live leaf")
	print("MACOS_DOMAIN_RESIZE ", JSON.stringify({kind = kind, alias_resized = resized, live_changed = live_changed}))


func _assert_reassignment_and_existing_alias() -> void:
	var world := _frozen({bins = {cell = PackedInt64Array([3, 7])}})
	var field := _frozen({id = "default"})
	var existing: PackedInt64Array = world.bins.cell
	_check(_prepare(world, field), "preexisting alias fixture prepares")
	var detached: PackedInt64Array = existing
	detached = PackedInt64Array([8, 9, 10])
	_check(world.bins.cell == PackedInt64Array([3, 7]) and _native.macos_domain_guard_matches(world, field),
		"reassigning a local alias leaves the frozen leaf and guard unchanged")
	existing[0] = 11
	_check(world.bins.cell[0] == 11, "alias retained before prepare actually mutates the live leaf")
	_check(not _native.macos_domain_guard_matches(world, field), "mutation via preexisting alias is detected")


func _assert_direct_resize() -> void:
	var world := _frozen({bins = {cell = PackedInt64Array([3, 7])}})
	var field := _frozen({id = "default"})
	_check(_prepare(world, field), "direct resize fixture prepares")
	var result: int = world.bins.cell.resize(1024)
	var live_changed: bool = world.bins.cell.size() != 2
	_check(result == OK, "direct nested packed resize succeeds")
	_check(_native.macos_domain_guard_matches(world, field) == (not live_changed),
		"direct resize is detected whenever it changes the live leaf")
	print("MACOS_DOMAIN_DIRECT_RESIZE ", JSON.stringify({live_changed = live_changed, size = world.bins.cell.size()}))
	if live_changed:
		world.bins.cell.resize(2)
		_check(world.bins.cell == PackedInt64Array([3, 7]) and _native.macos_domain_guard_matches(world, field),
			"restoring directly resized leaf restores guard")


func _assert_refused(world: Dictionary, field: Dictionary, label: String) -> void:
	_check(not _prepare(world, field), label + ": refused")
	_check(not _native.macos_domain_guard_matches(world, field), label + ": disarmed")


func _check_stock_world() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check(loaded.get("ok", false), "stock field loads")
	if not loaded.get("ok", false): return
	var built: Dictionary = CollisionSetup.build(loaded.field)
	_check(built.get("ok", false), "stock collision world builds")
	if not built.get("ok", false): return
	var world: Dictionary = _frozen(built.world)
	var field: Dictionary = _frozen(loaded.field)
	_check(not world.is_empty() and not field.is_empty() and world.is_read_only() and field.is_read_only(),
		"stock world and field are detached and frozen")
	if world.is_empty() or field.is_empty(): return
	_check(world.get("identity") == Domain.STOCK_WORLD and world.get("proxies", []).size() == Domain.STOCK_WORLD_PROXIES,
		"stock collision identity and proxy count match the screened world")
	var prepared: Dictionary = _native.prepare_macos_domain_guard(world, field)
	var ready: bool = prepared.get("ok", false) and _native.macos_domain_guard_matches(world, field)
	var statistics_valid: bool = int(prepared.get("nodes", 0)) > 0 and int(prepared.get("packed_leaves", 0)) > 0 \
		and int(prepared.get("packed_bytes", 0)) > 0
	_check(ready and statistics_valid, "stock frozen context prepares a native packed guard")
	if not ready or not statistics_valid:
		print("MACOS_DOMAIN_STOCK_GUARD_PREPARE ", JSON.stringify(prepared))
		return
	var matches := true
	for _index: int in STOCK_GUARD_WARMUP:
		matches = bool(_native.macos_domain_guard_matches(world, field)) and matches
	var started: int = Time.get_ticks_usec()
	for _index: int in STOCK_GUARD_CALLS:
		matches = bool(_native.macos_domain_guard_matches(world, field)) and matches
	var elapsed: int = Time.get_ticks_usec() - started
	_check(matches and elapsed >= 0, "every bounded stock guard call matches")
	print("MACOS_DOMAIN_STOCK_GUARD_DIAGNOSTIC ", JSON.stringify({
		scope = "isolated guard-call loop only; not inclusive tick or product performance",
		world_identity = world.identity, proxies = world.proxies.size(), warmup_calls = STOCK_GUARD_WARMUP,
		calls = STOCK_GUARD_CALLS, elapsed_usec = elapsed, mean_usec = float(elapsed) / STOCK_GUARD_CALLS,
		all_match = matches,
		nodes = prepared.nodes, packed_leaves = prepared.packed_leaves, packed_bytes = prepared.packed_bytes,
		cpu = OS.get_processor_name(), model = OS.get_model_name(),
	}))
	var selected := ""
	for key: Variant in world.bins:
		if world.bins[key] is PackedInt64Array and not world.bins[key].is_empty():
			selected = str(key)
			break
	_check(not selected.is_empty(), "stock world has a mutable packed-bin alias to test")
	if selected.is_empty(): return
	var original: int = world.bins[selected][0]
	var alias: PackedInt64Array = world.bins[selected]
	alias[0] = original + 1
	_check(world.bins[selected][0] == original + 1, "stock packed alias actually mutates the live frozen world")
	_check(not _native.macos_domain_guard_matches(world, field), "stock packed mutation is detected")
	alias[0] = original
	_check(world.bins[selected][0] == original and _native.macos_domain_guard_matches(world, field),
		"restoring stock packed bytes restores the guard")


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
	for kind: String in ["byte", "int32", "int64", "float32", "float64"]:
		_assert_resize(kind)
	_assert_reassignment_and_existing_alias()
	_assert_direct_resize()

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
	_check_stock_world()

	if _failures.is_empty():
		print("MACOS_DOMAIN_GUARD verdict=pass checks=", _checks)
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL ", failure)
		print("MACOS_DOMAIN_GUARD verdict=fail checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)
