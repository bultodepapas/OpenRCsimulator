# NITRO-05: fuel feed pressure at the carburetor (physics/glow/fuel_feed.gd). Analytic head and factor values, the
# optional installation block and its rejections, a bounded same-stage feed/rotation solve, and flights of the MAX-55AX Stik. The fuel feels only the
# non-gravitational acceleration: trimmed level flight runs needled with g_eff = 1 g down; a full-throttle
# acceleration (fuel thrown aft, like a steady up-line) leans the engine, more so with a low tank; a dive that drag
# is slowing richens it; the same head moves the mixture far more at idle than at full throttle (small suction).
# Run: godot --headless --path . --script res://tests/test_glow_fuel_feed.gd
extends SceneTree

const Feed := preload("res://physics/glow/fuel_feed.gd")
const Installation := preload("res://physics/glow/installation.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Session := preload("res://sim/flight_session.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const AIRCRAFT := "res://data/aircraft/stik_glow_55ax_2t.json"
const G := 9.80665

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_analytic()
	_rotation_and_solver()
	_installation()
	_flights()
	print("NITRO-05 fuel feed: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _analytic() -> void:
	var rho := 857.0
	var tank := PackedFloat64Array([0.0, 0.0, 0.0])
	var size := PackedFloat64Array([0.10, 0.05, 0.04])
	# Body FRD: carburetor 0.12 m ahead of the tank centre and 0.03 m above it (z down).
	var carb := PackedFloat64Array([0.12, 0.0, -0.03])
	var level := Feed.head_pa(PackedFloat64Array([0.0, 0.0, G]), 1.0, carb, tank, size, rho)
	_check("level, full tank: the carburetor 1 cm above the surface sees −ρg·0.01 (%.1f Pa)" % level, absf(level - (-rho * G * 0.01)) < 1e-9)
	var half := Feed.head_pa(PackedFloat64Array([0.0, 0.0, G]), 0.5, carb, tank, size, rho)
	_check("level, half tank: the surface drops to the centre, −ρg·0.03", absf(half - (-rho * G * 0.03)) < 1e-9)
	var up := Feed.head_pa(PackedFloat64Array([-G, 0.0, 0.0]), 1.0, carb, tank, size, rho)
	_check("vertical up-line, full tank: fuel lifted over 0.12 − 0.05 m (%.0f Pa)" % up, absf(up - (-rho * G * 0.07)) < 1e-9)
	var up_low := Feed.head_pa(PackedFloat64Array([-G, 0.0, 0.0]), 0.1, carb, tank, size, rho)
	_check("vertical up-line, 10 %% tank: lifted over 0.12 + 0.04 m", absf(up_low - (-rho * G * 0.16)) < 1e-9)
	var dive := Feed.head_pa(PackedFloat64Array([G, 0.0, 0.0]), 1.0, carb, tank, size, rho)
	_check("vertical dive pushes fuel to the carburetor (+%.0f Pa)" % dive, dive > 0.0 and absf(dive - rho * G * 0.17) < 1e-9)
	_check("no apparent gravity, no head", Feed.head_pa(PackedFloat64Array([0.0, 0.0, 0.0]), 0.5, carb, tank, size, rho) == 0.0)
	var feed := {idle_drive_pressure_pa = 1500.0, wot_drive_pressure_pa = 6000.0, rated_rpm = 16000.0}
	_check("idle admission gives the idle drive", Feed.drive_pa(0.0, 3000.0, feed) == 1500.0)
	_check("full admission at rated rpm gives the full-throttle drive", Feed.drive_pa(1.0, 16000.0, feed) == 6000.0)
	_check("the drive never exceeds its full-throttle value", Feed.drive_pa(1.0, 20000.0, feed) == 6000.0)
	_check("needled condition: k = 1", Feed.factor(4000.0, -84.0, -84.0) == 1.0)
	var k := Feed.factor(6000.0, up, level)
	_check("k = sqrt((p + Δp)/(p + Δp_needled)) = %.4f" % k, absf(k - sqrt((6000.0 + up) / (6000.0 + level))) < 1e-12 and k < 1.0)
	_check("a head beyond the drive starves the carburetor (k = 0)", Feed.factor(500.0, -900.0, -84.0) == 0.0)
	_check("flooding is bounded at %.1f" % Feed.MAX_FACTOR, Feed.factor(100.0, 5000.0, 0.0) == Feed.MAX_FACTOR)
	var k_wot := Feed.factor(Feed.drive_pa(1.0, 16000.0, feed), up, level)
	var k_idle := Feed.factor(Feed.drive_pa(0.28, 3000.0, feed), up, level)
	_check("the same up-line head leans the idle far more than full throttle (k %.3f vs %.3f)" % [k_idle, k_wot], 1.0 - k_idle > 3.0 * (1.0 - k_wot))
	var zero_g_feed := {
		carburetor_body_m = carb,
		idle_drive_pressure_pa = 1500.0,
		wot_drive_pressure_pa = 6000.0,
		density_kg_m3 = rho,
		rated_rpm = 16000.0,
	}
	var zero_g := Feed.evaluate(zero_g_feed, PackedFloat64Array([0.0, 0.0, 0.0]), 1.0,
		1.0, 1.0, 0.0, 1.0, 16000.0, tank, size,
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var zero_g_expected := Feed.factor(6000.0, 0.0, level)
	_check("zero-g live stage remains referenced to standard 1 g needle calibration",
		zero_g.get("ok", false) and M.norm(zero_g.g_eff) < 1.0e-12
		and absf(zero_g.needled_head_pa - level) < 1.0e-12
		and absf(zero_g.factor - zero_g_expected) < 1.0e-12 and zero_g.factor > 1.0,
		"%s expected factor=%s" % [str(zero_g), str(zero_g_expected)])
	var zero_context: Dictionary = Feed.prepare_factor_context(zero_g_feed, 1.0, 1.0, 0.0, 1.0, 16000.0, tank, size)
	var zero_factor: float = Feed.factor_for_stage(zero_context, PackedFloat64Array([0.0, 0.0, 0.0]), 1.0,
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("scalar closure candidate matches full zero-g feed evaluation bit-for-bit",
		zero_context.get("ok", false) and zero_factor == zero_g.factor, "candidate=%s full=%s" % [str(zero_factor), str(zero_g.factor)])
	var axial_force := PackedFloat64Array([-19.6133, 0.0, 0.0])
	var wet_pickup := PackedFloat64Array([0.0, 0.0, 0.015])
	var wet_full: Dictionary = Feed.evaluate(zero_g_feed, axial_force, 2.0, 0.4, 0.5, 0.01, 0.4, 5000.0,
		tank, size, PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), wet_pickup)
	var wet_context: Dictionary = Feed.prepare_factor_context(zero_g_feed, 0.4, 0.5, 0.01, 0.4, 5000.0, tank, size)
	var wet_factor: float = Feed.factor_for_stage(wet_context, axial_force, 2.0,
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), wet_pickup)
	_check("scalar closure candidate preserves the submerged pickup result exactly",
		wet_full.get("ok", false) and wet_context.get("ok", false) and wet_factor == wet_full.factor,
		"candidate=%s full=%s" % [str(wet_factor), str(wet_full.get("factor", NAN))])
	var dry_force := PackedFloat64Array([0.0, 0.0, -19.6133])
	var dry_full: Dictionary = Feed.evaluate(zero_g_feed, dry_force, 2.0, 0.05, 0.5, 0.001, 0.4, 5000.0,
		tank, size, PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), wet_pickup)
	var dry_context: Dictionary = Feed.prepare_factor_context(zero_g_feed, 0.05, 0.5, 0.001, 0.4, 5000.0, tank, size)
	var dry_factor: float = Feed.factor_for_stage(dry_context, dry_force, 2.0,
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), wet_pickup)
	_check("scalar closure candidate preserves a dry authored pickup result exactly",
		dry_full.get("ok", false) and dry_context.get("ok", false) and dry_factor == dry_full.factor and dry_factor == 0.0,
		"candidate=%s full=%s" % [str(dry_factor), str(dry_full.get("factor", NAN))])


