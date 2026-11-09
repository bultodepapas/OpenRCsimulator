extends SceneTree

const Config := preload("res://scenarios/scenario_config.gd")
const NaturalRandom := preload("res://scenarios/natural_random.gd")
const Field := preload("res://data/field_loader.gd")
const AIRCRAFT := "jensen-das-ugly-stik-60"

var _checks := 0
var _failures := 0
var _paths: Array[String] = []


func _initialize() -> void:
	var original := FileAccess.get_file_as_string(Field.DEFAULT_PATH)
	var changed := original.replace('"id": "default"', '"id": "changed"')
	_check("mutation changes content without changing byte length", original != changed
		and original.to_utf8_buffer().size() == changed.to_utf8_buffer().size())
	var path := _fixture(0, original)
	_test_exact_content(path, original, changed)
	_test_launch_gate(path, original, changed)
	_test_ownership_and_failures(path, original)
	_test_bounds_and_bypass(original)
	Config.clear_source_cache()
	_check("explicit clearing releases all optional cache entries", Config._source_cache.is_empty())
	for fixture_path in _paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("Natural Random source cache: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_exact_content(path: String, original: String, changed: String) -> void:
	Config.clear_source_cache()
	# Prime aircraft validation before the write pair. Timestamp equality is diagnostic:
	# a slow filesystem crossing its timestamp quantum must not fail a correct cache.
	Config.resolve_source_identities(AIRCRAFT)
	_write(path, original)
	var modified := FileAccess.get_modified_time(path)
	var first: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
	_write(path, changed)
	print("same-size source edit retained timestamp: ", modified == FileAccess.get_modified_time(path))
	var second: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
	var exact: Dictionary = Config.resolve_source_identities(AIRCRAFT, path, false)
	_check("same-size edit returns its new exact identity", first.ok and second.ok and exact.ok
		and first.source.field_identity != second.source.field_identity and second.source == exact.source
		and second.source.field_id == "changed")
	_check("revisions replace their source slot", Config._source_cache.size() == 3)
	_write(path, original)
	var reverted: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
	_check("reverting source bytes restores the original identity", reverted.ok and reverted.source == first.source
		and Config._source_cache.size() == 3)


func _test_launch_gate(path: String, original: String, changed: String) -> void:
	_write(path, original)
	var generated: Dictionary = NaturalRandom.generate(0)
	_check("unchanged copied sources pass launch validation", generated.ok
		and Config.validate_sources(generated.scenario, path).ok)
	if not generated.ok:
		return
	Config.resolve_source_identities(AIRCRAFT, path)
	_write(path, changed)
	_check("uncached launch validation refuses a changed field", not Config.validate_sources(generated.scenario, path).ok)
	_write(path, original)


func _test_ownership_and_failures(path: String, original: String) -> void:
	Config.clear_source_cache()
	var first: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
	_check("valid field populates compact source entries", first.ok and Config._source_cache.size() == 2)
	if not first.ok:
		return
	var expected: Dictionary = first.source.duplicate(true)
	first.source.field_id = "caller mutation"
	first.source.aircraft_identity = "bad"
	var again: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
	_check("callers cannot mutate cached source identities", again.ok and again.source == expected)
	var full: Dictionary = Config.load_field_source(path)
	full.field.id = "caller mutation"
	_check("public field loading still returns a detached complete field", full.ok and full.field.has("surfaces")
		and Config.load_field_source(path).field.id == "default")
	for invalid in ["", "{invalid json", original.replace('"openrc-field v1"', '"invalid-field-v1"')]:
		_write(path, invalid)
		var cached: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
		var uncached: Dictionary = Config.resolve_source_identities(AIRCRAFT, path, false)
		_check("invalid source refuses equally with and without cache", not cached.ok and not uncached.ok
			and cached.source.is_empty() and cached.errors == uncached.errors)
	_write(path, original)
	_check("a corrected source recovers after failure", Config.resolve_source_identities(AIRCRAFT, path).ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check("a missing file cannot use the previous cached identity", not Config.resolve_source_identities(AIRCRAFT, path).ok)
	_write(path, original)
	_check("empty path retains its explicit refusal", Config.resolve_source_identities(AIRCRAFT, "").errors
		== PackedStringArray(["field path is empty"]))


func _test_bounds_and_bypass(original: String) -> void:
	Config.clear_source_cache()
	for index in 20:
		var path := _fixture(index + 1, original)
		var loaded: Dictionary = Config.resolve_source_identities(AIRCRAFT, path)
		_check("distinct source %d resolves inside the entry bound" % index, loaded.ok
			and Config._source_cache.size() <= Config.SOURCE_CACHE_MAX_ENTRIES)
	var oldest_key := "field|" + ProjectSettings.globalize_path(_paths[1]).sha256_text()
	var newest_key := "field|" + ProjectSettings.globalize_path(_paths[-1]).sha256_text()
	_check("LRU evicts old paths and retains the latest field", Config._source_cache.size() == Config.SOURCE_CACHE_MAX_ENTRIES
		and not Config._source_cache.has(oldest_key) and Config._source_cache.has(newest_key))
	var compact := true
	for entry: Dictionary in Config._source_cache.values():
		compact = compact and not entry.source.has("field") and not entry.source.has("model") \
			and var_to_bytes(entry).size() <= Config.SOURCE_CACHE_MAX_ENTRY_BYTES
	_check("cache retains only bounded compact identity records", compact)
	var before := var_to_bytes(Config._source_cache)
	var uncached_path := _fixture(22, original)
	var uncached: Dictionary = Config.resolve_source_identities(AIRCRAFT, uncached_path, false)
	_check("uncached validation neither populates nor reorders the cache", uncached.ok
		and var_to_bytes(Config._source_cache) == before)
	# A hit must protect the older source from eviction, rather than behaving as FIFO.
	var recent_path := _paths[6]
	var recent_key := "field|" + ProjectSettings.globalize_path(recent_path).sha256_text()
	_check("older resident can be reused", Config._source_cache.has(recent_key)
		and Config.resolve_source_identities(AIRCRAFT, recent_path).ok)
	var next_oldest_key := "field|" + ProjectSettings.globalize_path(_paths[7]).sha256_text()
	Config.resolve_source_identities(AIRCRAFT, _fixture(23, original))
	_check("a cache hit updates eviction recency", Config._source_cache.has(recent_key)
		and not Config._source_cache.has(next_oldest_key))
	var oversized := original.replace('"id": "default"', '"id": "%s"' % "x".repeat(5000))
	var oversized_path := _fixture(24, oversized)
	var cached: Dictionary = Config.resolve_source_identities(AIRCRAFT, oversized_path)
	var exact: Dictionary = Config.resolve_source_identities(AIRCRAFT, oversized_path, false)
	var oversized_key := "field|" + ProjectSettings.globalize_path(oversized_path).sha256_text()
	_check("oversized valid identity bypasses retention with unchanged results", cached.ok and exact.ok
		and cached.source == exact.source and cached.source.field_id.length() == 5000
		and not Config._source_cache.has(oversized_key))


func _fixture(index: int, content: String) -> String:
	var path := "user://natural-source-cache-%d-%d.json" % [OS.get_process_id(), index]
	_paths.append(path)
	_write(path, content)
	return path


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("disposable source is writable", false)
		return
	file.store_string(content)
	file.close()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		print("FAIL ", label)
