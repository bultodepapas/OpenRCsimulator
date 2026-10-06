# P51-04 / V01: clearances of the P-51D's rudder and elevators against their fixed neighbours, with the Extra's generic
# mesh-pair checker (EX-04) at the extreme poses: both surfaces at the flown throws (data file) and at 45 deg. Its own
# script because each pose and pair costs ~5 s on these lofts; test.sh gives every script 60 s.
# Run: godot --headless --path app --script res://aircraft/verify_p51_clearance.gd
extends SceneTree

const P51 := preload("res://aircraft/p51d_model.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const PAIRS := [["rudder", "fin"], ["elevator_right", "stab"], ["elevator_left", "stab"]]
const MINIMUM_GAP_M := 0.0005

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane := P51.build()
	get_root().add_child(airplane.root)
	var flown := P51.manual_throws_deg()
	var big := {aileron = flown.aileron, elevator = 45.0, rudder = 45.0}
	var table := {}
	Clearance._collect(airplane.root, table)
	var t0 := Time.get_ticks_msec()
	for pose_case in [[-1.0, -1.0, flown, "flown"], [1.0, 1.0, big, "45 deg"]]:
		var pose := Clearance._pose(airplane, table, {roll = 0.0, pitch = pose_case[0], yaw = pose_case[1], throttle = 0.0}, pose_case[2], PAIRS)
		for pair in pose.pairs:
			_check("%s vs %s at pitch %+.0f yaw %+.0f (%s): no penetration" % [pair.a, pair.b, pose_case[0], pose_case[1], pose_case[3]], not pair.penetrates)
			_check("%s vs %s (%s): gap >= %.1f mm" % [pair.a, pair.b, pose_case[3], MINIMUM_GAP_M * 1000.0], pair.gap_m >= MINIMUM_GAP_M, "%.4f m" % pair.gap_m)
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}, flown))
	print("verify_p51_clearance: %d checks, %d failed (%d ms)%s" % [_checks, _failures, Time.get_ticks_msec() - t0, "" if _failures == 0 else " FAIL"])
	quit(1 if _failures > 0 else 0)
