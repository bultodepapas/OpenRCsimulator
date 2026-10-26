extends SceneTree

const Flight := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-fixed-brake-session/flight_session.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Log := preload("res://sim/flight_log.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const DIR := "res://../docs/research/ground-physics/GP-12/evidence/input-role-replay/recordings/"
var checks := 0
var failures := 0
var results: Array = []

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	for id: String in ["gp-extra-300s-60", "jensen-das-ugly-stik-60", "p51d-mustang-120",
		"sebart-avanti-s-a200-p100rx", "stik-glow-61fx-2t", "turbo-lumber-evolution"]:
		compare(id)
	var output := FileAccess.open("res://../tmp/gp12-fixed-brake-session/baseline-comparison.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({scope = "explicit candidate physics comparison; draft runtime hashes separately pinned; no historical exact-source identity claim",
		current_recording_solver_identity = Log.solver_identity(), results = results}, "\t"))
	output.close()
	print("Fixed brake baseline tapes: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func compare(id: String) -> void:
	var path := DIR + id + ".orfl"
	var original := FileAccess.get_sha256(path)
	var inspected := Reader.inspect(path)
	check("baseline remains readable " + id, inspected.ok and inspected.complete)
	if not inspected.ok: return
	var header: Dictionary = inspected.header
	# Explicit candidate request: current source differs from the retained source cohort.
	var prepared := Reader.prepare_replay(header, Catalog.entry(id).data)
	check("explicit candidate installed owner prepares " + id, prepared.ok)
	if not prepared.ok:
		results.append({id = id, error = prepared.error})
		return
	var old: Node = prepared.flight
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.soft_hull_contacts = header.soft_hull_contacts
	f.setup(header.aircraft_path, "", old.aircraft)
	f.ground_surfaces = header.ground_surfaces.duplicate()
	f.airframe_surfaces = header.get("airframe_surfaces", PackedFloat64Array())
	f.ground_field_id = header.ground_field_id
	var ready: bool = f.setup_shaft_integrator(header.shaft_integrator) and f.setup_weather(header.weather) \
		and f.set_collision_world(header.collision_world) and f.set_lake_context(header.lake)
	f.reset()
	check("draft accepts same explicit candidate checkpoint " + id, ready and f.restore_checkpoint(old.checkpoint()))
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var first := true
	var reproduced := 0
	var difference := ""
	var candidate_difference := ""
	var observer := Log.new(f)
	var control_observer := Log.new(old)
	while stream.get_position() < stream.get_length():
		var packet := Log.read_packet(stream)
		if not packet.ok:
			difference = "packet invalid"
			break
		if packet.value.kind == "footer": break
		for row: Dictionary in packet.value.rows:
			if first:
				first = false
				continue
			for target: Node in [f, old]:
				for key: String in row.intervention: target.sim.set(key, row.intervention[key].duplicate())
				target.sim.inputs = row.inputs.duplicate()
				target.sim.step()
			var actual := observer._sample({})
			var mismatch := Reader.disagreement(row, actual)
			if difference.is_empty() and not mismatch.is_empty(): difference = mismatch
			mismatch = Reader.disagreement(control_observer._sample({}), actual)
			if candidate_difference.is_empty() and not mismatch.is_empty(): candidate_difference = mismatch
			reproduced += 1
	stream.close()
	check("old layouts unchanged through entire tape " + id, candidate_difference.is_empty() and reproduced == inspected.rows - 1)
	check("baseline file remains exact bytes " + id, original == FileAccess.get_sha256(path))
	results.append({id = id, baseline_sha256 = original, original_solver_sha256 = header.solver_sha256,
		solver_changed = header.solver_sha256 != Log.solver_identity(), compared_ticks = reproduced,
		historical_row_difference = difference, draft_vs_installed_candidate_difference = candidate_difference})
	f.free()
	old.free()
