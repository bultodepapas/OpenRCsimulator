## DT-11a / L6b: complete field validation/loading with exact normalized-data and diagnostic parity.
extends SceneTree

var reference: GDScript
var candidate: GDScript
var data_path := ""
var no_trees_path := ""
var output := ""
var candidate_first := false
var failed := false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference = load(arg.trim_prefix("--reference=")) as GDScript
		elif arg.begins_with("--candidate="): candidate = load(arg.trim_prefix("--candidate=")) as GDScript
		elif arg.begins_with("--data="): data_path = arg.trim_prefix("--data=")
		elif arg.begins_with("--no-trees-data="): no_trees_path = arg.trim_prefix("--no-trees-data=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--candidate-first": candidate_first = true
		else: failed = true
	if failed or reference == null or candidate == null or data_path.is_empty() or no_trees_path.is_empty() \
		or output.is_empty() or FileAccess.file_exists(output):
		printerr("expected --reference=<source> --candidate=<source> --data=<json> --no-trees-data=<json> --output=<new file> [--candidate-first]")
		quit(2)
		return
	if FileAccess.get_sha256(reference.resource_path) == FileAccess.get_sha256(candidate.resource_path):
		printerr("reference and candidate must have distinct source content")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	var no_trees: Variant = JSON.parse_string(FileAccess.get_file_as_string(no_trees_path))
	if not parsed is Dictionary or not no_trees is Dictionary:
		quit(2)
		return
	if not parsed.get("objects") is Array or parsed.objects.size() != 1 or not parsed.objects[0] is Dictionary \
		or not no_trees.get("objects") is Array or not no_trees.objects.is_empty():
		printerr("expected one default treeline and an empty-object control")
		quit(2)
		return
	var quantity: Variant = parsed.objects[0].get("positions")
	if not quantity is Dictionary or not quantity.get("value") is Array or quantity.value.size() != 1680:
		printerr("expected the 1,680-row default treeline")
		quit(2)
		return
	_run(parsed, no_trees)


func _run(raw: Dictionary, no_trees: Dictionary) -> void:
	var identities_before := _identities()
	var parity: Array = []
	var fixtures: Array = [{id = "default-1680", data = raw, accepted = true},
		{id = "no-trees", data = no_trees, accepted = true},
		{id = "mixed-numeric-signs", data = _with_points(raw, [[300, 25.0, 0], [-300.0, 25, -0.0], [300.0, -25.0, 0.0]]), accepted = true},
		{id = "same-cell-tolerance", data = _with_points(raw, [[300.0, 0.0, 0.0], [300.0000001, 0.0, 0.0], [299.9999999, 0.0, 0.0]]), accepted = false},
		{id = "off-grid-before-valid-duplicate", data = _with_points(raw, [[300.125, 0.0, 0.0], [300.25, 0.0, 0.0]]), accepted = false},
		{id = "negative-half-grid-tie", data = _with_points(raw, [[-300.125, 0.0, 0.0], [-300.25, 0.0, 0.0]]), accepted = false},
		{id = "nonflat-does-not-enter-key-set", data = _with_points(raw, [[300.0, 0.0, 0.25], [300.0, 0.0, 0.0], [300.0, 0.0, 0.0]]), accepted = false},
		{id = "large-finite-radius", data = _with_points(raw, [[1e100, 0.0, 0.0], [-1e100, 0.0, 0.0]]), accepted = false},
		{id = "radius-and-grid-boundaries", data = _with_points(raw, [[1500.0, 0.0, 0.0], [-1500.0, 0.0, 0.0], [1500.25, 0.0, 0.0], [-1500.25, 0.0, 0.0]]), accepted = false},
		{id = "malformed-and-nonfinite", data = _with_points(raw, [null, [1, 2], ["bad", 0.0, 0.0], [NAN, 0.0, 0.0], [INF, 0.0, 0.0], [300.0, 0.125, 0.25]]), accepted = false}]
	var duplicate := raw.duplicate(true)
	var first: Array = duplicate.objects[0].positions.value[0]
	duplicate.objects[0].positions.value[-1] = first.duplicate()
	fixtures.append({id = "duplicate-final-default-row", data = duplicate, accepted = false})
	for fixture: Dictionary in fixtures:
		var before := var_to_bytes(fixture.data)
		var a: Dictionary = reference.validate(fixture.data)
		var b: Dictionary = candidate.validate(fixture.data)
		var equal := var_to_bytes(a) == var_to_bytes(b)
		var unchanged := before == var_to_bytes(fixture.data)
		if not equal or not unchanged or bool(a.ok) != bool(fixture.accepted): failed = true
		parity.append({id = fixture.id, equal = equal, source_unchanged = unchanged, ok = a.ok,
			errors = a.errors, result_sha256 = _hash(var_to_bytes(a))})
	var workloads: Array = []
	for fixture: Dictionary in [{id = "default", data = raw, path = data_path, batch = 8},
		{id = "no-trees-control", data = no_trees, path = no_trees_path, batch = 32}]:
		var before := var_to_bytes(fixture.data)
		for method: String in ["validate", "load_from"]:
			var item := {id = str(fixture.id) + ":" + method, batch = fixture.batch,
				reference_batch_usec = [], candidate_batch_usec = [], pairs = []}
			var argument: Variant = fixture.data if method == "validate" else fixture.path
			var expected := var_to_bytes(reference.call(method, argument))
			# Symmetric warmup is outside every timed batch.
			for warmup: int in 40:
				for script: GDScript in _order(warmup):
					script.call(method, argument)
			for pair: int in 12:
				var made: Dictionary = {}
				for script: GDScript in _order(pair):
					var result: Dictionary
					var started := Time.get_ticks_usec()
					for repeat: int in fixture.batch:
						result = script.call(method, argument)
					var elapsed := Time.get_ticks_usec() - started
					var key := "reference" if script == reference else "candidate"
					item[key + "_batch_usec"].append(elapsed)
					made[key] = result
				var equal := var_to_bytes(made.reference) == expected and var_to_bytes(made.candidate) == expected
				if not equal: failed = true
				item.pairs.append({equal = equal, result_sha256 = _hash(expected)})
			item["source_unchanged"] = before == var_to_bytes(fixture.data)
			if not item.source_unchanged: failed = true
			workloads.append(item)
	var inputs_unchanged := identities_before == _identities()
	if not inputs_unchanged: failed = true
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({complete = not failed, engine = Engine.get_version_info(),
		candidate_first = candidate_first, machine = {processor = OS.get_processor_name(), os = OS.get_name(),
			architecture = Engine.get_architecture_name(), debug_build = OS.is_debug_build()},
		reference_sha256 = FileAccess.get_sha256(reference.resource_path),
		candidate_sha256 = FileAccess.get_sha256(candidate.resource_path),
		data_sha256 = FileAccess.get_sha256(data_path), no_trees_sha256 = FileAccess.get_sha256(no_trees_path),
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path), identities_before = identities_before,
		inputs_unchanged = inputs_unchanged, parity = parity, workloads = workloads}, "\t"))
	file.close()
	print("field validation probe ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _with_points(raw: Dictionary, points: Array) -> Dictionary:
	var fixture := raw.duplicate(true)
	fixture.objects[0].positions.value = points
	return fixture


func _order(pair: int) -> Array[GDScript]:
	return [candidate, reference] if (pair % 2 == 0) == candidate_first else [reference, candidate]


func _identities() -> Dictionary:
	return {reference = FileAccess.get_sha256(reference.resource_path), candidate = FileAccess.get_sha256(candidate.resource_path),
		data = FileAccess.get_sha256(data_path), no_trees = FileAccess.get_sha256(no_trees_path), probe = FileAccess.get_sha256(get_script().resource_path)}


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
