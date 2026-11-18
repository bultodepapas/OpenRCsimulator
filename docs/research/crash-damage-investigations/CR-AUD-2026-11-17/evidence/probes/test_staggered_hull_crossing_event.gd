# Candidate serializer regression probe, not run by the researcher.
# Two rigid points enter in one interpolated interval. The first point is at
# fraction 0.2; a distinct, higher-speed terminal point enters at 0.8. The typed
# snapshot intentionally holds the earliest *whole-hull* crossing, while the
# flattened event currently loses that crossing's point identity. Baseline is
# expected to fail only the final unambiguous-crossing assertion.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Hull := preload("res://physics/hull_contact.gd")
const Cross := preload("res://physics/hull_crossing.gd")
const Impact := preload("res://physics/impact_snapshot.gd")
const Events := preload("res://sim/aircraft_contact_events.gd")

var count := 0
var failures := 0

func check(label: String, ok: bool, detail := "") -> void:
	count += 1
	print(("ok   " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1

func _depth_r_for_crossing(fraction: float, lateral: float) -> float:
	# Invert the exact shortest-nlerp roll used by HullCrossing. The centre's
	# downward motion is 0.05 m/tick; endpoint roll changes 0.04 rad/tick.
	var half_theta: float = 0.02
	var roll := 2.0 * atan2(fraction * sin(half_theta), \
		1.0 - fraction + fraction * cos(half_theta))
	var center_down := -0.02 + 0.05 * fraction
	return -(center_down + sin(roll) * lateral) / cos(roll)

func _initialize() -> void:
	var q_before := M.q_identity()
	var q_after := M.q_from_euler(0.0, 0.0, 0.04)
	var v_world := M.v3(0.0, 0.0, 12.0)
	var rate := M.v3(9.6, 0.0, 0.0) # 0.04 rad during a 1/240 s tick
	var before := RB.make_state(M.v3(0.0, 0.0, -0.02), v_world, q_before, rate)
	var after := RB.make_state(M.v3(0.0, 0.0, 0.03), \
		M.q_rotate(M.q_conj(q_after), v_world), q_after, rate)
	var hull := PackedFloat64Array([0.0, -0.1, _depth_r_for_crossing(0.2, -0.1), \
		0.0, 0.1, _depth_r_for_crossing(0.8, 0.1)])
	var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var prepared: Dictionary = Hull.prepare(hull, 1.0, inertia)
	check("prepared two-point fixture", not prepared.is_empty())
	var early := Cross.reconstruct(before, after, hull.slice(0, 3))
	var selected := Cross.reconstruct(before, after, hull.slice(3, 6))
	check("independent early crossing is 0.2", early.available and absf(early.fraction - 0.2) < 1e-9)
	check("independent selected crossing is 0.8", selected.available and absf(selected.fraction - 0.8) < 1e-9)
	var hit: Dictionary = Hull.terminal(before, after, prepared)
	check("faster second point is selected by terminal policy", int(hit.index) == 1 and hit.rule == "impact", str(hit))
	if int(hit.index) != 1 or not early.available or not selected.available:
		print("PROBE invalid fixture; refusing to draw serializer conclusion")
		quit(1)
		return
	var snapshot: Impact.Snapshot = Impact.hull_point(after, 1, hull, int(hit.index), before, str(hit.rule))
	check("typed snapshot retains earliest point separately", snapshot.point_index == 1 \
		and snapshot.crossing.available and snapshot.crossing.point_index == 0 \
		and absf(snapshot.crossing.fraction - early.fraction) < 1e-9)
	var bindings := {"hull_probes": [{"id": "early_probe"}, {"id": "selected_probe"}]}
	var event: Dictionary = Events.impact_event(snapshot, bindings, Hull.law())
	check("terminal event serializes and validates", not event.is_empty() \
		and Events.validate_events([event], 1, bindings))
	print("OBSERVED selected_id=", event.get("contact_id", "MISSING"), \
		" selected_index=", snapshot.point_index, " crossing_index=", snapshot.crossing.point_index, \
		" event_fraction=", event.get("crossing_fraction", "MISSING"), \
		" independent_selected_fraction=", selected.fraction, \
		" event=", event)
	# The fraction is unambiguous if it identifies the selected point's crossing,
	# names the different earliest crossing point, or is withheld. This accepts
	# more than one valid future representation; it does not require new physics.
	var has_fraction := event.has("crossing_fraction")
	var fraction_is_selected := has_fraction and absf(float(event.crossing_fraction) - selected.fraction) < 1e-9
	var names_earliest: bool = event.get("crossing_point_index", -1) == snapshot.crossing.point_index \
		or event.get("crossing_probe_id", "") == "early_probe"
	check("flattened crossing is unambiguous about its point", not has_fraction or fraction_is_selected or names_earliest)
	print("PROBE staggered hull crossing: %d checks, %d failures" % [count, failures])
	quit(1 if failures > 0 else 0)
