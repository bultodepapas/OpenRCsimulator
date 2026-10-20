## DT-11a regression for the bounded GroundFeatures.patch CPU-buffer cache.
## Defaults to the production GroundFeatures script; --candidate=<path> optionally selects a draft.
## Budget cases use disposable source copies under user:// and refuse to overwrite existing files.
extends SceneTree

const MeshKit = preload("res://scenery/mesh_kit.gd")

var _candidate: Script
var _candidate_path := "res://scenery/ground_features.gd"
var _failures := 0
var _checks := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate="):
			_candidate_path = argument.trim_prefix("--candidate=")
	if _candidate_path.is_empty():
		push_error("Pass --candidate=<absolute path to ground_candidate.gd>")
		quit(2)
		return
	_candidate = load(_candidate_path) as Script
	if _candidate == null:
		push_error("Could not load patch-cache candidate: " + _candidate_path)
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_test_cold_warm_and_mutation_isolation()
	_test_full_key_dimensions()
	_test_fifo_and_accounting()
	_test_oversize_refusal()
	_test_byte_budget_eviction()
	print("patch cache regression: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_cold_warm_and_mutation_isolation() -> void:
	_reset_cache(_candidate)
	var poly := _small_poly()
	var xf := Transform3D.IDENTITY
	var key := _cache_key(poly, "gravel", "temperate", 17, xf)
	var expected := _oracle(_candidate, poly, "gravel", "temperate", 17, xf)
	_check("cache fixture produces patch vertices beyond its prefix", expected.verts.size() > _prefix_vertex_count())
	var cold := _make_kit(xf)
	_candidate.patch(cold, poly, "gravel", "temperate", 17)
	_check("cold miss matches uncached complete MeshKit bytes including prefix", _kit_bytes(cold) == _kit_bytes(expected))
	_check("cold miss stores its exact serialized key", _cache_contains(_candidate, key))
	_check_cache_accounting("single cold insertion")

	var keys_before_hit := _cache_keys(_candidate)
	var bytes_before_hit: int = _candidate._patch_cache_bytes
	var warm := _make_kit(xf)
	_candidate.patch(warm, poly, "gravel", "temperate", 17)
	_check("warm hit matches uncached complete MeshKit bytes including prefix", _kit_bytes(warm) == _kit_bytes(expected))
	_check("warm hit leaves FIFO order unchanged", _cache_keys(_candidate) == keys_before_hit)
	_check("warm hit leaves byte accounting unchanged", _candidate._patch_cache_bytes == bytes_before_hit)

	if warm.verts.size() > _prefix_vertex_count():
		var last := warm.verts.size() - 1
		warm.verts[last] = Vector3(123.0, -456.0, 789.0)
		warm.norms[last] = Vector3(0.25, 0.5, 0.75)
		warm.cols[last] = Color(0.91, 0.17, 0.63, 0.42)
	var after_mutation := _make_kit(xf)
	_candidate.patch(after_mutation, poly, "gravel", "temperate", 17)
	_check("mutating one returned hit cannot corrupt a later hit", _kit_bytes(after_mutation) == _kit_bytes(expected))
	_check_cache_accounting("post-mutation hit")


func _test_full_key_dimensions() -> void:
	var base_poly := _small_poly()
	var shifted_poly := base_poly.duplicate()
	shifted_poly[2] += Vector2(0.21, 0.13)
	var variants: Array[Dictionary] = [
		{label = "polygon", poly = shifted_poly, surface = "gravel", theme = "temperate", seed = 17, xf = Transform3D.IDENTITY},
		{label = "seed", poly = base_poly, surface = "gravel", theme = "temperate", seed = 18, xf = Transform3D.IDENTITY},
		{label = "surface", poly = base_poly, surface = "dirt", theme = "temperate", seed = 17, xf = Transform3D.IDENTITY},
		{label = "theme", poly = base_poly, surface = "gravel", theme = "summer", seed = 17, xf = Transform3D.IDENTITY},
		{label = "translated transform", poly = base_poly, surface = "gravel", theme = "temperate", seed = 17,
			xf = Transform3D(Basis.IDENTITY, Vector3(1.25, 0.3, -0.75))},
		{label = "mirrored transform", poly = base_poly, surface = "gravel", theme = "temperate", seed = 17,
			xf = Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3(0.4, 0.0, 0.8))},
		{label = "nonuniform scale transform", poly = base_poly, surface = "gravel", theme = "temperate", seed = 17,
			xf = Transform3D(Basis.from_scale(Vector3(1.35, 0.72, 0.61)), Vector3(-0.2, 0.1, 0.35))},
	]
	for variant: Dictionary in variants:
		_reset_cache(_candidate)
		var label: String = variant["label"]
		var poly: PackedVector2Array = variant["poly"]
		var surface: String = variant["surface"]
		var theme: String = variant["theme"]
		var seed: int = variant["seed"]
		var xf: Transform3D = variant["xf"]
		_check_cached_against_oracle("%s base" % label, _candidate, base_poly, "gravel", "temperate", 17, Transform3D.IDENTITY)
		_check_cached_against_oracle("%s changed input" % label, _candidate, poly, surface, theme, seed, xf)
		var base_key := _cache_key(base_poly, "gravel", "temperate", 17, Transform3D.IDENTITY)
		var changed_key := _cache_key(poly, surface, theme, seed, xf)
		_check("%s changes the serialized full key" % label, base_key != changed_key)
		_check("%s keeps separate base and changed entries" % label,
			_cache_contains(_candidate, base_key) and _cache_contains(_candidate, changed_key) and _candidate._patch_cache.size() == 2)
		_check_cache_accounting("%s variant" % label)


