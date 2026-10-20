## LU-10-R1: paired complete scenery-query costs; no rendering or frame-rate claim.
extends SceneTree

const World := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const Aircraft := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _reference: GDScript
var _candidate: GDScript = Collision
var _output := ""
var _failed := false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="):
			_reference = load(arg.trim_prefix("--reference=")) as GDScript
		elif arg.begins_with("--candidate="):
			_candidate = load(arg.trim_prefix("--candidate=")) as GDScript
		elif arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		else:
			_failed = true
	if _failed or _reference == null or _candidate == null or _output.is_empty() or FileAccess.file_exists(_output):
		printerr("expected --reference=<source> [--candidate=<source>] --output=<new file>")
		quit(2)
		return
	var built: Dictionary = World.build({pilot = {}, objects = []}, {groups = []},
		{fixtures = [{id = "probe", type = "flood", north = 16.0, east = 16.0, height = 8.0}]})
	var loaded: Dictionary = Aircraft.load_file(Scenarios.AIRCRAFT)
	if not built.ok or not loaded.ok:
		printerr("fixture setup failed")
		quit(1)
		return
	var cases := [
		_case("empty_bin", 1000.0, 1000.0, 1000.33, 1000.0, 0.0),
		_case("occupied_bin_clear", 4.0, 4.0, 4.33, 4.0, 0.0),
		_case("occupied_bin_small_rotation", 4.0, 4.0, 4.33, 4.0, 0.02),
		_case("occupied_bin_rotating_clear", 4.0, 4.0, 4.33, 4.0, PI),
		_case("cell_boundary_clear", 31.9, 4.0, 32.2, 4.0, 0.15),
		_case("true_contact", 12.0, 16.0, 20.0, 16.0, 0.0),
		_case("rotating_contact", 12.0, 16.0, 20.0, 16.0, 0.4),
	]
	var original_inputs := var_to_bytes([cases, built.world, loaded.model.crash_hull, loaded.model.inertia])
	var results: Array[Dictionary] = []
	for fixture: Dictionary in cases:
		results.append(_measure(fixture, built.world, loaded.model))
	var inputs_unchanged := original_inputs == var_to_bytes([cases, built.world,
		loaded.model.crash_hull, loaded.model.inertia])
	_failed = _failed or not inputs_unchanged
	var report := {complete = not _failed, engine = Engine.get_version_info(),
		machine = {os = OS.get_name(), processor = OS.get_processor_name(),
			logical_cpu_count = OS.get_processor_count(), architecture = Engine.get_architecture_name(),
			debug_build = OS.is_debug_build()}, inputs_unchanged = inputs_unchanged,
		reference_sha256 = FileAccess.get_sha256(_reference.resource_path),
		candidate_sha256 = FileAccess.get_sha256(_candidate.resource_path),
		world_identity = built.world.identity, hull_points = loaded.model.crash_hull.size() / 3,
		warmup_calls = 50, calls_per_batch = 200, paired_batches = 5, cases = results}
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		printerr("cannot create report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("scenery empty-envelope probe: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _case(label: String, n0: float, e0: float, n1: float, e1: float, yaw: float) -> Dictionary:
	return {label = label, previous = _pose(n0, e0, 0.0), current = _pose(n1, e1, yaw)}


func _pose(n: float, e: float, yaw: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([n, e, -4.0]), PackedFloat64Array([80.0, 0.0, 0.0]),
		M.q_from_euler(yaw, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))


func _measure(fixture: Dictionary, world: Dictionary, model: Dictionary) -> Dictionary:
	var reference_times: Array[int] = []
	var candidate_times: Array[int] = []
	var a: Array = _reference.contacts(fixture.previous, fixture.current, model.crash_hull, world, 1,
		model.mass_kg, model.inertia)
	var b: Array = _candidate.contacts(fixture.previous, fixture.current, model.crash_hull, world, 1,
		model.mass_kg, model.inertia)
	var identical := _event_bytes(a) == _event_bytes(b)
	var expected_hit := str(fixture.label).ends_with("contact")
	if not identical or expected_hit != (not a.is_empty()):
		_failed = true
		printerr("unexpected contact/parity: ", fixture.label)
	for index: int in 50:
		_time(_reference, fixture, world, model, 1)
		_time(_candidate, fixture, world, model, 1)
	for pair: int in 5:
		if pair % 2 == 0:
			reference_times.append(_time(_reference, fixture, world, model, 200))
			candidate_times.append(_time(_candidate, fixture, world, model, 200))
		else:
			candidate_times.append(_time(_candidate, fixture, world, model, 200))
			reference_times.append(_time(_reference, fixture, world, model, 200))
	return {label = fixture.label, previous = fixture.previous, current = fixture.current,
		identical = identical, contacts = a.size(),
		reference_batch_usec = reference_times, candidate_batch_usec = candidate_times}


func _time(detector: GDScript, fixture: Dictionary, world: Dictionary, model: Dictionary, count: int) -> int:
	var started := Time.get_ticks_usec()
	for index: int in count:
		detector.contacts(fixture.previous, fixture.current, model.crash_hull, world, index,
			model.mass_kg, model.inertia)
	return Time.get_ticks_usec() - started


func _event_bytes(events: Array) -> PackedByteArray:
	var values: Array = []
	for event: RefCounted in events:
		var fields: Dictionary = {}
		for property: Dictionary in event.get_property_list():
			var value: Variant = event.get(property.name)
			if value is Object:
				continue # crossing objects are covered by the frozen-oracle suite.
			fields[property.name] = value
		values.append(fields)
	return var_to_bytes(values)