func _rotation_and_solver() -> void:
	var zero_force := PackedFloat64Array([0.0,0.0,0.0])
	var tank_arm := PackedFloat64Array([1.0,0.0,0.0])
	var yaw_alpha := PackedFloat64Array([0.0,0.0,1.0])
	var no_rotation := PackedFloat64Array([0.0,0.0,0.0])
	var tangential: PackedFloat64Array=Feed.apparent_gravity(zero_force,1.0,tank_arm,yaw_alpha,no_rotation)
	_check("a stationary point under positive yaw acceleration sees the opposite tangential apparent gravity",
		tangential.size()==3 and tangential[0]==0.0 and tangential[1]==-1.0 and tangential[2]==0.0,str(tangential))
	var spin := PackedFloat64Array([0.0,0.0,2.0])
	var centripetal: PackedFloat64Array=Feed.apparent_gravity(zero_force,1.0,tank_arm,no_rotation,spin)
	_check("a stationary point one metre from a 2 rad/s spin axis sees 4 m/s² outward apparent gravity",
		centripetal.size()==3 and absf(centripetal[0]-4.0)<1.0e-12 and centripetal[1]==0.0 and centripetal[2]==0.0,str(centripetal))
	var malformed: PackedFloat64Array=Feed.apparent_gravity(zero_force,0.0,tank_arm,yaw_alpha,no_rotation)
	_check("apparent-gravity calculation refuses zero live mass",malformed.is_empty())

	_solver_calls=0
	var normal: Dictionary=Feed.solve_factor(Callable(self,"_smooth_feed_target"),1.0)
	_check("smooth weak-coupling fixed point resolves to its analytic root",
		normal.get("ok",false) and absf(float(normal.factor)-0.9375)<=Feed.SOLVE_RESIDUAL_TOLERANCE
		and absf(float(normal.residual))<=Feed.SOLVE_RESIDUAL_TOLERANCE,
		"factor=%s residual=%s" % [str(normal.get("factor",NAN)),str(normal.get("residual",NAN))])
	_check("normal feed closure uses a bounded small number of source evaluations",
		_solver_calls==int(normal.get("evaluations",-1)) and _solver_calls<=8,str(_solver_calls))
	var normal_evaluations: int=int(normal.get("evaluations",0))
	_solver_calls=0
	var discontinuous: Dictionary=Feed.solve_factor(Callable(self,"_no_root_feed_target"),1.0)
	_check("discontinuous no-root fixture fails rather than accepting a narrow bracket",
		not discontinuous.get("ok",false) and _solver_calls==int(discontinuous.get("evaluations",-1))
		and _solver_calls<=MAX_FACTOR_SOLVE_EVALUATIONS and float(discontinuous.get("residual",0.0))>Feed.SOLVE_RESIDUAL_TOLERANCE,
		"evaluations=%s residual=%s" % [str(discontinuous.get("evaluations",0)),str(discontinuous.get("residual",NAN))])
	var worst_evaluations: int=int(discontinuous.get("evaluations",0))
	var invalid: Dictionary=Feed.solve_factor(Callable(self,"_invalid_feed_target"),1.0)
	_check("nonfinite endpoint evaluation fails closed",not invalid.get("ok",false))
	print("paired feed-stage work: no-feed path=1 lifecycle evaluation; weak closure=%d; bounded adversarial closure=%d" % [normal_evaluations,worst_evaluations])