func _test_fifo_and_accounting() -> void:
	_reset_cache(_candidate)
	var poly := _small_poly()
	var xf := Transform3D.IDENTITY
	var limit: int = _candidate.PATCH_CACHE_MAX_ENTRIES
	_check("candidate declares the planned eight-entry and four-MiB limits",
		limit == 8 and _candidate.PATCH_CACHE_MAX_BYTES == 4 * 1024 * 1024)
	for index in limit:
		_check_cached_against_oracle("FIFO insertion %d" % index, _candidate, poly, "gravel", "temperate", 100 + index, xf)
	_check("cache fills to its entry limit", _candidate._patch_cache.size() == limit)
	var order_before_hit := _cache_keys(_candidate)
	_check_cached_against_oracle("hit on second FIFO entry", _candidate, poly, "gravel", "temperate", 101, xf)
	_check("a FIFO hit does not refresh insertion order", _cache_keys(_candidate) == order_before_hit)
	_check_cached_against_oracle("ninth FIFO insertion", _candidate, poly, "gravel", "temperate", 108, xf)
	var expected_order: Array[PackedByteArray] = []
	for seed in range(101, 109):
		expected_order.append(_cache_key(poly, "gravel", "temperate", seed, xf))
	_check("ninth insertion evicts the oldest entry and preserves FIFO order", _cache_keys(_candidate) == expected_order)
	_check_cache_accounting("ninth FIFO insertion")


func _test_oversize_refusal() -> void:
	var tiny_path := _write_candidate_copy_with_budget(1, "oversize")
	if tiny_path.is_empty():
		return
	var tiny := load(tiny_path) as Script
	if tiny == null:
		_check("load disposable one-byte-budget candidate", false)
		_remove_scratch(tiny_path)
		return

	_reset_cache(tiny)
	var poly := _small_poly()
	var xf := Transform3D.IDENTITY
	var expected := _oracle(_candidate, poly, "gravel", "temperate", 29, xf)
	var first_vertex := _prefix_vertex_count()
	var key := _cache_key(poly, "gravel", "temperate", 29, xf)
	var payload := var_to_bytes([
		expected.verts.slice(first_vertex), expected.norms.slice(first_vertex), expected.cols.slice(first_vertex),
	])
	var serialized_entry_bytes := key.size() + payload.size()
	var output := _make_kit(xf)
	tiny.patch(output, poly, "gravel", "temperate", 29)
	_check("small-budget copy still emits byte-identical geometry", _kit_bytes(output) == _kit_bytes(expected))
	_check("oversize fixture exceeds the copied cache budget", serialized_entry_bytes > tiny.PATCH_CACHE_MAX_BYTES)
	_check("oversize output is refused without storing partial cache state",
		tiny._patch_cache.is_empty() and tiny._patch_cache_bytes == 0)
	_remove_scratch(tiny_path)


