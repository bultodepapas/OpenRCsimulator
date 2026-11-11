# D6b: the radio calibration wizard and the saved profiles (pure, no device).
# Run: godot --headless --path . --script res://tests/test_rc_calibration.gd
extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const TMP := "user://test_rc_calibration.cfg"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Raw axes for a radio whose layout is unusual: yaw on axis 0, pitch on 1 (stick back = −), throttle on 4 reversed
## (low = +0.9), roll on 6 with an off-centre rest (+0.05) and short endpoints (−0.8…+0.9). Others idle at 0.
func _axes(throttle: float, roll: float, pitch: float, yaw: float) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(RcInput.AXES)
	a[0] = yaw
	a[1] = -pitch
	a[4] = 0.9 - 1.8 * throttle # throttle 0 → +0.9, 1 → −0.9
	a[6] = 0.05 + (roll * 0.85 if roll >= 0.0 else roll * 0.85) # −0.8 … +0.9 around +0.05
	return a


## Feeds a sweep through `points` (each [throttle, roll, pitch, yaw]) in small steps, like a pilot moving a stick.
func _sweep(cal: RcCalibration, points: Array) -> void:
	for k in range(1, points.size()):
		for i in 20:
			var t := float(i + 1) / 20.0
			var p: Array = points[k - 1]
			var q: Array = points[k]
			cal.sample(_axes(lerpf(p[0], q[0], t), lerpf(p[1], q[1], t), lerpf(p[2], q[2], t), lerpf(p[3], q[3], t)))


func _direction_case(center: float, requested: float, opposite: float) -> void:
	var cal := RcCalibration.new()
	var rest := PackedFloat64Array()
	rest.resize(RcInput.AXES)
	rest[4] = -0.8
	rest[6] = center
	cal.advance(rest)
	var throttle := rest.duplicate()
	throttle[4] = 0.8
	cal.sample(throttle)
	cal.advance(rest)
	var held := rest.duplicate()
	held[6] = center + requested
	cal.advance(held)
	_check("direction confirms held axis and shows the opposite prompt", cal.step == 2 and "LEFT" in cal.instruction() and not cal.profile.has("roll"), cal.error)
	var other := rest.duplicate()
	other[6] = center + opposite
	cal.sample(other)
	cal.advance(rest)
	var mapped: Dictionary = cal.profile.get("roll", {})
	_check("reduced/asymmetric held direction %s/%s at %s" % [requested, opposite, center], \
		cal.step == 3 and not mapped.is_empty() and mapped.invert == (requested < 0.0) \
		and is_equal_approx(RcInput.normalize(center + requested, mapped), 1.0) \
		and is_equal_approx(RcInput.normalize(center + opposite, mapped), -1.0), str(mapped))


