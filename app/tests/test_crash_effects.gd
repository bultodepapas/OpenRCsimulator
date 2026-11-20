extends SceneTree
const Effects = preload("res://render/crash/effects.gd")
var failures := 0
var checks := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ")+label)
func _initialize() -> void:
	run.call_deferred()
## Collision audit 2026-11-17 regressions: CR-AUD-05 (impact height), CR-AUD-12 (one clock), CR-AUD-13 (accepted fuel).
func _audit_regressions(fx: Node3D) -> void:
	var report := {"class":3,"severity":0.7,"surface":"tree_trunk","component_group":"fuselage"}
	fx.start(Vector3(2,10,3),Vector3(5,-2,0),report,0.0,false,Vector3.ZERO)
	check("CR-AUD-05 an elevated impact keeps its height",absf(fx._origin.y - 10.0) < 1.0e-4 and absf(fx.dust.global_position.y - 10.0) < 1.0e-4)
	var lowest := INF
	for i in fx._fragment_count:
		lowest = minf(lowest, fx._positions[i].y)
	check("CR-AUD-05 chips spawn at the elevated impact",fx._fragment_count > 0 and lowest > 9.25)
	check("CR-AUD-05 no ground gouge under an elevated impact",fx.stats().marks == 0)
	for i in 600:
		fx.update(1.0/60.0,false)
	var settled := INF
	for i in fx._fragment_count:
		settled = minf(settled, fx._positions[i].y)
	check("CR-AUD-05 chips fall to the ground below",absf(settled - 0.012) < 1.0e-3)
	fx.ground_sampler = func(_point: Vector3) -> PackedFloat64Array: return PackedFloat64Array([1.5,0.0,0.0])
	fx.start(Vector3(0,1.5,0),Vector3(5,-2,0),{"class":3,"severity":0.7},0.0,false,Vector3.ZERO)
	check("CR-AUD-05 a raised ground gets its gouge and floor",fx.stats().marks == 1 and is_equal_approx(fx._ground_y,1.5) and fx._origin.y >= 1.54 - 1.0e-4)
	fx.ground_sampler = Callable()
	var slow: Node3D = load("res://render/crash/effects.gd").new()
	root.add_child(slow)
	slow.prepare()
	for target: Node3D in [fx, slow]:
		target.start(Vector3.ZERO,Vector3(5,-2,0),report,0.0,false,Vector3.ZERO)
	for i in 60:
		fx.update(1.0/60.0,false)
	for i in 10:
		slow.update(0.1,false)
	check("CR-AUD-12 equal supplied time gives equal age at 60 and 10 Hz",absf(fx._age - 1.0) < 1.0e-4 and absf(slow._age - 1.0) < 1.0e-4)
	slow.free()
	var hot := {"class":4,"severity":1.0,"tank_ruptured":true}
	fx.start(Vector3.ZERO,Vector3(40,-50,0),hot,1.28,true,Vector3.ZERO)
	fx.apply_energy(Effects.energy_outcome({"kerosene": 0.035},hot,true,true))
	check("CR-AUD-13 kerosene fire lasts for the accepted fuel sample",is_equal_approx(fx._fire_duration,0.035/Effects.KEROSENE_BURN_KG_S))
	fx.start(Vector3.ZERO,Vector3(40,-50,0),hot,1.28,true,Vector3.ZERO)
	fx.apply_energy(Effects.energy_outcome({"kerosene": 0.0},hot,true,true))
	check("CR-AUD-13 an empty accepted tank leaves no kerosene fire",fx._fire_duration == 0.0 and fx.fire_strength() == 0.0)
	fx.reset()


