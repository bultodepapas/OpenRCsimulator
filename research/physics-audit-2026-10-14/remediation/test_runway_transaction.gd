extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
var checks := 0
var failures := 0

class RejectingFlight extends "res://sim/flight_session.gd":
	var reject_candidate := false
	func _wheel_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		return {} if reject_candidate else super._wheel_evaluate(s, x, t)
	func _turbine_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		return {} if reject_candidate else super._turbine_evaluate(s, x, t)


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func snapshot(f: Node) -> PackedByteArray:
	return var_to_bytes([f.checkpoint(), f.commands, f.trims, f.crash, f.pause_reason,
		f.sim.paused, f._launch_metadata, f._gear_requested_down, f._wheel_brake_demand,
		f._weather_pending_reset, f._turbulence_aux_index])


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var field: Dictionary = Field.load_from().field
	var spot := GroundStart.threshold(field)
	for id in ["jensen-das-ugly-stik-60", "sebart-avanti-s-a200-p100rx"]:
		var f := RejectingFlight.new()
		f.setup(Catalog.entry(id).data)
		root.add_child(f)
		check(id + " field", f.set_field(field))
		f.input_enabled = false
		f.crash = {audit_sentinel = true}
		f.pause_reason = "audit prior valid state"
		f.sim.set_paused(true)
		var events := [0, 0, 0]
		f.resetting.connect(func(): events[0] += 1)
		f.sim.stepped.connect(func(_k, _t, _s, _l, _i, _a): events[1] += 1)
		f.sim.faulted.connect(func(_reason): events[2] += 1)
		var before := snapshot(f)
		var invalid := f.try_runway_start(NAN, spot.east, spot.heading)
		check(id + " invalid launch rejected", not invalid.ok)
		check(id + " invalid launch preserves complete prior state", snapshot(f) == before)
		check(id + " rejection publishes no reset, tick or fault", events == [0, 0, 0])
		f.reject_candidate = true
		var refused := f.try_runway_start(spot.north, spot.east, spot.heading)
		check(id + " nonfinite candidate refused after solve", not refused.ok and str(refused.message).contains("reset rejected"))
		check(id + " candidate rejection rolls context back", snapshot(f) == before)
		check(id + " failed candidate publishes nothing", events == [0, 0, 0])
		f.start_choice = Flight.START_RUNWAY
		f.reset()
		check(id + " ordinary runway reset retains prior valid flight on rejection", snapshot(f) == before)
		check(id + " ordinary rejected reset publishes nothing", events == [0, 0, 0])
		f.reject_candidate = false
		var accepted := f.try_runway_start(spot.north, spot.east, spot.heading)
		check(id + " valid candidate commits", accepted.ok and accepted.get("status") == "converged")
		check(id + " commit publishes one reset and one sample", events == [1, 1, 0])
		check(id + " accepted launch clears old crash", f.crash.is_empty() and f.start_error.is_empty())
		var cp: Dictionary = f.checkpoint()
		check(id + " accepted launch has restorable checkpoint", not cp.is_empty() and f.restore_checkpoint(cp))
		var incompatible: Dictionary = cp.duplicate(true)
		incompatible.aero_loads_law = "local-surfaces-v1"
		var restored_before := snapshot(f)
		check(id + " old wake meaning rejected transactionally", not f.restore_checkpoint(incompatible) and snapshot(f) == restored_before)
		var fell_back := f.reset_on_runway(NAN, spot.east, spot.heading)
		check(id + " legacy helper explicitly reports fallback", not fell_back and f.runway_start_outcome.fallback == "trimmed_airborne")
		check(id + " fallback trace preserves cause", f.trace_meta().launch_kind == "airborne_fallback" and not f.trace_meta().launch_error.is_empty())
		f.free()
	print("VAL-AUD-R04 launch transaction: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
