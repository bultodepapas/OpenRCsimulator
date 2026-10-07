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


func _initialize() -> void:
	var cal := RcCalibration.new()
	var rest := _axes(0, 0, 0, 0)
	_check("starts at the rest step", "1/5" in cal.prompt() and "LOW" in cal.prompt(), cal.prompt())
	cal.advance(rest)
	_sweep(cal, [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("throttle found on axis 4, reversed", cal.profile.throttle.axis == 4 and cal.profile.throttle.invert, str(cal.profile.get("throttle")))
	# Enter without moving anything: rejected, same step.
	cal.advance(rest)
	_check("no movement → error, stays on the step", cal.error != "" and "3/5" in cal.prompt(), cal.error)
	_sweep(cal, [[0, 0, 0, 0], [0, 1, 0, 0], [0, -1, 0, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("aileron on axis 6, not inverted", cal.profile.roll.axis == 6 and not cal.profile.roll.invert, str(cal.profile.get("roll")))
	_sweep(cal, [[0, 0, 0, 0], [0, 0, 1, 0], [0, 0, -1, 0], [0, 0, 0, 0]])
	cal.advance(rest)
	_check("elevator on axis 1, inverted (stick back reads −)", cal.profile.pitch.axis == 1 and cal.profile.pitch.invert, str(cal.profile.get("pitch")))
	# Rudder moved LEFT first: the wizard believes the prompt (RIGHT first) and records an inversion.
	_sweep(cal, [[0, 0, 0, 0], [0, 0, 0, -1], [0, 0, 0, 1], [0, 0, 0, 0]])
	var finished := cal.advance(rest)
	_check("rudder on axis 0; moved left first → inverted", cal.profile.yaw.axis == 0 and cal.profile.yaw.invert, str(cal.profile.get("yaw")))
	_check("wizard finished with a valid profile", finished and cal.done() and RcCalibration.valid(cal.profile))

	# The calibrated profile reproduces the pilot's sticks exactly (except the deliberately reversed rudder).
	var r := RcInput.new()
	r.connect_device(1, { name = "Odd radio" }, cal.profile)
	r.on_motion(1, 4, 0.9)
	for stick in [[0.0, 0.0, 0.0, 0.0], [0.5, 0.5, -0.25, 0.3], [1.0, -1.0, 1.0, -1.0]]:
		r.poll(func(_d: int, axis: int) -> float: return _axes(stick[0], stick[1], stick[2], stick[3])[axis], 1.0 / 240.0)
		var s := r.sticks()
		_check("calibrated sticks %s" % [stick], absf(r.throttle_position() - stick[0]) < 1e-9 and absf(s.roll - stick[1]) < 1e-9 and absf(s.pitch - stick[2]) < 1e-9 and absf(s.yaw + stick[3]) < 1e-9, str([r.throttle_position(), s]))
	_check("a calibrated radio arms on its own low throttle", r.armed)

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