const MAX_FACTOR_SOLVE_EVALUATIONS := 2 + 1 + Feed.MAX_SOLVE_ITERATIONS


var _solver_calls: int=0


func _smooth_feed_target(factor: float) -> Dictionary:
	_solver_calls+=1
	return {ok=true,target_factor=0.75+0.2*factor}


func _no_root_feed_target(factor: float) -> Dictionary:
	_solver_calls+=1
	return {ok=true,target_factor=2.0 if factor<1.0 else 0.0}


func _invalid_feed_target(_factor: float) -> Dictionary:
	_solver_calls+=1
	return {ok=true,target_factor=NAN}


func _installation() -> void:
	var loaded: Dictionary = AD.load_file(AIRCRAFT)
	_check("the 55AX Stik loads with its fuel_feed block", loaded.ok and loaded.model.propulsion.glow.has("fuel_feed"), str(loaded.get("errors", [])))
	if not loaded.ok:
		return
	var install: Dictionary = loaded.model.propulsion.glow
	var feed: Dictionary = install.fuel_feed
	var fuel: Dictionary = install.profile.fuel
	_check("premix density comes from the profile's own blend (%.1f kg/m³)" % feed.density_kg_m3, feed.density_kg_m3 == fuel.density_kg_m3 and feed.density_kg_m3 > 800.0 and feed.density_kg_m3 < 900.0)
	_check("the carburetor lies ahead of the tank in body axes", feed.carburetor_body_m[0] > install.tank_position[0])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT))
	var install_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(raw.propulsion.engine.glow_installation))
	var bytes := PackedByteArray()
	var bare: Dictionary = install_raw.duplicate(true)
	bare.erase("fuel_feed")
	var base_model: Dictionary = loaded.model.duplicate(true)
	_check("the block is optional", Installation.prepare_value(bare, raw, base_model, bytes).ok
		and not Installation.prepare_value(bare, raw, base_model, bytes).model.propulsion.glow.has("fuel_feed"))
	var high: Dictionary = install_raw.duplicate(true)
	high.fuel_feed.carburetor_position.value = [-0.24, 0.0, 0.5]
	_check("a carburetor the idle drive cannot feed in level flight is refused", not Installation.prepare_value(high, raw, base_model, bytes).ok)
	var inverted: Dictionary = install_raw.duplicate(true)
	inverted.fuel_feed.wot_drive_pressure_pa.value = 100.0
	_check("a full-throttle drive below the idle drive is refused", not Installation.prepare_value(inverted, raw, base_model, bytes).ok)
	var extra: Dictionary = install_raw.duplicate(true)
	extra.fuel_feed["muffler_pressure_pa"] = extra.fuel_feed.wot_drive_pressure_pa
	_check("unknown fuel_feed fields are refused", not Installation.prepare_value(extra, raw, base_model, bytes).ok)
	var unsourced: Dictionary = install_raw.duplicate(true)
	unsourced.fuel_feed.idle_drive_pressure_pa.source = " "
	_check("an unsourced pressure is refused", not Installation.prepare_value(unsourced, raw, base_model, bytes).ok)


