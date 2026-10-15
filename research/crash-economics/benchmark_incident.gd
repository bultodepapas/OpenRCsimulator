extends SceneTree
## CR-30/32-R1 isolated software benchmark; not whole-frame or physical qualification.
## godot --headless --path app --script ../research/crash-economics/benchmark_incident.gd
const Incident = preload("res://economy/incident.gd")
const Catalog = preload("res://economy/catalog.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const SAMPLES := 100
const BATCH := 64
const WARMUP := 10
var failed := false


func _initialize() -> void:
	var loaded := Catalog.load_for("jensen-das-ugly-stik-60")
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var result := {
		"format": "openrc-incident-benchmark-v1", "date": "2026-10-15",
		"godot": Engine.get_version_info().string, "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"samples": SAMPLES, "ingestion_batch_size": BATCH, "warmup_batches": WARMUP,
		"timing_unit": "microseconds_per_operation", "rendering": "headless",
		"limits": "Isolated ingestion and report construction. Excludes source loading, session snapshot/ground queries, solver, UI and disk; not full 500 us tick qualification. Synthetic 100-part BOM is not a retail aircraft.",
		"healthy_ingestion": _ingestion(loaded, "healthy"),
		"new_contact_ingestion": _ingestion(loaded, "new"),
		"overflow_ingestion": _ingestion(loaded, "overflow"),
		"report_100_parts": _report_construction(),
		"correctness_passed": not failed,
	}
	print(JSON.stringify(result, "  ", true))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var file := FileAccess.open(argument.trim_prefix("--out="), FileAccess.WRITE)
			if file == null:
				failed = true
			else:
				file.store_string(JSON.stringify(result, "  ", true) + "\n")
				file.close()
	quit(1 if failed else 0)


func _ingestion(loaded: Dictionary, mode: String) -> Dictionary:
	var bindings := {"hull_probes": [{"id": "benchmark_probe"}]}
	var snapshots: Array = []
	# Build all payloads before timing; each new event has a unique accepted tick.
	for tick in range(1, (SAMPLES + WARMUP) * BATCH + Incident.MAX_EVENTS + 1):
		var events: Array = []
		if mode != "healthy":
			events = Events.hull_events([{index = 0, new = true, depth_m = 0.001}], bindings, PackedStringArray(), tick).events
		snapshots.append({tick = tick, events = events})
	var ledger := Incident.new()
	var times: Array[float] = []
	for sample in SAMPLES + WARMUP:
		ledger.begin_with_catalog(loaded, "jensen-das-ugly-stik-60", "benchmark")
		var offset := sample * BATCH
		if mode == "overflow":
			for index in Incident.MAX_EVENTS:
				ledger.observe(snapshots[index], bindings, false)
			offset += Incident.MAX_EVENTS
		var start := Time.get_ticks_usec()
		for index in BATCH:
			ledger.observe(snapshots[offset + index], bindings, false)
		var elapsed := Time.get_ticks_usec() - start
		if sample >= WARMUP:
			times.append(float(elapsed) / BATCH)
		failed = failed or not ledger.report.is_empty()
		var expected_events := 0 if mode == "healthy" else (Incident.MAX_EVENTS if mode == "overflow" else BATCH)
		failed = failed or ledger.journal.size() != expected_events or ledger._seen.size() > Incident.MAX_EVENTS
	return _summary(times)


func _report_construction() -> Dictionary:
	var dossier: Dictionary = {
		"format": "openrc-aircraft-economics v1", "aircraft_id": "synthetic-benchmark",
		"source_sha256": "synthetic-benchmark", "currency": "USD", "price_date": "2026-10-15",
		"valuation_kind": "synthetic-benchmark", "complete": true, "components": [],
		"missing": [], "exclusions": [],
	}
	var dispositions: Dictionary = {}
	for index in 100:
		var id := "component_%03d" % index
		dossier.components.append({"id": id, "quantity": 1, "unit_minor": 100,
			"low_unit_minor": 100, "high_unit_minor": 100, "physical_inventory_ids": [id],
			"price_basis": "synthetic-benchmark", "offer_id": null})
		dispositions[id] = {"disposition": "replace"}
	var loaded := {"ok": true, "dossier": dossier, "catalog_hash": "synthetic-benchmark"}
	var ledger := Incident.new()
	var times: Array[float] = []
	for sample in SAMPLES + WARMUP:
		ledger.begin_with_catalog(loaded, "synthetic-benchmark", "synthetic-benchmark")
		# Seed an explicit assessment, not a claimed physical inference from one impact.
		ledger._assessment.components = dispositions.duplicate(true)
		ledger._queue_assessment(1)
		var start := Time.get_ticks_usec()
		ledger.evaluate_pending()
		var elapsed := Time.get_ticks_usec() - start
		if sample >= WARMUP:
			times.append(float(elapsed))
		failed = failed or not ledger.report.get("ok", false) or ledger.report.get("total_minor") != 10000 or ledger.report.get("lines", []).size() != 100
	return _summary(times)


func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median_us": values[values.size() / 2], "p95_us": values[int(ceil(values.size() * 0.95)) - 1], "max_us": values.back()}
