extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Qualification := preload("res://workshop/start_qualification.gd")
const Field := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../tmp/workshop-extreme")
	var compiler := preload("res://workshop/compiler.gd")
	var trial := preload("res://workshop/trial.gd")
	var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/jensen_ugly_stik_60.json")
	var raw: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var results := []
	for policy: String in ["constant_wing_loading", "geometric"]:
		for scale: float in [0.1, 0.2, 0.35, 1.0, 2.25, 5.0]:
			var recipe := {"scale": scale, "mass_policy": policy, "size_model": "virtual_similarity_v1"}
			var compiled: Dictionary = compiler.compile(raw, recipe)
			var row := {"scale": scale, "policy": policy, "compiled": compiled.ok, "errors": Array(compiled.errors)}
			if compiled.ok:
				row.mass_kg = compiled.data.model.mass_kg
				row.span_m = compiled.summary.wing_span_m
				var file := FileAccess.open(out.path_join("candidate-%s-%s.json" % [policy, scale]), FileAccess.WRITE)
				file.store_string(JSON.stringify(compiled.raw, "\t", true, true))
				file.close()
				var frozen: Dictionary = trial.freeze({"base_id": str(raw.id), "base_bytes": bytes, "recipe": recipe})
				row.frozen = frozen.ok
				if frozen.ok:
					var session := Session.new()
					session.physics_enabled = false
					session.input_enabled = false
					session.setup("", str(frozen.data.model.id), frozen.data)
					row.flyable = session.is_flyable()
					row.start_error = session.start_error
					row.message = session.start.get("message", "")
					var started := Time.get_ticks_usec()
					if session.is_flyable():
						for tick in 480:
							session.sim.inputs[0] = 0.08 if tick >= 120 and tick < 240 else 0.0
							session.sim.step()
						row.tick = session.sim.tick
						row.fault = session.sim.fault_reason
						row.state = Array(session.sim.state)
					row.step_usec = Time.get_ticks_usec() - started
					session.free()
				else: row.freeze_errors = Array(frozen.errors)
			results.append(row)
			print("Scale ", scale, " ", policy, ": compile=", compiled.ok, " start=", row.get("flyable", false), " errors=", row.get("errors", []), row.get("start_error", ""))
	var report := FileAccess.open(out.path_join("accepted-probe.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(results, "\t", true, true))
	report.close()
	quit()
