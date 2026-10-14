# TT-05: compare each moving control's surface triangles against its matching r2 fixed section mesh at manual throws and authored limits.
# The supplier notes contact near flap 40° and suspension travel beyond about 6°. The imported gear meshes aggregate
# the leg and wire link, so the gear/bracket comparison is diagnostic only. Open/overlapping shells are checked by
# triangle crossings and surface gap; ray-parity containment is not claimed for those assets.
# Run: godot --headless --path app --script res://aircraft/verify_timber_clearance.gd
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd")
const SEAM_GAP_M := 0.0005 # below this the pair is reported as contact (information, not a clearance pass)
const FIXED_FOR_MOVING := {
	"aileron_left": "wing_left_fixed", "flap_left": "wing_left_fixed",
	"aileron_right": "wing_right_fixed", "flap_right": "wing_right_fixed",
	"elevator": "stabilizer_fixed", "rudder": "fin_fixed",
}

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _pair(airplane: Dictionary, meshes: Dictionary, moving: String, fixed: String, recompute_gap := true) -> Dictionary:
	var a: Array = Clearance._triangles(meshes[moving], airplane.root)
	var b: Array = Clearance._triangles(meshes[fixed], airplane.root)
	var near_b: Array = Clearance._near(b, Clearance._bounds(a))
	var near_a: Array = Clearance._near(a, Clearance._bounds(near_b)) if not near_b.is_empty() else []
	# Imported r2 parts aggregate open and overlapping shells. The AABB-filtered triangles are useful for edge crossing,
	# but neither they nor the aggregate asset support a sound ray-parity containment test. Geometry3D's fixed
	# determinant epsilon misses millimetre-scale faces in metres; scale only the crossing predicate to mm. Gaps stay m.
	var crosses := _crosses_mm(near_a, near_b) or _crosses_mm(near_b, near_a)
	var gap_m := 0.0 if crosses else (Clearance._gap(near_a, near_b) if recompute_gap else NAN)
	return {crosses = crosses, gap_m = gap_m, near = near_b.size()}


func _gap_label(gap_m: float) -> String:
	return "not recomputed" if is_nan(gap_m) else "%.4f m" % gap_m


func _scaled_triangle_set(triangles: Array) -> Array:
	var out := []
	for triangle in triangles:
		var scaled := PackedVector3Array()
		for point: Vector3 in triangle: scaled.append(point * 1000.0)
		out.append(scaled)
	return out


func _crosses_mm(a: Array, b: Array) -> bool:
	return Clearance._crosses(_scaled_triangle_set(a), _scaled_triangle_set(b))


func _set_pivot_degrees(pivot: Node3D, rest: Transform3D, degrees: float) -> void:
	var axis: Vector3 = rest.basis.x.normalized()
	pivot.transform = Transform3D(Basis(axis, deg_to_rad(degrees)) * rest.basis, rest.origin)


