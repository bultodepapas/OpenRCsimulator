extends SceneTree
## AE-23a: four-second bounded airborne refinement and real start qualification.

const Session := preload("res://sim/flight_session.gd")
const Qualification := preload("res://workshop/start_qualification.gd")
const Field := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("Required --out=<new-directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var compiler := preload("res://workshop/compiler.gd")
	var trial := preload("res://workshop/trial.gd")
	var bytes := FileAccess.get_file_as_bytes("res://data/aircraft/jensen_ugly_stik_60.json")
	var base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var rows := []
	var passed := true
	for policy: String in ["constant_wing_loading", "geometric"]:
		for scale: float in [0.35, 1.0, 2.25]:
			var recipe := {"scale": scale, "mass_policy": policy}
			var compiled: Dictionary = compiler.compile(base, recipe)
			var row := {"scale": scale, "policy": policy, "compiled": compiled.ok, "errors": Array(compiled.errors), "runs": []}
			passed = passed and (bool(compiled.ok) == not (policy == "geometric" and scale == 2.25))
			if compiled.ok:
				var frozen: Dictionary = trial.freeze({"base_id": str(base.id), "base_bytes": bytes, "recipe": recipe})
				row.frozen = frozen.ok
				passed = passed and bool(frozen.ok)
				if frozen.ok:
					for rate: int in [240, 480, 960]:
						Engine.physics_ticks_per_second = rate
						var session := Session.new()
						session.physics_enabled = false
						session.input_enabled = false
						session.setup("", str(frozen.data.model.id), frozen.data)
						var run := {"rate": rate, "flyable": session.is_flyable(), "start_error": session.start_error}
						var started := Time.get_ticks_usec()
						var minimum_altitude := INF
						if session.is_flyable():
							for tick in rate * 4:
								var t := float(tick) / rate
								session.sim.inputs[0] = 0.04 if t >= 0.5 and t < 1.0 else (-0.04 if t >= 1.0 and t < 1.5 else 0.0)
								session.sim.step()
								minimum_altitude = minf(minimum_altitude, -session.sim.state[2])
							run.tick = session.sim.tick
							run.fault = session.sim.fault_reason
							run.state = Array(session.sim.state)
							run.min_altitude_m = minimum_altitude
							run.usec_per_tick = float(Time.get_ticks_usec() - started) / (rate * 4)
						row.runs.append(run)
						passed = passed and bool(run.flyable) and int(run.get("tick", -1)) == rate * 4 and str(run.get("fault", "not run")).is_empty()
						for number: float in run.get("state", []): passed = passed and is_finite(number)
						session.free()
					Engine.physics_ticks_per_second = 240
					row.starts = {}
					for choice: String in ["airborne", "runway"]:
						row.starts[choice] = Qualification.qualify(frozen, Field.load_from().field, Weather.defaults(), choice)
					passed = passed and bool(row.starts.airborne.ok) and bool(row.starts.runway.ok) \
						and bool(row.starts.airborne.available) and (bool(row.starts.runway.available) == (scale == 1.0))
			rows.append(row)
			print("Scale ", scale, " ", policy, ": compiled=", compiled.ok)
	var report := FileAccess.open(out.path_join("refinement.json"), FileAccess.WRITE)
	# Failed ground solves can contain nonfinite diagnostics. Retain them explicitly
	# as strings rather than relying on JSON's implicit NaN-to-null conversion.
	report.store_string(JSON.stringify(_json_safe(rows), "\t", true, true))
	report.close()
	print("AE-23a expected compile/start/completion gates: ", passed)
	quit(0 if passed else 1)

func _json_safe(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and not is_finite(value): return str(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _json_safe(value[key])
		return result
	if value is Array or value is PackedFloat64Array or value is PackedFloat32Array:
		var result := []
		for child: Variant in value: result.append(_json_safe(child))
		return result
	return value
