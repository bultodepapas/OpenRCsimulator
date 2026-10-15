extends SceneTree
var output := ""
var reference_path := ""
var candidate_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=")
		if arg.begins_with("--candidate="): candidate_path = arg.trim_prefix("--candidate=")
	_run.call_deferred()

func _run() -> void:
	var effects: Array = [load(reference_path).new(), load(candidate_path).new()]
	for fx in effects:
		root.add_child(fx)
		fx.prepare()
	var comparisons := 0
	var valid := true
	for level in 5:
		for schedule in ["fuel", "vent"]:
			for fx in effects:
				_start(fx, level)
				fx.apply_energy({fire_kind="gasoline", fire_s=8.0, flash=true, flash_radius_m=.4, flash_s=.35} if schedule == "fuel" else {vent_delay_s=5.0,vent_s=20.0,flare=true})
			for frame in 1800:
				var dt: float = [1.0/60.0, 1.0/144.0, 0.05, 0.0, -0.01, 0.2][frame % 6]
				for fx in effects: fx.update(dt, frame >= 80 and frame < 95)
				var equal := _state(effects[0]) == _state(effects[1])
				comparisons += 1
				if not equal:
					push_error("parity failed at class %d / %s / frame %d" % [level, schedule, frame])
					valid = false
					break
			print("class ",level," / ",schedule," parity: ",valid)
	var rows: Array = []
	for scenario in ["airborne", "settled", "paused", "inactive"]:
		for repeat in 16:
			for variant in ([0,1] if repeat % 2 == 0 else [1,0]):
				var fx: Node3D = effects[variant]
				_start(fx,4)
				if scenario == "settled":
					for frame in 600: fx.update(1.0/60.0,false)
					valid = valid and fx._velocities.slice(0,fx._fragment_count).count(Vector3.ZERO) == fx._fragment_count
				if scenario == "inactive": fx.reset()
				fx.update(0.0,scenario == "paused")
				var start := Time.get_ticks_usec()
				for frame in 1200: fx.update(0.0,scenario == "paused")
				rows.append({scenario=scenario,repeat=repeat,variant=variant,frames=1200,usec=Time.get_ticks_usec()-start})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,comparisons=comparisons,rows=rows},"\t"))
	print(comparisons," exact comparisons; valid=",valid)
	for fx in effects: fx.free()
	quit(0 if valid else 1)

func _start(fx: Node3D, level: int) -> void:
	fx.start(Vector3(2,0,4),Vector3(40,-30,5),{"class":level,"severity":level/4.0,"tank_ruptured":true},1.28,true,Vector3(3,0,1))

func _state(fx: Node3D) -> Array:
	var state: Array = [fx._age,fx._rng.state,fx._positions,fx._velocities,fx._rotations,fx._spins,
		fx.fragments.multimesh.buffer,fx.fragments.multimesh.visible_instance_count,
		fx.light.visible,fx.light.light_energy,fx.fire_strength(),fx.flash_strength()]
	for p in fx.emitters: state.append([p.visible,p.emitting,p.speed_scale,p.transform])
	return state