func _run() -> void:
	var test_surface := PackedVector3Array([Vector3.ZERO, Vector3(0.001, 0, 0), Vector3(0, 0.001, 0)])
	var hit_segment := PackedVector3Array([Vector3(-0.0005, 0.00025, -0.0005), Vector3(0.0005, 0.00025, 0.0005), Vector3(0.0005, 0.00075, 0.0005)])
	var miss_segment := PackedVector3Array([Vector3(0.002, 0.00025, -0.0005), Vector3(0.003, 0.00025, 0.0005), Vector3(0.003, 0.00075, 0.0005)])
	_check("mm crossing predicate detects a 1 mm triangle/segment hit", _crosses_mm([hit_segment], [test_surface]))
	_check("mm crossing predicate rejects a 1 mm miss fixture", not _crosses_mm([miss_segment], [test_surface]))
	var airplane := Timber.build()
	get_root().add_child(airplane.root)
	await process_frame
	var meshes := {}
	Clearance._collect(airplane.root, meshes)
	_check("r2 has no merged airframe mesh", not meshes.has("airframe"))
	var t := Timber.manual_throws_deg()
	var articulations: Dictionary = Timber.TimberGeometry.DATA.articulations
	var user_args := OS.get_cmdline_user_args()
	var run_controls := not user_args.has("gear-only")
	var run_gear := user_args.has("gear-only") or (not user_args.has("manual-aileron-only") and not user_args.has("crossings-only"))
	var crossings_only := user_args.has("crossings-only")
	var poses := [
		["aileron manual +%.1f" % t.aileron, {aileron_right = t.aileron, aileron_left = -t.aileron}, 0.0, ["aileron_right", "aileron_left"], true],
		["aileron manual -%.1f" % t.aileron, {aileron_right = -t.aileron, aileron_left = t.aileron}, 0.0, ["aileron_right", "aileron_left"], true],
		["elevator manual +%.1f" % t.elevator, {elevator = t.elevator}, 0.0, ["elevator"], true],
		["elevator manual -%.1f" % t.elevator, {elevator = -t.elevator}, 0.0, ["elevator"], true],
		["rudder manual +%.1f" % t.rudder, {rudder = t.rudder}, 0.0, ["rudder"], true],
		["rudder manual -%.1f" % t.rudder, {rudder = -t.rudder}, 0.0, ["rudder"], true],
		["flaps manual full %.1f" % float(Timber.TimberGeometry.DATA.controls.flap.full_deg.value), {}, float(Timber.TimberGeometry.DATA.controls.flap.full_deg.value), ["flap_right", "flap_left"], true],
		["ailerons authored ±22°", {aileron_right = 22.0, aileron_left = -22.0}, 0.0, ["aileron_right", "aileron_left"], true],
		["elevator authored +22°", {elevator = 22.0}, 0.0, ["elevator"], true],
		["elevator authored -22°", {elevator = -22.0}, 0.0, ["elevator"], true],
		["rudder authored +30°", {rudder = 30.0}, 0.0, ["rudder"], true],
		["rudder authored -30°", {rudder = -30.0}, 0.0, ["rudder"], true],
		["flaps supplier limit 40°", {}, float(articulations.flap_right_hinge.range_deg[1]), ["flap_right", "flap_left"], false],
	]
	if user_args.has("manual-aileron-only"):
		poses = poses.slice(0, 2)
	var t0 := Time.get_ticks_msec()
	var minimum := INF
	if run_controls:
		for pose in poses:
			Timber.apply_surfaces(airplane, pose[1])
			Timber.set_flaps(airplane, pose[2])
			for moving in pose[3]:
				var fixed := String(FIXED_FOR_MOVING[moving])
				var result := _pair(airplane, meshes, String(moving), fixed, not crossings_only)
				if not is_nan(float(result.gap_m)): minimum = minf(minimum, result.gap_m)
				if bool(pose[4]):
					var clear: bool = not result.crosses and (crossings_only or result.gap_m > 0.0)
					var wording := "has no surface crossing" if crossings_only else "has no surface crossing with positive gap"
					_check("%s: %s %s from %s" % [pose[0], moving, wording, fixed], clear,
						"%d fixed triangles nearby; gap %s" % [result.near, _gap_label(result.gap_m)])
				else:
					if not crossings_only:
						_check("%s: near-seam endpoint is recorded for %s" % [pose[0], fixed], result.crosses or result.gap_m <= SEAM_GAP_M,
							"%d fixed triangles nearby; gap %s" % [result.near, _gap_label(result.gap_m)])
				var status := "surface crossing" if result.crosses else ("no surface crossing" if crossings_only else ("near seam" if result.gap_m < SEAM_GAP_M else "clear"))
				print("%s | %s vs %s | %s | gap %s | %d fixed triangles nearby | %d ms" % [pose[0], moving, fixed,
					status, _gap_label(result.gap_m), result.near, Time.get_ticks_msec() - t0])
	Timber.apply_surfaces(airplane, {})
	Timber.set_flaps(airplane, 0.0)
	# The importer has one mesh per leg that combines the strut and wire link, while fuselage_core combines the bracket
	# and fuselage. Their mechanical attachment overlap is not an isolated wire-vs-bracket clearance measurement.
	# Keep the old 0°/6°/7° pair as a non-gating observation and verify only that the probe restores the exact pose.
	if run_gear:
		print("GEAR OBSERVATION ONLY: merged leg/wire and body/bracket meshes include intended attachment overlaps; these pairs do not qualify the supplier's >6° wire clearance.")
		var suspension_pairs := [["left", "gear_left_suspension", "gear_left_leg"], ["right", "gear_right_suspension", "gear_right_leg"]]
		for pair in suspension_pairs:
			var pivot := airplane.root.find_child(String(pair[1]), true, false) as Node3D
			var rest: Transform3D = pivot.transform
			for angle in [0.0, 6.0, 7.0]:
				_set_pivot_degrees(pivot, rest, angle)
				var result := _pair(airplane, meshes, String(pair[2]), "fuselage_core", not crossings_only)
				print("GEAR UNQUALIFIED %s %.0f°: gear_leg vs fuselage_core | %s | gap %s | %d fixed triangles nearby" % [pair[0], angle,
					"surface crossings" if result.crosses else ("gap not recomputed" if crossings_only else ("near seam" if result.gap_m < SEAM_GAP_M else "no crossing")), _gap_label(result.gap_m), result.near])
			pivot.transform = rest
			_check("%s suspension diagnostic restores imported pose exactly" % pair[0], pivot.transform == rest)
	var minimum_text := "n/a" if minimum == INF else "%.4f m" % minimum
	print("verify_timber_clearance: %d checks, %d failed, smallest gap %s (%d ms)%s" % [_checks, _failures, minimum_text, Time.get_ticks_msec() - t0, "" if _failures == 0 else " FAIL"])
	quit(1 if _failures > 0 else 0)
