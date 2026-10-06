# D3: the six-axis aero model — hand-computed loads, control signs through the real command path,
# stability and damping signs, and finite output everywhere.
# Run: godot --headless --path . --script res://tests/test_aero.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Commands := preload("res://input/commands.gd")

var _failures := 0
var _count := 0
var _model: Dictionary


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Loads for body velocity, rates and pilot commands {roll, pitch, yaw} (−1…1).
func _loads(vel: Array, rates := [0.0, 0.0, 0.0], cmd := {}) -> PackedFloat64Array:
	var s := RB.make_state(M.v3(0, 0, -20), M.v3(vel[0], vel[1], vel[2]), M.q_identity(), M.v3(rates[0], rates[1], rates[2]))
	var c := Commands.neutral_commands()
	c.merge(cmd, true)
	var d := Aero.deflections_from_surfaces(Commands.surface_deflections_deg(c))
	return Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), d, _model, Air.RHO_SEA_LEVEL)


func _initialize() -> void:
	_model = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var a: Dictionary = _model.aero
	var S := 0.464515
	var c := 0.3048

	# 1. Hand-computed loads, level at 15 m/s, controls neutral (independent arithmetic, not the implementation).
	var qbar := 0.5 * 1.225 * 225.0
	var cl: float = a.CL0
	var cd: float = a.CD0 + a.k_induced * pow(cl - a.CL_minD, 2)
	var lift := qbar * S * cl
	var drag := qbar * S * cd
	var my_arp: float = qbar * S * c * a.Cm0
	var my_transfer := (-0.07) * (-drag) # r = arp − cg = 0.07 m up → body z = −0.07; (r × F)_y = r_z·F_x
	var f := _loads([15, 0, 0])
	_check("lift = qbar·S·CL0 (Fz = −6.837 N)", absf(f[2] + lift) < 1e-9 and absf(lift - 6.8369) < 1e-3, "%s vs %s" % [f[2], -lift])
	_check("drag = qbar·S·CD (Fx = −2.858 N)", absf(f[0] + drag) < 1e-9 and absf(drag - 2.8576) < 1e-3, "%s vs %s" % [f[0], -drag])
	_check("pitch moment incl. ARP→CG transfer", absf(f[4] - (my_arp + my_transfer)) < 1e-9, "%s vs %s" % [f[4], my_arp + my_transfer])
	_check("symmetric flight: no side force, roll or yaw", absf(f[1]) < 1e-12 and absf(f[3]) < 1e-12 and absf(f[5]) < 1e-12)

	# 2. Control signs through the real pilot command path.
	var base := _loads([15, 0, 0])
	_check("+roll command → right roll moment", _loads([15, 0, 0], [0, 0, 0], { roll = 1.0 })[3] > 0.5)
	_check("+pitch command → nose-up moment", _loads([15, 0, 0], [0, 0, 0], { pitch = 1.0 })[4] > base[4] + 2.0)
	_check("+yaw command → nose-right moment", _loads([15, 0, 0], [0, 0, 0], { yaw = 1.0 })[5] > 0.5)
	# Right rudder deflects the air to the right, so the fin is pushed LEFT: the tail swings left, the nose right.
	_check("+yaw command → fin pushed left (Fy < 0)", _loads([15, 0, 0], [0, 0, 0], { yaw = 1.0 })[1] < 0.0)
	_check("deflections cost drag", _loads([15, 0, 0], [0, 0, 0], { roll = 1.0, yaw = 1.0 })[0] < base[0])
	var d := Aero.deflections_from_surfaces(Commands.surface_deflections_deg({ roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.5 }))
	_check("convention map: elevator TE up 20° → −0.349 rad (TE down positive)", absf(d.elevator + deg_to_rad(20)) < 1e-12)
	_check("convention map: roll right → right TE up (−), left TE down (+)", d.aileron_right < 0 and d.aileron_left > 0)
	_check("convention map: rudder TE right 25° → −0.436 rad (TE left positive)", absf(d.rudder + deg_to_rad(25)) < 1e-12)

	# 3. Static stability: more alpha → nose-down; sideslip from the right → weathervane right, pushed left.
	_check("pitch stiffness (dMy/dα < 0)", _loads([15, 0, 1])[4] < base[4])
	var slip := _loads([15, 2, 0])
	_check("weathervane: β>0 → nose right (Mz > 0)", slip[5] > 0.0)
	_check("side force opposes sideslip (Fy < 0)", slip[1] < 0.0)
	_check("dihedral effect: β>0 → roll left (Mx < 0)", slip[3] < 0.0)

	# 4. Damping opposes rotation.
	_check("roll damping", _loads([15, 0, 0], [1.0, 0, 0])[3] < 0.0)
	_check("pitch damping", _loads([15, 0, 0], [0, 1.0, 0])[4] < base[4])
	_check("yaw damping", _loads([15, 0, 0], [0, 0, 1.0])[5] < 0.0)

	# 5. Finite everywhere: zero airspeed with wild rates, and a full alpha/beta sweep.
	var still := _loads([0, 0, 0], [0.0, 0.0, 0.0], { roll = 1.0, pitch = -1.0, yaw = 1.0 })
	var zero := true
	for i in 6:
		zero = zero and still[i] == 0.0
	_check("zero translation AND rotation → zero loads", zero, str(still))
	var rotating := _loads([0, 0, 0], [5.0, -7.0, 9.0])
	_check("rotating at rest: local surface drag dissipates energy", rotating[3]*5.0 - rotating[4]*7.0 + rotating[5]*9.0 < 0.0, str(rotating))
	var finite := true
	for ai in range(-180, 181, 15):
		for bi in range(-90, 91, 15):
			var u := 20.0 * cos(deg_to_rad(bi)) * cos(deg_to_rad(ai))
			var v := 20.0 * sin(deg_to_rad(bi))
			var w := 20.0 * cos(deg_to_rad(bi)) * sin(deg_to_rad(ai))
			for x in _loads([u, v, w], [2.0, 2.0, 2.0]):
				finite = finite and is_finite(x)
	_check("finite over the full α/β sphere", finite)

	# 6. Predicted roll authority (ROADMAP table): steady roll rate = −Clδa,total / Clp · 2V/b at 20 m/s ≈ 192°/s.
	var mx_cmd := _loads([20, 0, 0], [0, 0, 0], { roll = 1.0 })[3]
	var mx_damp := _loads([20, 0, 0], [1.0, 0, 0])[3] # roll damping per 1 rad/s
	var p_ss := -mx_cmd / mx_damp
	_check("steady full-aileron roll rate ≈ 192°/s at 20 m/s", absf(rad_to_deg(p_ss) - 192.0) < 5.0, "%.1f°/s" % rad_to_deg(p_ss))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
