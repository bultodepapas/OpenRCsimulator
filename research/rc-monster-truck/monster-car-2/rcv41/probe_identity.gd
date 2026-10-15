## Compare content hashing and digest validation costs; no cached file contents.
extends SceneTree
const Dynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Nitro := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const PATHS := ["res://physics/ground_vehicle/nitro_dynamics.gd", "res://physics/ground_vehicle/vehicle_dynamics.gd"]
const CALLS := 200
var output := ""
var contents := {}
var hashes := {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty(): quit(1); return
	var variants := {"builtin_file_sha": _builtin, "buffered_sha": _buffered,
		"artifact_lookup": _artifact, "file_exists_only": _exists,
		"content_compare_sha": _content_compare}
	var measurements := {}
	var exact := true
	for path in PATHS:
		var digest := FileAccess.get_sha256(path)
		exact = exact and digest == _buffered(path) and digest == _content_compare(path)
		var cases := {}
		for name in variants:
			cases[name] = []
			for _warmup in 20: variants[name].call(path)
		for round_index in 5:
			var names: Array = variants.keys()
			if round_index % 2: names.reverse()
			for name in names:
				var started := Time.get_ticks_usec()
				for _index in CALLS: variants[name].call(path)
				cases[name].append(float(Time.get_ticks_usec() - started) / CALLS)
		measurements[path] = {"sha256": digest, "mean_us_by_round": cases}
	var digest := FileAccess.get_sha256(PATHS[0])
	var validators := {"script_loop": _old_valid, "native_hex": _native_valid}
	var validation := {}
	for name in validators:
		var started := Time.get_ticks_usec()
		for _index in 4000:
			exact = validators[name].call(digest) and exact
		validation[name] = float(Time.get_ticks_usec() - started) / 4000
	var started := Time.get_ticks_usec()
	for _index in CALLS: Nitro.backend_identity()
	var report := {"complete": exact, "engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(), "content_hashing": measurements,
		"validation_us": validation, "identity_us": float(Time.get_ticks_usec() - started) / CALLS,
		"harness_sha256": FileAccess.get_sha256(get_script().resource_path)}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print(JSON.stringify(report, "\t", true, true))
	quit(0 if exact else 1)

func _builtin(path: String) -> String: return FileAccess.get_sha256(path)
func _artifact(path: String) -> String: return Dynamics._reference_implementation_artifact(path).sha256
func _exists(path: String) -> bool: return FileAccess.file_exists(path)
func _content_compare(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if FileAccess.get_open_error() != OK: return ""
	if contents.has(path) and contents[path] == bytes: return hashes[path]
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK: return ""
	if not bytes.is_empty() and hash.update(bytes) != OK: return ""
	contents[path] = bytes
	hashes[path] = hash.finish().hex_encode()
	return hashes[path]
func _old_valid(value: String) -> bool: return Dynamics._sha256_is_valid(value)
func _native_valid(value: String) -> bool:
	return value.length() == 64 and value.to_lower() == value and value.is_valid_hex_number(false)

func _buffered(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK: return ""
	while file.get_position() < file.get_length():
		var expected := mini(262144, file.get_length() - file.get_position())
		var bytes := file.get_buffer(expected)
		if bytes.size() != expected or hash.update(bytes) != OK: return ""
	return hash.finish().hex_encode()
