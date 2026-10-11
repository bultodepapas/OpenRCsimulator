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
	fx.reset()
	check("reset clears aftermath",fx.stats().marks == 0 and fx.stats().splinters == 0 and not fx.light.visible)
	for p in fx.emitters:
		check("reset hides and stops every emitter",not p.visible and not p.emitting)
	fx.free()
	print("%d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