## One airborne 55AX flight for `seconds`: the trimmed start when `speed` is 0, otherwise `pitch_deg` with the
## velocity along the body axis; throttle and tank fill as given.
func _fly(pitch_deg: float, speed: float, throttle: float, fill: float, seconds := 0.5) -> Dictionary:
	var f: Node = Session.new()
	f.setup(AIRCRAFT)
	root.add_child(f)
	f.input_enabled = false
	f.set_physics_process(false)
	if speed > 0.0:
		var s: PackedFloat64Array = f.sim.state.duplicate()
		var q := M.q_from_euler(0.0, deg_to_rad(pitch_deg), 0.0)
		for i in 4:
			s[RB.ATT + i] = q[i]
		for i in 3:
			s[RB.VEL + i] = speed if i == 0 else 0.0
			s[RB.RATE + i] = 0.0
		f.sim.state = s
		f.sim.previous = s.duplicate()
	else:
		throttle = f.sim.inputs[3]
	var install: Dictionary = f.aircraft.model.propulsion.glow
	f.sim.continuous[1] = install.capacity_fuel_kg * fill
	f.sim.inputs[3] = throttle
	for tick in int(seconds * Engine.physics_ticks_per_second):
		f.sim.step()
		if not f.sim.fault_reason.is_empty():
			break
	var state: Dictionary = f.glow_state()
	var out := {ok = state.get("ok", false) and f.sim.fault_reason.is_empty(), fault = f.sim.fault_reason}
	if out.ok:
		out.factor = float(state.fuel_feed.factor)
		out.mixture = float(state.actual_mixture)
		out.g_aft = -float(state.fuel_feed.g_eff[0])
		out.g_eff = state.fuel_feed.g_eff
		out.solver = state.get("fuel_feed_solver", {})
	f.queue_free()
	return out


func _flights() -> void:
	var trimmed := _fly(0.0, 0.0, 0.0, 1.0)
	var accelerating := _fly(0.0, 12.0, 1.0, 1.0)
	var accelerating_low := _fly(0.0, 12.0, 1.0, 0.15)
	var braking_dive := _fly(-85.0, 35.0, 0.0, 1.0)
	for run in [trimmed, accelerating, accelerating_low, braking_dive]:
		if not run.ok:
			_check("glow flights run", false, str(run.fault))
			return
	var g: PackedFloat64Array = trimmed.g_eff
	_check("trimmed level flight: the fuel feels 1 g straight down the body z axis %s" % str(g),
		absf(g[2] - G) < 0.05 * G and absf(g[0]) < 0.05 * G and absf(g[1]) < 0.05 * G)
	_check("trimmed level flight with a full tank runs needled (k %.4f)" % trimmed.factor, absf(trimmed.factor - 1.0) < 0.01)
	_check("actual feed-enabled stage solves its factor residual within the declared bound",
		trimmed.solver is Dictionary and absf(float(trimmed.solver.get("residual",INF)))<=Feed.SOLVE_RESIDUAL_TOLERANCE,
		str(trimmed.get("solver",{})))
	_check("actual weak-coupling stage uses fewer than eight source evaluations (no-feed baseline is one)",
		trimmed.solver is Dictionary and int(trimmed.solver.get("evaluations",99))<8,
		str(trimmed.get("solver",{})))
	_check("full throttle from 12 m/s throws the fuel aft (%.1f m/s²)" % accelerating.g_aft, accelerating.g_aft > 2.0)
	_check("and leans the engine (k %.3f, mixture %.3f vs %.3f trimmed)" % [accelerating.factor, accelerating.mixture, trimmed.mixture],
		accelerating.factor < trimmed.factor - 0.02 and accelerating.mixture < trimmed.mixture)
	_check("a low tank leans it further (k %.3f vs %.3f)" % [accelerating_low.factor, accelerating.factor], accelerating_low.factor < accelerating.factor - 0.01)
	_check("a dive that drag is slowing throws the fuel forward and richens (k %.3f, g aft %.1f m/s²)" % [braking_dive.factor, braking_dive.g_aft],
		braking_dive.g_aft < -2.0 and braking_dive.factor > 1.1 and braking_dive.mixture > trimmed.mixture)