func _test_byte_budget_eviction() -> void:
	var poly := _small_poly()
	var xf := Transform3D.IDENTITY
	var seed := 41
	var temperate := _oracle(_candidate, poly, "gravel", "temperate", seed, xf)
	var summer := _oracle(_candidate, poly, "gravel", "summer", seed, xf)
	_check("byte-budget fixtures keep identical geometry array lengths",
		temperate.verts.size() == summer.verts.size()
		and temperate.norms.size() == summer.norms.size()
		and temperate.cols.size() == summer.cols.size())
	var first_vertex := _prefix_vertex_count()
	var temperate_key := _cache_key(poly, "gravel", "temperate", seed, xf)
	var summer_key := _cache_key(poly, "gravel", "summer", seed, xf)
	var temperate_payload := var_to_bytes([
		temperate.verts.slice(first_vertex), temperate.norms.slice(first_vertex), temperate.cols.slice(first_vertex),
	])
	var summer_payload := var_to_bytes([
		summer.verts.slice(first_vertex), summer.norms.slice(first_vertex), summer.cols.slice(first_vertex),
	])
	var temperate_entry_bytes := temperate_key.size() + temperate_payload.size()
	var summer_entry_bytes := summer_key.size() + summer_payload.size()
	var budget := temperate_entry_bytes + 16
	_check("byte-budget fixtures each fit alone but exceed the budget together",
		temperate_entry_bytes <= budget and summer_entry_bytes <= budget
		and temperate_entry_bytes + summer_entry_bytes > budget)
	if not (temperate_entry_bytes <= budget and summer_entry_bytes <= budget
		and temperate_entry_bytes + summer_entry_bytes > budget):
		return
	var scratch_path := _write_candidate_copy_with_budget(budget, "byte_eviction")
	if scratch_path.is_empty():
		return
	var bounded := load(scratch_path) as Script
	if bounded == null:
		_check("load disposable measured-byte-budget candidate", false)
		_remove_scratch(scratch_path)
		return
	_reset_cache(bounded)
	var first_output := _make_kit(xf)
	bounded.patch(first_output, poly, "gravel", "temperate", seed)
	_check("first byte-budget insertion matches the uncached oracle", _kit_bytes(first_output) == _kit_bytes(temperate))
	_check("first patch occupies one cache entry", bounded._patch_cache.size() == 1)
	_check("first patch fits the measured byte budget", bounded._patch_cache_bytes == temperate_entry_bytes)

	var second_output := _make_kit(xf)
	bounded.patch(second_output, poly, "gravel", "summer", seed)
	_check("second theme output matches its uncached oracle", _kit_bytes(second_output) == _kit_bytes(summer))
	_check("byte pressure evicts FIFO below the eight-entry limit",
		bounded._patch_cache.size() == 1 and bounded._patch_cache.size() < bounded.PATCH_CACHE_MAX_ENTRIES
		and not _cache_contains(bounded, temperate_key) and _cache_contains(bounded, summer_key))
	_check("byte-budget eviction leaves exact bounded accounting",
		_cache_accounting_matches(bounded, bounded.PATCH_CACHE_MAX_ENTRIES, budget)
		and bounded._patch_cache_bytes == summer_entry_bytes)
	_remove_scratch(scratch_path)