func _initialize() -> void:
	var cal := RcCalibration.new()
	var rest := _axes(0, 0, 0, 0)
	_check("starts at the rest step", "1/5" in cal.prompt() and "EXCEPT the THROTTLE" in cal.prompt() and "fully DOWN" in cal.prompt(), cal.prompt())
	cal.advance(rest)
	_sweep(cal, [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("throttle found on axis 4, reversed", cal.profile.throttle.axis == 4 and cal.profile.throttle.invert, str(cal.profile.get("throttle")))
	# Enter without moving anything: rejected, same step.
	cal.advance(rest)
	_check("no movement → error, stays on the step", cal.error != "" and "3/5" in cal.prompt(), cal.error)
	_sweep(cal, [[0, 0, 0, 0], [0, 1, 0, 0]])
	cal.advance(_axes(0, 1, 0, 0))
	_sweep(cal, [[0, 1, 0, 0], [0, -1, 0, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("aileron on axis 6, not inverted", cal.profile.roll.axis == 6 and not cal.profile.roll.invert, str(cal.profile.get("roll")))
	_sweep(cal, [[0, 0, 0, 0], [0, 0, 1, 0]])
	cal.advance(_axes(0, 0, 1, 0))
	_sweep(cal, [[0, 0, 1, 0], [0, 0, -1, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("elevator on axis 1, inverted (stick back reads −)", cal.profile.pitch.axis == 1 and cal.profile.pitch.invert, str(cal.profile.get("pitch")))
	# The requested RIGHT direction reports a negative axis on this fixture.
	_sweep(cal, [[0, 0, 0, 0], [0, 0, 0, -1]])
	cal.advance(_axes(0, 0, 0, -1))
	_sweep(cal, [[0, 0, 0, -1], [0, 0, 0, 1], [0, 0, 0, 0]])
	var finished := cal.advance(rest)
	_check("rudder on axis 0; right reports negative → inverted", cal.profile.yaw.axis == 0 and cal.profile.yaw.invert, str(cal.profile.get("yaw")))
	_check("wizard finished with a valid profile", finished and cal.done() and RcCalibration.valid(cal.profile))

	# A competing sweep used to silently win the throttle step (and could map yaw as throttle).
	var mixed := RcCalibration.new()
	mixed.advance(rest)
	_sweep(mixed, [[0, 0, 0, 0], [0.5, 0, 0, 1], [0, 0, 0, 0]])
	mixed.advance(rest)
	_check("mixed throttle and yaw motion is rejected", mixed.step == 1 and not mixed.profile.has("throttle") and "one axis" in mixed.error, mixed.error)
	mixed.sample(rest)
	_check("a rejected step remains readable during later sampling", "one axis" in mixed.error, mixed.error)
	var wrong_axis := RcCalibration.new()
	wrong_axis.advance(rest)
	_sweep(wrong_axis, [[0, 0, 0, 0], [0, 0, 0, 1], [0, 0, 0, 0]])
	wrong_axis.advance(rest)
	_sweep(wrong_axis, [[0, 0, 0, 0], [0, 0, 0, 1], [0, 0, 0, 0]])
	wrong_axis.advance(rest)
	_check("reusing a mistaken throttle axis explains the conflict", wrong_axis.step == 2 and "already assigned" in wrong_axis.error, wrong_axis.error)
	var half_throttle := RcCalibration.new()
	half_throttle.advance(rest)
	_sweep(half_throttle, [[0, 0, 0, 0], [1, 0, 0, 0]])
	half_throttle.advance(_axes(0.5, 0, 0, 0))
	_check("throttle must return to its recorded low before assignment", half_throttle.step == 1 and not half_throttle.profile.has("throttle") and "LOW" in half_throttle.error, half_throttle.error)
	var short_travel := RcCalibration.new()
	short_travel.advance(rest)
	_sweep(short_travel, [[0, 0, 0, 0], [0.5, 0, 0, 0]])
	short_travel.advance(_axes(0.06, 0, 0, 0))
	_check("short-travel throttle return uses calibrated percentage", short_travel.step == 1 and not short_travel.profile.has("throttle") and "LOW" in short_travel.error, short_travel.error)
	var off_center := RcCalibration.new()
	off_center.advance(rest)
	_sweep(off_center, [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	off_center.advance(rest)
	_sweep(off_center, [[0, 0, 0, 0], [0, 1, 0, 0]])
	off_center.advance(_axes(0, 1, 0, 0))
	_sweep(off_center, [[0, 1, 0, 0], [0, -1, 0, 0]])
	off_center.advance(_axes(0, 0.12, 0, 0))
	_check("centered channel must return to rest before assignment", off_center.step == 2 and not off_center.profile.has("roll") and "centre" in off_center.error, off_center.error)

	# The calibrated profile reproduces the pilot's sticks exactly (including the negative-reading rudder).
	var r := RcInput.new()
	r.connect_device(1, { name = "Odd radio" }, cal.profile)
	r.on_motion(1, 4, 0.9)
	for stick in [[0.0, 0.0, 0.0, 0.0], [0.5, 0.5, -0.25, 0.3], [1.0, -1.0, 1.0, -1.0]]:
		r.poll(func(_d: int, axis: int) -> float: return _axes(stick[0], stick[1], stick[2], stick[3])[axis], 1.0 / 240.0)
		var s := r.sticks()
		_check("calibrated sticks %s" % [stick], absf(r.throttle_position() - stick[0]) < 1e-9 and absf(s.roll - stick[1]) < 1e-9 and absf(s.pitch - stick[2]) < 1e-9 and absf(s.yaw + stick[3]) < 1e-9, str([r.throttle_position(), s]))
	_check("a calibrated radio arms on its own low throttle", r.armed)
	_direction_case(0.0, -0.2, 0.3)
	_direction_case(0.0, 0.2, -0.3)
	_direction_case(0.0, -0.25, 0.25)
	_direction_case(0.0, 0.25, -0.25)
	_direction_case(0.03, -0.22, 0.35)
	_direction_case(-0.04, 0.22, -0.35)

	var ambiguous := RcCalibration.new()
	ambiguous.advance(rest)
	_sweep(ambiguous, [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	ambiguous.advance(rest)
	_sweep(ambiguous, [[0, 0, 0, 0], [0, -0.25, 0, 0], [0, 0.35, 0, 0], [0, 0, 0, 0]])
	ambiguous.advance(rest)
	_check("a completed sweep cannot replace held direction confirmation", ambiguous.step == 2 and not ambiguous.profile.has("roll") and "Hold" in ambiguous.error, ambiguous.error)
	var competing := _axes(0, 0.5, 0.5, 0)
	ambiguous.advance(competing)
	_check("simultaneously held axes cannot establish direction", ambiguous.step == 2 and not ambiguous.profile.has("roll") and "one axis" in ambiguous.error, ambiguous.error)

	# One-way or off-centre sweeps are rejected for centred sticks.
	var c2 := RcCalibration.new()
	c2.advance(rest)
	_sweep(c2, [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	c2.advance(rest)
	_sweep(c2, [[0, 0, 0, 0], [0, 1, 0, 0]]) # right only, Enter while still deflected... rest stays centred
	c2.advance(rest)
	_check("aileron moved one way only → error", c2.error != "" and c2.profile.get("roll") == null, c2.error)

	# Saved per device key; other devices and broken files give nothing.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_check("no file → no profile", RcCalibration.load_profile(TMP, "k1").is_empty())
	_check("saves", RcCalibration.save_profile(TMP, "guid|1209:4f54|EdgeTX [x]", cal.profile) == OK)
	RcCalibration.save_profile(TMP, "other", RcInput.DEFAULT_PROFILE)
	var back := RcCalibration.load_profile(TMP, "guid|1209:4f54|EdgeTX [x]")
	_check("round trip keeps the profile", back == cal.profile, str(back))
	_check("each device keeps its own", RcCalibration.load_profile(TMP, "other").roll.axis == 0)
	_check("unknown device → none", RcCalibration.load_profile(TMP, "nobody").is_empty())
	var broken := cal.profile.duplicate(true)
	broken.roll.axis = 12
	_check("invalid calibration is refused before saving", RcCalibration.save_profile(TMP, "broken", broken) == ERR_INVALID_DATA)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(TMP)
	cfg.set_value("broken".md5_text(), "device_key", "broken")
	cfg.set_value("broken".md5_text(), "profile", broken)
	cfg.save(TMP) # emulate an invalid on-disk profile without going through the writer
	_check("an invalid saved profile is ignored (axis 12)", RcCalibration.load_profile(TMP, "broken").is_empty())
	# (A corrupt file also returns {} via ConfigFile.load != OK, but Godot prints a parse ERROR, which test.sh
	# rightly treats as a failure, so that case is not exercised here.)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
