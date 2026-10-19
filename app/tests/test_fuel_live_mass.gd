# FUEL-06: the session's live mass-properties sample and its consumers. A finite-fuel session reports the
# shared kernel at the remaining tank mass; constant-mass aircraft report their validated build; the load
# factor divides by the live weight; flight logs carry the live mass and CG every tick.
# Run: godot --headless --path app --script res://tests/test_fuel_live_mass.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const MassInventory := preload("res://physics/mass_inventory.gd")
const Telemetry := preload("res://render/overlays/telemetry.gd")
const RB := preload("res://physics/rigid_body.gd")

const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_glow_sample()
	_constant_sample()
	_load_factor()
	_flight_log()
	print("FUEL-06 live mass: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


## Component-wise: a full tank yields -0.0 offsets, which differ from 0.0 only in their bytes.
func _is_origin(v: PackedFloat64Array) -> bool:
	return v.size() == 3 and v[0] == 0.0 and v[1] == 0.0 and v[2] == 0.0


func _session(path: String) -> Node:
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.setup(path)
	return flight


func _glow_sample() -> void:
	var flight: Node = _session(GLOW)
	_check("glow session is flyable", flight.is_flyable())
	var model: Dictionary = flight.aircraft.model
	var install: Dictionary = model.propulsion.glow
	var full: Dictionary = flight.mass_properties()
	_check("full tank: live sample is the validated wet build at the datum",
		full.get("ok", false) and full.finite_fuel and full.mass_kg == model.mass_kg
		and _is_origin(full.cg_body_m) and full.fuel_remaining_kg == install.initial_fuel_kg)
	var half: float = 0.5 * install.initial_fuel_kg
	flight.sim.continuous[1] = half
	var live: Dictionary = flight.mass_properties()
	var expected: Dictionary = MassInventory.evaluate_reference(install.mass_reference, PackedFloat64Array([half]))
	_check("half tank: live sample equals the shared kernel at the remaining fuel",
		live.get("ok", false) and live.mass_kg == expected.mass_kg and live.cg_body_m == expected.cg_body_m
		and live.inertia == expected.inertia and live.fuel_remaining_kg == half)
	_check("burning the tank ahead of the CG moves the live CG aft (body x < 0) and lightens the airplane",
		live.cg_body_m[0] < 0.0 and live.mass_kg < full.mass_kg, "cg %s" % str(live.cg_body_m))
	flight.free()


func _constant_sample() -> void:
	var flight: Node = _session(STIK)
	var live: Dictionary = flight.mass_properties()
	_check("prescribed fuel reports its constant build with no remaining-fuel claim",
		live.get("ok", false) and not live.finite_fuel and live.mass_kg == flight.sim.mass
		and _is_origin(live.cg_body_m) and is_nan(live.fuel_remaining_kg))
	flight.free()


func _load_factor() -> void:
	var state: PackedFloat64Array = RB.make_state(PackedFloat64Array([0.0, 0.0, -30.0]), PackedFloat64Array([20.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var air := {V = 20.0, alpha = 0.0, beta = 0.0}
	var loads := PackedFloat64Array([0.0, 0.0, -29.0, 0.0, 0.0, 0.0])
	var wet: Dictionary = Telemetry.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), air, {last_loads = loads, mass = 3.0, gravity = 9.80665})
	var dry: Dictionary = Telemetry.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), air, {last_loads = loads, mass = 2.7, gravity = 9.80665})
	_check("the load factor scales with 1/live mass (same force, lighter airplane reads more g)",
		absf(dry.load_factor / wet.load_factor - 3.0 / 2.7) < 1e-12, "%f vs %f" % [wet.load_factor, dry.load_factor])


func _flight_log() -> void:
	var flight: Node = _session(GLOW)
	var path: String = ProjectSettings.globalize_path("res://../tmp/fuel06-%d.orfl" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var logger: RefCounted = Log.new(flight)
	_check("log starts on a glow flight", logger.start(path) == OK)
	flight.sim.inputs[3] = 1.0
	for _tick in 240:
		flight.sim.step()
	var final: Dictionary = flight.mass_properties()
	_check("log stops", logger.stop() == OK)
	var read: Dictionary = Reader.inspect(path)
	_check("log reads back", read.get("ok", false), str(read.get("error", "")))
	if not read.get("ok", false):
		flight.free()
		return
	_check("the header declares the four-value mass block", int(read.header.layout.get("mass", 0)) == 4)
	var columns: PackedStringArray = Reader.columns(read.header.layout)
	_check("CSV columns carry mass and CG offset", columns.has("mass_kg") and columns.has("cg_offset_x_m"))
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var masses := PackedFloat64Array()
	var last: PackedFloat64Array
	while stream.get_position() < stream.get_length():
		var block: Dictionary = Log.read_packet(stream).value
		if block.kind == "footer":
			break
		for row: Dictionary in block.rows:
			masses.append(row.mass[0])
			last = row.mass
	stream.close()
	var monotonic := true
	for i in range(1, masses.size()):
		monotonic = monotonic and masses[i] <= masses[i - 1]
	_check("logged mass never increases while the engine burns, and it does burn",
		monotonic and masses.size() == 241 and masses[masses.size() - 1] < masses[0],
		"%s -> %s kg" % [str(masses[0]), str(masses[masses.size() - 1])])
	_check("the last logged sample is the session's live sample",
		last[0] == final.mass_kg and last[1] == final.cg_body_m[0] and last[3] == final.cg_body_m[2])
	DirAccess.remove_absolute(path)
	flight.free()
