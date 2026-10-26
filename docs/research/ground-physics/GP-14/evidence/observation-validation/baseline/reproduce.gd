extends SceneTree

const Adapter := preload("res://statistics/fixed_wing_adapter.gd")

class PacketSession:
	extends Node
	var statistics_generation := 7
	var sim := {"tick": 3}

var checks := 0
var failures := 0

func _initialize() -> void:
	var adapter: RefCounted = Adapter.new()
	var session := PacketSession.new()
	adapter.session = session
	var packet := {"schema": "openrc-aircraft-accident-observation", "version": 1,
		"tick": 3, "generation": 7, "gear_up_contact": true, "ground_contact": true,
		"intended_support": false, "terminal": false}
	var before := var_to_bytes(packet)
	for value: Variant in [null, false, 1, 1.0, [], {}, PackedStringArray(),
		PackedFloat64Array(), &"openrc-aircraft-accident-observation", "unknown"]:
		var malformed := packet.duplicate(true)
		malformed.schema = value
		var result: Variant = adapter._accident_observation({"accident_observation": malformed})
		checks += 1
		if not result is Dictionary or not result.is_empty(): failures += 1
	checks += 1
	if var_to_bytes(packet) != before: failures += 1
	var accepted: Dictionary = adapter._accident_observation({"accident_observation": packet})
	checks += 1
	if var_to_bytes(accepted) != before: failures += 1
	accepted.terminal = true
	checks += 1
	if packet.terminal: failures += 1
	session.free()
	print("GP14 observation validation: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
