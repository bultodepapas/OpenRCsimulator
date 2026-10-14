# HUD-01/08/09: overlay telemetry and warnings (render/overlays/telemetry.gd) on hand-computed attitudes and loads.
# Run: godot --headless --path . --script res://tests/test_overlay_telemetry.gd
extends SceneTree

const Telemetry := preload("res://render/overlays/telemetry.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Air := preload("res://physics/air_data.gd")

const MASS := 2.5
const G := 9.80665

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(a: float, b: float, tol := 1e-9) -> bool:
	return absf(a - b) <= tol


func _state(pos: Array, vel_body: Array, yaw: float, pitch: float, roll: float) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(RB.SIZE)
	for i in 3:
		s[RB.POS + i] = pos[i]
		s[RB.VEL + i] = vel_body[i]
	var q := M.q_from_euler(yaw, pitch, roll)
	for i in 4:
		s[RB.ATT + i] = q[i]
	return s


func _telemetry(s: PackedFloat64Array, wind: PackedFloat64Array, ctx := {}) -> Dictionary:
	var full := { pilot_ned = [0.0, 0.0, -1.7], terrain_up = 0.0, mass = MASS, gravity = G, throttle = 0.5, time_s = 12.0,
		last_loads = PackedFloat64Array([0.0, 0.0, -MASS * G, 0.0, 0.0, 0.0]) }
	full.merge(ctx, true)
	return Telemetry.compute(s, wind, Air.compute(s, wind), full)


func _initialize() -> void:
	var calm := M.v3(0.0, 0.0, 0.0)
	# Level flight north at 20 m/s, 50 m up, 100 m north of a pilot whose eye is 1.7 m above the datum.
	var level := _telemetry(_state([100.0, 0.0, -50.0], [20.0, 0.0, 0.0], 0.0, 0.0, 0.0), calm)
	_check("level: airspeed 20", _near(level.airspeed, 20.0))
	_check("level: ground speed 20, no vertical speed", _near(level.ground_speed, 20.0) and _near(level.vertical_speed, 0.0))
	_check("level: height 50 above datum and ground", _near(level.height_datum, 50.0) and _near(level.height_agl, 50.0))
	_check("level: slant distance to the pilot's eye", _near(level.distance_pilot, sqrt(100.0 * 100.0 + 48.3 * 48.3), 1e-9))
	_check("level: load factor 1 from lift = weight", _near(level.load_factor, 1.0))
	_check("level: heading 000, no pitch or bank", _near(level.heading_deg, 0.0) and _near(level.pitch_deg, 0.0) and _near(level.bank_deg, 0.0))
	_check("level: throttle and time pass through", level.throttle == 0.5 and level.time_s == 12.0)
	_check("calm: no wind bearing", is_nan(level.wind_from_deg) and level.wind_speed == 0.0)

	# Climbing 30° at α = 0: vertical speed V sin 30°, ground speed V cos 30°; uses world vertical, not body w.
	var climb := _telemetry(_state([0.0, 0.0, -20.0], [10.0, 0.0, 0.0], 0.0, deg_to_rad(30.0), 0.0), calm)
	_check("30° climb: vertical speed +5", _near(climb.vertical_speed, 5.0, 1e-12), "%.15f" % climb.vertical_speed)
	_check("30° climb: ground speed 8.660", _near(climb.ground_speed, 10.0 * cos(deg_to_rad(30.0)), 1e-12))
	_check("30° climb: pitch 30°, α 0", _near(climb.pitch_deg, 30.0, 1e-9) and _near(climb.alpha_deg, 0.0, 1e-12))

	# Steady level 60° banked turn heading east: lift = W / cos 60° = 2 W, so n = 2.
	var turn := _telemetry(_state([0.0, 0.0, -30.0], [15.0, 0.0, 0.0], deg_to_rad(90.0), 0.0, deg_to_rad(60.0)), calm,
		{ last_loads = PackedFloat64Array([0.0, 0.0, -2.0 * MASS * G, 0.0, 0.0, 0.0]) })
	_check("60° turn: load factor 2", _near(turn.load_factor, 2.0))
	_check("60° turn: heading 090, bank 60°", _near(turn.heading_deg, 90.0, 1e-9) and _near(turn.bank_deg, 60.0, 1e-9))

	# Height above ground follows the terrain under the aircraft.
	var hill := _telemetry(_state([0.0, 0.0, -30.0], [15.0, 0.0, 0.0], 0.0, 0.0, 0.0), calm, { terrain_up = 12.5 })
	_check("terrain: AGL = datum height − ground height", _near(hill.height_agl, 17.5) and _near(hill.height_datum, 30.0))

	# Wind: a north wind blows toward the south; looking north the arrow points down the screen, looking east it points right.
	var windy := _telemetry(_state([0.0, 0.0, -30.0], [15.0, 0.0, 0.0], 0.0, 0.0, 0.0), M.v3(-3.0, 0.0, -1.0))
	_check("wind: from 000 at 3 m/s, updraft +1", _near(windy.wind_from_deg, 0.0) and _near(windy.wind_speed, 3.0) and _near(windy.wind_up, 1.0))
	_check("wind arrow: looking north, toward the pilot", _near(Telemetry.wind_arrow_deg(0.0, 0.0), 180.0))
	_check("wind arrow: looking east, to the right", _near(Telemetry.wind_arrow_deg(0.0, 90.0), 90.0))
	_check("render forward −z is north", _near(Telemetry.heading_of_render_forward(0.0, -1.0), 0.0))
	_check("render forward +x is east", _near(Telemetry.heading_of_render_forward(1.0, 0.0), 90.0))

	# FAR: span 1.524 m at the 6° minimum FOV is 30 px tall on 720 px at 1.524·720 / (2·tan 3°·30) m.
	var far := Telemetry.far_distance(1.524)
	_check("far distance of the Stik span ≈ 348.9 m", _near(far, 1.524 * 720.0 / (2.0 * tan(deg_to_rad(3.0)) * 30.0), 1e-6), "%.3f" % far)

	# Warnings.
	var base := { airspeed = 15.0, alpha_deg = 0.0, height_agl = 40.0, vertical_speed = 0.0, distance_pilot = 80.0 }
	var ctx := { stall_pos_deg = 12.0, stall_neg_deg = 10.0, span = 1.524 }
	_check("no warning in normal flight", Telemetry.warnings(base, ctx).is_empty())
	_check("STALL within 2° of the positive stall start", Array(Telemetry.warnings(_with(base, { alpha_deg = 10.5 }), ctx)) == ["stall"])
	_check("no STALL below the margin", Telemetry.warnings(_with(base, { alpha_deg = 9.0 }), ctx).is_empty())
	_check("STALL within 2° of the negative stall start", Array(Telemetry.warnings(_with(base, { alpha_deg = -8.5 }), ctx)) == ["stall"])
	_check("no STALL on the wheels", Telemetry.warnings(_with(base, { alpha_deg = 14.0, height_agl = 0.3 }), ctx).is_empty())
	_check("no STALL when the aircraft gives no stall angle", Telemetry.warnings(_with(base, { alpha_deg = 14.0 }), { span = 1.524 }).is_empty())
	_check("LOW: 5 m up sinking 3 m/s (ground in < 2 s)", Array(Telemetry.warnings(_with(base, { height_agl = 5.0, vertical_speed = -3.0 }), ctx)) == ["low"])
	_check("no LOW on a 1.5 m/s approach", Telemetry.warnings(_with(base, { height_agl = 2.0, vertical_speed = -1.5 }), ctx).is_empty())
	_check("FAR beyond the readable distance", Array(Telemetry.warnings(_with(base, { distance_pilot = far + 1.0 }), ctx)) == ["far"])
	_check("SAFE: radio connected, not armed", Array(Telemetry.warnings(base, _with(ctx, { radio_connected = true, armed = false }))) == ["safe"])
	_check("gamepad neutral prompt is distinct from radio throttle-low", Array(Telemetry.warnings(base, _with(ctx, { radio_connected = true, armed = false, controller_kind = "gamepad" }))) == ["gamepad_safe"])
	_check("lost selection requests explicit controller recovery", Array(Telemetry.warnings(base, _with(ctx, { controller_lost = true, pause_reason = "radio disconnected" }))) == ["controller_lost"])
	_check("no SAFE when armed", Telemetry.warnings(base, _with(ctx, { radio_connected = true, armed = true })).is_empty())
	_check("FAILSAFE on radio disconnection", Array(Telemetry.warnings(base, _with(ctx, { pause_reason = "radio disconnected" }))) == ["failsafe"])
	_check("BATTERY below 20 %", Array(Telemetry.warnings(base, _with(ctx, { battery = { ok = true, soc = 0.15, exhausted = false } }))) == ["battery"])
	_check("no BATTERY without a modelled battery", Telemetry.warnings(base, _with(ctx, { battery = {} })).is_empty())
	_check("EXPERIMENTAL is listed", Array(Telemetry.warnings(base, _with(ctx, { experimental = true }))) == ["experimental"])
	_check("order: failsafe before stall", Array(Telemetry.warnings(_with(base, { alpha_deg = 11.0 }), _with(ctx, { pause_reason = "radio disconnected" }))) == ["failsafe", "stall"])
	print("overlay telemetry: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _with(d: Dictionary, changes: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out.merge(changes, true)
	return out
