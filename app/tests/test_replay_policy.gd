# H9: fixed component budgets, stamped additive records, legacy compatibility, mutation rejection.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Golden := preload("res://tests/golden_flights.gd")
const Policy := preload("res://tests/replay_policy.gd")
var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	for component in Policy.COMPONENTS:
		var spec: Dictionary = Policy.COMPONENTS[component]
		check(component + " accepts half its budget", Policy.accepted(component, spec.absolute * 0.5, 0.0))
		check(component + " rejects twice its budget", not Policy.accepted(component, spec.absolute * 2.0, 0.0))
		check(component + " rejects NaN", not Policy.accepted(component, NAN, 0.0))
		check(component + " scaled diagnostic", Policy.normalized_error(component, spec.scale, 0.0) == 1.0)
	var flight := Flight.new()
	flight.setup()
	root.add_child(flight)
	var record := Golden.record(flight, "roll_15")
	check("new records identify engine/platform/build", record.stamp.os != "" and record.stamp.architecture != "" and record.stamp.godot.has("hash") and record.stamp.build.commit != "")
	check("new records include sampled/discrete checkpoints", record.aux_checkpoints.size() == record.checkpoints.size() and record.mode_checkpoints.size() == record.checkpoints.size())
	# Use the actual on-disk encoding; the format stays v1 with additive fields.
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(record, "", false, true))
	var replayed: Dictionary = Golden.replay(flight, decoded)
	print("H9 round-trip: ", replayed)
	check("stamped v1 round trip replays", replayed.ok)
	for entry in [["position", "checkpoints", 1], ["velocity", "checkpoints", 4], ["attitude", "checkpoints", 7], ["rate", "checkpoints", 11], ["rpm", "aux_checkpoints", 1], ["servo", "aux_checkpoints", 2]]:
		var mutation := decoded.duplicate(true)
		mutation[entry[1]][1][entry[2]] += 2.0 * Policy.COMPONENTS[entry[0]].absolute
		check(entry[0] + " checkpoint mutation rejected", not Golden.replay(flight, mutation).ok)
	var bad := decoded.duplicate(true)
	bad.mode_checkpoints[1][1] = 0
	check("discrete mode mismatch rejected", not Golden.replay(flight, bad).ok)
	for field in ["aux_checkpoints", "mode_checkpoints", "stamp"]:
		bad = decoded.duplicate(true)
		bad.erase(field)
		check("partial extension rejected: " + field, not Golden.replay(flight, bad).ok)
	bad = decoded.duplicate(true)
	bad.checkpoints[1][1] = NAN
	check("nonfinite checkpoint rejected", not Golden.replay(flight, bad).ok)
	bad = decoded.duplicate(true)
	bad.checkpoints[1][1] += 1e-3
	bad.policy.components.position.absolute = 1.0
	check("recorded metadata cannot loosen test budgets", not Golden.replay(flight, bad).ok)
	bad = decoded.duplicate(true)
	bad.stamp.ticks_per_second *= 2.0
	check("recorded clock must match replay timestep", not Golden.replay(flight, bad).ok)
	bad.stamp.ticks_per_second = "240"
	check("recorded clock must be numeric", not Golden.replay(flight, bad).ok)
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Golden.path("roll_15")))
	check("legacy v1 remains readable", not legacy.has("policy") and Golden.replay(flight, legacy).ok)
	print("H9 replay policy: %d checks, %d failed" % [checks, failures])
	flight.free()
	quit(1 if failures else 0)