func run() -> void:
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	check("particle budget",fx.stats().particles <= 700)
	check("transparent particles do not cast card shadows",fx.emitters.all(func(p): return p.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
	check("no live effects before collision",fx.stats().fire == 0 and fx.stats().splinters == 0)
	fx.mark(Vector3.ZERO,Vector3(0,-100,0),0.5)
	check("vertical speed does not lengthen the horizontal gouge",is_equal_approx(fx.marks[0].scale.z,0.5))
	for hot: bool in [false,true]:
		for fuel: float in [0.0,1.28]:
			for level: int in [0,1,2,3,4]:
				fx.start(Vector3(10,0,20),Vector3(50,-30,0),{"class":level,"severity":level/4.0,"tank_ruptured":true},fuel,hot,Vector3(4,0,0))
				check("fire needs severe + fuel + hot engine %s/%s/%s" % [hot,fuel,level],(fx.fire_strength() > 0) == (hot and fuel>0 and level>=3))
				check("fragment budget",fx.stats().splinters <= 160)
	fx.start(Vector3.ZERO,Vector3(40,-50,0),{"class":4,"severity":1.0,"tank_ruptured":false},1.28,true,Vector3.ZERO)
	check("intact tank does not ignite",fx.fire_strength() == 0)
	fx.start(Vector3.ZERO,Vector3(40,-50,0),{"class":4,"severity":1.0,"tank_ruptured":true},1.28,true,Vector3.ZERO)
	var before: Transform3D = fx.fragments.multimesh.get_instance_transform(0)
	fx.update(1.0,true)
	check("pause freezes fragment poses",fx.fragments.multimesh.get_instance_transform(0) == before)
	check("pause freezes emitters",fx.smoke.speed_scale == 0 and fx.flame.speed_scale == 0)
	for step in 900:
		fx.update(1.0/60,false)
	var finite := true
	for i in fx.stats().splinters:
		var p: Vector3 = fx.fragments.multimesh.get_instance_transform(i).origin
		finite = finite and p.is_finite() and p.y >= 0.0
	check("ballistic fragments remain finite above ground",finite)
	var scorch: Transform3D = fx.marks[0].transform
	for i in 64:
		fx.secondary(Vector3(i,0,0),1)
	check("bounded secondary marks",fx.stats().marks == 16)
	check("primary scorch persists",fx.marks[0].transform == scorch)
	for step in 3000:
		fx.update(1.0/60,false)
	check("finite fuel budget extinguishes",fx.fire_strength() == 0 and not fx.flame.emitting and not fx.smoke.emitting)
	# CR-22c-R3: resting chips do not stop delayed energy effects or the next burst.
	fx.start(Vector3.ZERO,Vector3(40,-50,0),{"class":4,"severity":1.0},0.0,false,Vector3.ZERO)
	for step in 600:
		fx.update(1.0/60.0,false)
	var settled_buffer: PackedFloat32Array = fx.fragments.multimesh.buffer
	var settled_positions: PackedVector3Array = fx._positions.duplicate()
	check("chips settle before the 12-second update cutoff",fx._fragments_settled and fx._age < 12.0)
	fx.apply_energy({vent_delay_s=11.0,vent_s=2.0,flare=true})
	for step in 90:
		fx.update(1.0/60.0,false)
	check("settled chips retain every position, instance transform and color",fx._positions == settled_positions and fx.fragments.multimesh.buffer == settled_buffer)
	check("settled chips still allow delayed battery vent and flare",fx.vent.emitting and fx.flame.emitting and fx.light.visible)
	var held_age: float = fx._age
	for step in 12:
		fx.update(1.0/60.0,true)
	check("repeated pause holds delayed effects and all particle clocks",fx._age == held_age and fx.emitters.all(func(p): return p.speed_scale == 0.0))
	fx.start(Vector3.ZERO,Vector3(40,-50,0),{"class":4,"severity":1.0},0.0,false,Vector3.ZERO)
	var fresh_positions: PackedVector3Array = fx._positions.duplicate()
	fx.update(1.0/60.0,false)
	check("a new crash after settled pause moves fresh chips",fx._positions != fresh_positions)
	check("a new crash restores all particle clocks",fx.emitters.all(func(p): return p.speed_scale == 1.0))
	fx.reset()
	check("reset clears aftermath",fx.stats().marks == 0 and fx.stats().splinters == 0 and not fx.light.visible)
	for p in fx.emitters:
		check("reset hides and stops every emitter",not p.visible and not p.emitting)
	_audit_regressions(fx)
	fx.free()
	print("%d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
