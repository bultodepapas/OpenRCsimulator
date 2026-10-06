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
	# L6c: the game's view (auto-zoom) is a declared case, never an implicit default.
	var game_view: Dictionary = args.duplicate()
	game_view.autozoom = "1"
	check("explicit game view accepted", Evidence.validate_pose(game_view) == "")
	for autozoom in ["2", "on", "true", ""]:
		var bad: Dictionary = args.duplicate()
		bad.autozoom = autozoom
		check("ambiguous autozoom " + autozoom, Evidence.validate_pose(bad) != "")
	for elevation in ["-2", "-0.5", "1.6", "10", "45"]:
		var ok_args: Dictionary = args.duplicate()
		ok_args.visual_elevation = elevation
		check("elevation " + elevation, Evidence.validate_pose(ok_args) == "")
	for elevation in ["-2.01", "45.01", "nan", "inf", "bad", ""]:
		var bad: Dictionary = args.duplicate()
		bad.visual_elevation = elevation
		check("bad elevation " + elevation, Evidence.validate_pose(bad) != "")
	for azimuth in ["0", "30", "359.9"]:
		var ok_args: Dictionary = args.duplicate()
		ok_args.visual_azimuth = azimuth
		check("azimuth " + azimuth, Evidence.validate_pose(ok_args) == "")
	for azimuth in ["-1", "360", "nan", "bad"]:
		var bad: Dictionary = args.duplicate()
		bad.visual_azimuth = azimuth
		check("bad azimuth " + azimuth, Evidence.validate_pose(bad) != "")
	check("elevation alone needs a pose", Evidence.validate_pose({capture = true, scripted = true, visual_elevation = "1.6", autozoom = "0"}) != "")
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
	# L6c: the defaults reproduce VQ-01b's pose exactly; elevation and azimuth move the airplane where they say.
	var default_pose: Dictionary = Evidence.synthetic_pose("level", 100.0, 1.7)
	var explicit_pose: Dictionary = Evidence.synthetic_pose("level", 100.0, 1.7, 10.0, 0.0)
	check("defaults are VQ-01b's pose", default_pose.pos == explicit_pose.pos and default_pose.basis == explicit_pose.basis)
	check("default pose due north, 10 deg up", absf(default_pose.pos.z + 100.0 * cos(deg_to_rad(10.0))) < 0.0001 and absf(default_pose.pos.y - (1.7 + 100.0 * sin(deg_to_rad(10.0)))) < 0.0001)
	var low: Dictionary = Evidence.synthetic_pose("knife_left", 100.0, 1.7, -0.5)
	check("negative elevation goes below the eyes", absf(low.pos.y - (1.7 - 100.0 * sin(deg_to_rad(0.5)))) < 0.0001 and low.pos.y > 0.5)
	check("distance kept at low elevation", absf(low.pos.distance_to(Vector3(0, 1.7, 0)) - 100.0) < 0.0001)
	check("low pose stays side-on", absf((low.basis * Vector3.FORWARD).x - 1.0) < 0.0001)
	var east: Dictionary = Evidence.synthetic_pose("level", 100.0, 1.7, 1.6, 90.0)
	check("azimuth 90 puts the airplane east", east.pos.x > 99.0 and absf(east.pos.z) < 0.01)
	check("azimuth 90 heads south (nose to the pilot's right)", (east.basis * Vector3.FORWARD).z > 0.999)
	check("azimuth keeps the distance", absf(east.pos.distance_to(Vector3(0, 1.7, 0)) - 100.0) < 0.0001)
	var provenance: Dictionary = Evidence.provenance()
	check("actual source hash", provenance.source_sha256["res://main.gd"] == FileAccess.get_sha256("res://main.gd"))
	check("root flight scene in provenance", provenance.source_sha256["res://main.tscn"] == FileAccess.get_sha256("res://main.tscn"))
	check("entry scene in provenance", provenance.source_sha256["res://app_root.tscn"] == FileAccess.get_sha256("res://app_root.tscn"))
	check("atmosphere fixture in provenance", provenance.source_sha256.has("res://tests/fixtures/atmosphere_field.gd"))
	check("ground shader in provenance", provenance.source_sha256.has("res://render/ground.gdshader"))
	print("visual evidence: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
