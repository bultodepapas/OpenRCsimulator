# C7: the flight trace — complete, self-describing, exact enough to debug with.
# Run: godot --headless --path . --script res://tests/test_trace.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Trace := preload("res://sim/trace.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var sim: Node = Sim.new()
	var aircraft := AircraftData.load_file(Scenarios.AIRCRAFT)
	sim.mass = aircraft.model.mass_kg
	sim.inertia = aircraft.model.inertia
	root.add_child(sim)
	var trace := Trace.new()
	trace.meta = { scenario = "test" }
	sim.stepped.connect(trace.record)
	sim.reset(Scenarios.throw_across_view())
	for i in 360:
		sim.step()

	# Completeness: tick 0 plus one row per step, no gaps, time = tick · dt.
	_check("361 rows for 1.5 s at 240 Hz", trace.row_count() == 361, str(trace.row_count()))
	_check("no missing ticks", trace.gaps().is_empty(), str(trace.gaps()))
	_check("ticks continuous from 0", trace.is_continuous() and trace.value(0, "tick") == 0.0)
	var time_ok := true
	for r in trace.row_count():
		time_ok = time_ok and absf(trace.value(r, "t_s") - trace.value(r, "tick") * sim.dt()) < 1e-12
	_check("t_s = tick · dt", time_ok)

	# Exactness on EVERY row against its own timestamp: altitude 30 - ½gt², east -40 + 15t.
	# (Checking only the final row missed a one-tick time-labeling bug.)
	var worst_alt := 0.0
	var worst_east := 0.0
	for r in trace.row_count():
		var t := trace.value(r, "t_s")
		worst_alt = maxf(worst_alt, absf(trace.value(r, "alt_m") - (30.0 - 0.5 * 9.80665 * t * t)))
		worst_east = maxf(worst_east, absf(trace.value(r, "east_m") - (-40.0 + 15.0 * t)))
	_check("every row: alt = 30 - ½g·t²", worst_alt < 1e-9, str(worst_alt))
	_check("every row: east = -40 + 15·t", worst_east < 1e-9, str(worst_east))
	var last := trace.row_count() - 1
	_check("alt at 1.5 s = 30 - ½g·1.5²", absf(trace.value(last, "alt_m") - (30.0 - 0.5 * 9.80665 * 2.25)) < 1e-9)
	_check("east at 1.5 s = -17.5 m", absf(trace.value(last, "east_m") + 17.5) < 1e-9)
	_check("heading 90° throughout", absf(trace.value(last, "yaw_deg") - 90.0) < 1e-9)

	# CSV: metadata first, one header, units on physical columns, same width on every row.
	var lines := trace.to_csv().strip_edges().split("\n")
	_check("first line names the format", lines[0] == "# format: openrc-trace v1", lines[0])
	var header := ""
	var data := 0
	var widths_ok := true
	for line in lines:
		if line.begins_with("#"):
			continue
		if header == "":
			header = line
			continue
		data += 1
		widths_ok = widths_ok and line.split(",").size() == Trace.COLUMNS.size()
	_check("header matches COLUMNS", header == ",".join(Trace.COLUMNS))
	_check("every data row has every column", widths_ok and data == 361, "%d rows" % data)
	var unitless := []
	for c in Trace.COLUMNS:
		var dimensionless: bool = c in ["tick", "qw", "qx", "qy", "qz"] or c.begins_with("cmd_")
		if not dimensionless and not (c.ends_with("_m") or c.ends_with("_s") or c.ends_with("_mps") or c.ends_with("_deg") or c.ends_with("_radps") or c.ends_with("_N") or c.ends_with("_Nm")):
			unitless.append(c)
	_check("physical columns carry units", unitless.is_empty(), str(unitless))

	# Round trip: the CSV text parses back to the recorded value at 1e-9 precision.
	var last_cells := lines[lines.size() - 1].split(",")
	var col := Trace.COLUMNS.find("down_m")
	_check("CSV round trip", absf(float(last_cells[col]) - trace.value(last, "down_m")) < 1e-9, last_cells[col])

	# A dropped sample is visible.
	var holey := Trace.new()
	for k in 11:
		if k != 5:
			holey.record(k, k * sim.dt(), sim.state, sim.last_loads, sim.inputs)
	_check("gaps() reports a dropped tick", holey.gaps() == PackedInt64Array([5]), str(holey.gaps()))
	_check("a dropped tick breaks continuity", not holey.is_continuous())
	var dup := Trace.new()
	for k in [0, 0, 1, 2]:
		dup.record(k, k * sim.dt(), sim.state, sim.last_loads, sim.inputs)
	_check("a duplicated tick breaks continuity", not dup.is_continuous())

	# Save and read back from disk.
	var path := "user://test-traces/trace-test.csv"
	_check("save succeeds", trace.save(path) == OK)
	_check("file on disk equals to_csv()", FileAccess.get_file_as_string(path) == trace.to_csv())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
