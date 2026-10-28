extends SceneTree
# Capture the four legacy output digests from a reconstruct_legacy_reference.py tree.
# Copy into <reference>/app/ and run:
#   godot --headless --path <reference>/app --script res://capture_legacy_outputs.gd -- --out=<capture.json>
# Helpers are the installed test_fixed_gear_brake_input.gd legacy() body, unchanged.

const Flight := preload("res://sim/flight_session.gd")
const Trace := preload("res://sim/trace.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const IDS := ["gp-extra-300s-60", "jensen-das-ugly-stik-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"]

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func legacy_metadata(f: Node) -> Dictionary:
	var metadata: Dictionary = f.trace_meta()
	metadata.created_utc = "fixed-brake-legacy-fixture-time"
	return metadata

func step(f: Node, count: int) -> void:
	for i: int in count:
		f.sim.inputs = f._inputs()
		f.sim.step()

func record(trace: RefCounted, f: Node) -> void:
	trace.meta.mass_trace_schema = "openrc-mass-sample v1"
	trace.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs,
		f.sim.aux, f.sim.continuous, f.mass_properties())

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_path = arg.substr(6)
	var reference: Variant = {}
	if out_path.is_empty():
		printerr("capture needs --out= and a reconstructed reference.json")
		quit(2)
		return
	var outputs := {}
	for id: String in IDS:
		var f := Flight.new()
		f.setup(Catalog.entry(id).data)
		var row := {checkpoint = digest(f.checkpoint()), metadata = digest(legacy_metadata(f)), checkpoint_value = f.checkpoint(), metadata_value = legacy_metadata(f)}
		var trace := Trace.new()
		trace.meta = legacy_metadata(f)
		record(trace, f)
		row.trace_csv = trace.to_csv().sha256_text() if trace.row_count() == 1 else ""
		row.csv_value = trace.to_csv() if trace.row_count() == 1 else ""
		step(f, 3)
		row.after_three_ticks = digest(f.sim.checkpoint())
		outputs[id] = row
		f.free()
	var capture := {format = "openrc-fixed-brake-legacy-capture v1", os = OS.get_name(),
		engine = Engine.get_version_info().string, physics_hz = Engine.physics_ticks_per_second,
		reference = reference, session_sha256 = FileAccess.get_sha256("res://sim/flight_session.gd"),
		trace_sha256 = FileAccess.get_sha256("res://sim/trace.gd"), outputs = outputs}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(capture, "\t", true) + "\n")
	file.close()
	print("captured %s on %s" % [out_path, OS.get_name()])
	quit(0)
