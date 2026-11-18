extends SceneTree

# Constructed 240-Hz, 2 m/s helicopter body-probe crossing. This exercises the
# production shared scenery contact generator and helicopter detector directly;
# it is not a flown session or a material-strength measurement.
const Data := preload("res://physics/rotorcraft_data.gd")
const Detector := preload("res://physics/rotorcraft/impact_detector.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["PASS" if condition else "FAIL", label, detail])

func _world(north: float, east: float, down: float, response: String) -> Dictionary:
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "fixture", "rc_track", "tyre_stack", response,
		north, east, down, 0.010, 0.010, 0.003, 0.0)
	return {"format": CollisionWorld.FORMAT, "identity": "heli-soft-audit", "cell_size_m": 32.0,
		"proxies": proxies, "bins": CollisionWorld._build_bins(proxies)}

func _run() -> void:
	var loaded: Dictionary = Data.load_file("res://data/aircraft/xcell_60_research.json")
	_check("stock helicopter data loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var context: Dictionary = loaded.context
	var skids: Dictionary = loaded.skids
	var prepared: Dictionary = Detector.prepare(context, skids)
	_check("stock helicopter collision probes prepare", bool(prepared.get("ok", false)), str(prepared.get("error", "")))
	if not prepared.get("ok", false):
		_finish()
		return
	var chosen: PackedFloat64Array = PackedFloat64Array()
	for probe: Dictionary in prepared.probes:
		var point: PackedFloat64Array = probe.point
		# Lower-front fuselage corner remains well below the stopped main rotor.
		if str(probe.component) == "fuselage" and point[0] > 0.0 and point[2] > 0.0:
			chosen = point
			break
	_check("a lower-front fuselage point is available", chosen.size() == 3, str(chosen))
	if chosen.size() != 3:
		_finish()
		return
	var start := PackedFloat64Array([5.0, 5.0, -10.0, 2.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var end: PackedFloat64Array = start.duplicate()
	end[0] += 2.0 / 240.0
	var n: float = start[0] + chosen[0] + 1.0 / 240.0
	var e: float = start[1] + chosen[1]
	var d: float = start[2] + chosen[2]
	var soft: Dictionary = _world(n, e, d, "frangible_impulse")
	var hard: Dictionary = _world(n, e, d, "hard_terminal")
	var surface := PackedFloat64Array()
	var continuous := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var phase := PackedFloat64Array([0.0, 0.0])
	var contacts: Array = SceneryCollision.contacts(start, end, prepared.hull, soft, 1,
		float(context.mass_kg), context.inertia_body_kg_m2)
	_check("shared hull sweep finds the frangible crossing as nonterminal", not contacts.is_empty() \
		and not contacts[0].terminal and absf(float(contacts[0].normal_speed_mps) - 2.0) < 1.0e-6,
		"events=%d point=%s speed=%s" % [contacts.size(), chosen, contacts[0].normal_speed_mps if not contacts.is_empty() else "none"])
	if not contacts.is_empty():
		var event: Variant = contacts[0]
		var response: Dictionary = SceneryCollision.apply_response(event.contact_state(), event,
			float(context.mass_kg), context.inertia_body_kg_m2)
		_check("shared nonterminal response has a finite impulse", bool(response.get("ok", false)) \
			and response.get("state") is PackedFloat64Array \
			and response.state.to_byte_array() != event.contact_state().to_byte_array(), str(response))
	var soft_result: Dictionary = Detector.evaluate(start, end, continuous, context, skids, surface, phase, soft, prepared)
	var hard_result: Dictionary = Detector.evaluate(start, end, continuous, context, skids, surface, phase, hard, prepared)
	var open_result: Dictionary = Detector.evaluate(start, end, continuous, context, skids, surface, phase, {}, prepared)
	_check("helicopter detector discards the frangible body contact", bool(soft_result.get("ok", false)) \
		and soft_result.get("impact", {}).is_empty(), str(soft_result))
	_check("same hard box yields a terminal helicopter body impact", bool(hard_result.get("ok", false)) \
		and str(hard_result.get("impact", {}).get("component", "")) == "fuselage" \
		and absf(float(hard_result.impact.get("normal_speed_mps", NAN)) - 2.0) < 1.0e-6, str(hard_result))
	_check("open-air control is clear", bool(open_result.get("ok", false)) and open_result.get("impact", {}).is_empty(), str(open_result))
	print("fixture: part=fuselage start=%s end=%s obstacle=(%.9f, %.9f, %.9f)" % [start, end, n, e, d])
	_finish()

func _finish() -> void:
	print("HELI_SOFT_CONTACT_PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