func _write_candidate_copy_with_budget(budget: int, purpose: String) -> String:
	var source_file := FileAccess.open(_candidate_path, FileAccess.READ)
	if source_file == null:
		_check("open candidate source for disposable %s-budget copy" % purpose, false)
		return ""
	var source := source_file.get_as_text()
	source_file.close()
	var budget_declaration := "const PATCH_CACHE_MAX_BYTES := 4 * 1024 * 1024"
	if not source.contains(budget_declaration):
		_check("candidate has the expected cache-budget declaration for %s copy" % purpose, false)
		return ""
	var scratch_path := OS.get_user_data_dir().path_join("patch_cache_%s_%d_%d.gd" % [purpose, OS.get_process_id(), Time.get_ticks_usec()])
	if FileAccess.file_exists(scratch_path):
		_check("refuse to overwrite existing scratch candidate: " + scratch_path, false)
		return ""
	var scratch_file := FileAccess.open(scratch_path, FileAccess.WRITE)
	if scratch_file == null:
		_check("create disposable candidate for %s budget" % purpose, false)
		return ""
	scratch_file.store_string(source.replace(budget_declaration, "const PATCH_CACHE_MAX_BYTES := %d" % budget))
	scratch_file.close()
	return scratch_path


func _remove_scratch(path: String) -> void:
	if not path.is_empty():
		DirAccess.remove_absolute(path)


func _check_cached_against_oracle(label: String, script: Script, poly: PackedVector2Array, surface: String,
		theme: String, seed: int, xf: Transform3D) -> void:
	var expected := _oracle(script, poly, surface, theme, seed, xf)
	var actual := _make_kit(xf)
	script.patch(actual, poly, surface, theme, seed)
	_check("%s matches uncached complete MeshKit bytes" % label, _kit_bytes(actual) == _kit_bytes(expected))
	_check("%s stores its exact full input key" % label, _cache_contains(script, _cache_key(poly, surface, theme, seed, xf)))


func _oracle(script: Script, poly: PackedVector2Array, surface: String, theme: String, seed: int, xf: Transform3D) -> MeshKit:
	var kit := _make_kit(xf)
	script._patch_uncached(kit, poly, surface, theme, seed)
	return kit


func _make_kit(xf: Transform3D) -> MeshKit:
	var kit := MeshKit.new()
	kit.xf = xf
	_add_prefix(kit)
	return kit


func _add_prefix(kit: MeshKit) -> void:
	kit.tri(Vector3(-0.7, 0.11, -0.2), Vector3(0.2, 0.11, -0.4), Vector3(-0.1, 0.11, 0.8), Color(0.17, 0.31, 0.47, 0.83))


func _prefix_vertex_count() -> int:
	var kit := MeshKit.new()
	_add_prefix(kit)
	return kit.verts.size()


func _small_poly() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1.65, -1.2), Vector2(1.4, -1.15), Vector2(1.75, 0.95), Vector2(0.55, 1.45), Vector2(-1.35, 0.9),
	])


func _kit_bytes(kit: MeshKit) -> Array:
	return [kit.verts.to_byte_array(), kit.norms.to_byte_array(), kit.cols.to_byte_array(), var_to_bytes(kit.damage_ranges)]


func _cache_key(poly: PackedVector2Array, surface: String, theme: String, seed: int, xf: Transform3D) -> PackedByteArray:
	return var_to_bytes([poly, surface, theme, seed, xf])


func _cache_contains(script: Script, key: PackedByteArray) -> bool:
	for entry: Dictionary in script._patch_cache:
		if entry["key"] == key:
			return true
	return false


func _cache_keys(script: Script) -> Array[PackedByteArray]:
	var keys: Array[PackedByteArray] = []
	for entry: Dictionary in script._patch_cache:
		keys.append(entry["key"])
	return keys


func _reset_cache(script: Script) -> void:
	script._patch_cache.clear()
	script._patch_cache_bytes = 0


func _check_cache_accounting(label: String) -> void:
	_check("%s cache count and serialized-byte accounting remain bounded" % label,
		_cache_accounting_matches(_candidate, _candidate.PATCH_CACHE_MAX_ENTRIES, _candidate.PATCH_CACHE_MAX_BYTES))


func _cache_accounting_matches(script: Script, maximum_entries: int, maximum_bytes: int) -> bool:
	var accounted := 0
	for entry: Dictionary in script._patch_cache:
		var key: PackedByteArray = entry["key"]
		var payload: PackedByteArray = entry["payload"]
		accounted += key.size() + payload.size()
	return script._patch_cache.size() <= maximum_entries and script._patch_cache_bytes == accounted and accounted <= maximum_bytes


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + label)
