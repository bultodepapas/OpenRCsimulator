extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const OP = preload("res://physics/glow/operating_point.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	for name in ["stik_glow_61fx_2t", "stik_glow_55ax_2t", "stik_glow_fs64v_4t", "stik_glow_55ax_2t_apc_13x6", "stik_glow_fs64v_4t_apc_13x6", "gp_extra_300s_60"]:
		var loaded: Dictionary = AD.load_file("res://data/aircraft/" + name + ".json")
		_check(name + " loads", loaded.ok)
		if not loaded.ok: continue
		var prop: Dictionary = loaded.model.propulsion
		var before := var_to_bytes(prop)
		for query in [[0., 0., 1.225, 1.225], [.5, 20., 1.225, 1.225], [1., -10., .9, .8], [.25, 40., 1.4, 1.3]]:
			_compare(name, prop, query)
		_check(name + " solve leaves input unchanged", var_to_bytes(prop) == before)
		var synthetic: Dictionary = prop.duplicate(true)
		synthetic.glow.propeller.pitch_m *= 1.1
		_compare(name + " modified installation", synthetic, [.5, 20., 1.225, 1.225])
		synthetic = prop.duplicate(true)
		synthetic.glow.profile.parameters.indicated_efficiency = PackedFloat64Array([0.,0.,5000.1,0.,5000.15,.9,5000.2,0.,8000.1,0.,8000.15,.9,8000.2,0.,synthetic.glow.profile.operation.max_rpm,0.])
		_compare(name + " modified profile narrow roots", synthetic, [1., 0., 1.225, 1.225])
		var roots: Dictionary = OP.solve(synthetic, 1., 0., 1.225, 1.225)
		_check(name + " highest of two narrow roots", roots.ok and roots.roots.size() == 2 and roots.rpm > 8000.15 and roots.rpm < 8000.2)
		synthetic.glow.profile.parameters.indicated_efficiency = PackedFloat64Array([0.,0.,synthetic.glow.profile.operation.max_rpm,0.])
		_compare(name + " no restoring root", synthetic, [1., 0., 1.225, 1.225])
		synthetic = prop.duplicate(true)
		synthetic.glow.propeller.chord_m = -1.
		_compare(name + " invalid propeller", synthetic, [.5, 20., 1.225, 1.225])
		synthetic = prop.duplicate(true)
		synthetic.glow.profile.parameters.indicated_efficiency = PackedFloat64Array([0., 1.1, synthetic.glow.profile.operation.max_rpm, 1.1])
		_compare(name + " invalid engine table", synthetic, [.5, 20., 1.225, 1.225])
		_compare(name + " fresh solve after modified inputs", prop, [.5, 20., 1.225, 1.225])
		for query in [[-.1, 0., 1.225, 1.225], [1.1, 0., 1.225, 1.225], [NAN, 0., 1.225, 1.225], [.5, INF, 1.225, 1.225], [.5, 0., 0., 1.225], [.5, 0., 1.225, 0.]]:
			_compare(name + " invalid query", prop, query)
	print("Glow operating-point reuse: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _compare(label: String, prop: Dictionary, q: Array) -> void:
	var expected: Dictionary = _reference_solve(prop, q[0], q[1], q[2], q[3])
	var actual: Dictionary = OP.solve(prop, q[0], q[1], q[2], q[3])
	_check(label + " byte-exact result", var_to_bytes(expected) == var_to_bytes(actual))

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

## Frozen pre-optimization mesh/bisection, with independently guarded residuals.
func _reference_solve(prop: Dictionary, throttle: float, u: float, rho: float, dry_density: float) -> Dictionary:
	for v in [throttle,u,rho,dry_density]:
		if not is_finite(v): return {ok=false, roots=PackedFloat64Array()}
	if throttle<0.0 or throttle>1.0 or rho<=0.0 or dry_density<=0.0: return {ok=false, roots=PackedFloat64Array()}
	var maximum: float = prop.glow.profile.operation.max_rpm
	var minimum: float = prop.glow.settings.stall_rpm
	var roots := PackedFloat64Array()
	var nodes: Array[float]=[]
	for i in range(1,129): nodes.append(minimum+(maximum-minimum)*i/128.0)
	for key in prop.glow.profile.parameters:
		var table: Variant=prop.glow.profile.parameters[key]
		if not table is PackedFloat64Array or key=="combustion_efficiency": continue
		for i in range(0,table.size(),2):
			if table[i]>minimum and table[i]<maximum: nodes.append(table[i])
	nodes.sort()
	var lo: float = minimum
	var flo: float = OP.residual(prop,lo,throttle,u,rho,dry_density)
	for hi: float in nodes:
		if hi<=lo: continue
		var fhi: float = OP.residual(prop,hi,throttle,u,rho,dry_density)
		if not is_finite(flo) or not is_finite(fhi): return {ok=false, roots=roots}
		if flo>0.0 and fhi<=0.0:
			var left: float=lo
			var right: float=hi
			for _iteration in 64:
				var mid: float=(left+right)*0.5
				var fm: float=OP.residual(prop,mid,throttle,u,rho,dry_density)
				if not is_finite(fm): return {ok=false,roots=roots}
				if fm>0.0: left=mid
				else: right=mid
			var root_rpm: float=(left+right)*0.5
			if absf(OP.residual(prop,root_rpm,throttle,u,rho,dry_density))>1e-10: return {ok=false,roots=roots}
			roots.append(root_rpm)
		lo=hi
		flo=fhi
	return {ok=not roots.is_empty(),roots=roots,rpm=roots[roots.size()-1] if not roots.is_empty() else NAN,
		selection="highest bracketed restoring root on RPM-knot plus 128-interval mesh"}
