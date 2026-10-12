# TT-05: clearances of each Turbo Lumber Evolution control surface against the fixed airframe at the manual high-rate
# throws (geometry.json controls) and at the authored hinge limits, with the Extra's generic mesh-pair checker (EX-04).
# The pass criterion is no penetration (no edge crossing a triangle, no vertex inside); the gap is reported because the
# author's hinge coves hold the control-surface noses 0.0-0.1 mm from the skin (seam contact), unlike the 3 mm gaps of
# the procedural models. Its own script because the airframe is one 36k-triangle mesh: a pair costs 10-90 s, the sweep
# about 10 min. Poses go through the Timber builder directly.
# Run: godot --headless --path app --script res://aircraft/verify_timber_clearance.gd
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd")
const SEAM_GAP_M := 0.0005 # below this the pair is reported as seam contact (information, not a failure)

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _pair(airplane: Dictionary, meshes: Dictionary, moving: String) -> Dictionary:
	var a: Array = Clearance._triangles(meshes[moving], airplane.root)
	var b: Array = Clearance._triangles(meshes.airframe, airplane.root)
	var near_b: Array = Clearance._near(b, Clearance._bounds(a))
	var near_a: Array = Clearance._near(a, Clearance._bounds(near_b)) if not near_b.is_empty() else []
	var penetrates: bool = Clearance._crosses(near_a, near_b) or Clearance._crosses(near_b, near_a) or Clearance._vertex_inside(a, near_b)
	return {penetrates = penetrates, gap_m = 0.0 if penetrates else Clearance._gap(near_a, near_b), near = near_b.size()}


func _run() -> void:
	var airplane := Timber.build()
	get_root().add_child(airplane.root)
	await process_frame
	var meshes := {}
	Clearance._collect(airplane.root, meshes)
	var t := Timber.manual_throws_deg()
	var limits: Dictionary = Timber.TimberGeometry.DATA.articulations
	# [label, surfaces_deg for apply_surfaces, flap_deg, moving meshes to check]
	var poses := [
		["ailerons manual %+.1f" % t.aileron, {aileron_right = t.aileron, aileron_left = -t.aileron}, 0.0, ["aileron_right", "aileron_left"]],
		["ailerons manual %+.1f" % -t.aileron, {aileron_right = -t.aileron, aileron_left = t.aileron}, 0.0, ["aileron_right", "aileron_left"]],
		["elevator manual %+.1f" % t.elevator, {elevator = t.elevator}, 0.0, ["elevator"]],
		["elevator manual %+.1f" % -t.elevator, {elevator = -t.elevator}, 0.0, ["elevator"]],
		["rudder manual %+.1f" % t.rudder, {rudder = t.rudder}, 0.0, ["rudder"]],
		["rudder manual %+.1f" % -t.rudder, {rudder = -t.rudder}, 0.0, ["rudder"]],
		["flaps manual full %.1f" % float(Timber.TimberGeometry.DATA.controls.flap.full_deg.value), {}, float(Timber.TimberGeometry.DATA.controls.flap.full_deg.value), ["flap_right", "flap_left"]],
		["flaps authored limit %.0f" % float(limits.flap_right_hinge.range_deg[1]), {}, float(limits.flap_right_hinge.range_deg[1]), ["flap_right"]],
		["elevator authored limit %+.0f" % float(limits.elevator_hinge.range_deg[1]), {elevator = float(limits.elevator_hinge.range_deg[1])}, 0.0, ["elevator"]],
		["elevator authored limit %+.0f" % float(limits.elevator_hinge.range_deg[0]), {elevator = float(limits.elevator_hinge.range_deg[0])}, 0.0, ["elevator"]],
		["rudder authored limit %+.0f" % float(limits.rudder_hinge.range_deg[1]), {rudder = float(limits.rudder_hinge.range_deg[1])}, 0.0, ["rudder"]],
	]
	var t0 := Time.get_ticks_msec()
	var minimum := INF
	for pose in poses:
		Timber.apply_surfaces(airplane, pose[1])
		Timber.set_flaps(airplane, pose[2])
		for moving in pose[3]:
			var result := _pair(airplane, meshes, moving)
			minimum = minf(minimum, result.gap_m)
			_check("%s: %s does not penetrate the airframe" % [pose[0], moving], not result.penetrates, "%d airframe triangles nearby" % result.near)
			print("%s | %s | %s gap %.4f m | %d nearby triangles | %d ms" % [pose[0], moving, "seam" if result.gap_m < SEAM_GAP_M else "clear", result.gap_m, result.near, Time.get_ticks_msec() - t0])
	Timber.apply_surfaces(airplane, {})
	Timber.set_flaps(airplane, 0.0)
	print("verify_timber_clearance: %d checks, %d failed, smallest gap %.4f m (%d ms)%s" % [_checks, _failures, minimum, Time.get_ticks_msec() - t0, "" if _failures == 0 else " FAIL"])
	quit(1 if _failures > 0 else 0)
