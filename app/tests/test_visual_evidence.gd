# VQ-01b synthetic poses must be render-only, correctly placed, and unambiguous.
extends SceneTree
const Evidence = preload("res://render/visual_evidence.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	var args: Dictionary = {capture = true, scripted = true, visual_pose = "level", visual_distance = "20", autozoom = "0"}
	check("valid inspection", Evidence.validate_pose(args) == "")
	check("ordinary capture unchanged", Evidence.validate_pose({capture = true}) == "")
	for key in ["capture", "scripted", "visual_pose", "visual_distance", "autozoom"]:
		var bad: Dictionary = args.duplicate()
		bad.erase(key)
		check("missing " + key, Evidence.validate_pose(bad) != "")
	for distance in ["0", "-1", "4.99", "1001", "nan", "inf", "bad"]:
		var bad: Dictionary = args.duplicate()
		bad.visual_distance = distance
		check("bad distance " + distance, Evidence.validate_pose(bad) != "")
	for key in ["inspect", "look_az"]:
		var bad: Dictionary = args.duplicate()
		bad[key] = true
		check("conflicting camera " + key, Evidence.validate_pose(bad) != "")
	var up_vectors: Dictionary = {}
	for pose_name in Evidence.POSES:
		for distance in [20.0, 50.0, 100.0]:
			var pose: Dictionary = Evidence.synthetic_pose(pose_name, distance, 1.7)
			check("distance " + pose_name, absf(pose.pos.distance_to(Vector3(0, 1.7, 0)) - distance) < 0.0001)
			check("proper rotation " + pose_name, absf(pose.basis.determinant() - 1.0) < 0.000001)
			var nose: Vector3 = pose.basis * Vector3.FORWARD
			if pose_name == "climb":
				check("climb nose rises", nose.y > 0.7)
			if pose_name == "dive":
				check("dive nose falls", nose.y < -0.7)
			up_vectors[pose_name] = pose.basis * Vector3.UP
	check("inverted underside up", up_vectors.inverted.y < -0.99)
	check("opposite knife attitudes", up_vectors.knife_left.dot(up_vectors.knife_right) < -0.99)
	var provenance: Dictionary = Evidence.provenance()
	check("actual source hash", provenance.source_sha256["res://main.gd"] == FileAccess.get_sha256("res://main.gd"))
	check("root flight scene in provenance", provenance.source_sha256["res://main.tscn"] == FileAccess.get_sha256("res://main.tscn"))
	check("entry scene in provenance", provenance.source_sha256["res://app_root.tscn"] == FileAccess.get_sha256("res://app_root.tscn"))
	check("atmosphere fixture in provenance", provenance.source_sha256.has("res://tests/fixtures/atmosphere_field.gd"))
	check("ground shader in provenance", provenance.source_sha256.has("res://render/ground.gdshader"))
	print("visual evidence: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
