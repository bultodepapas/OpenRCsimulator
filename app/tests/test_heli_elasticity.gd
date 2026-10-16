extends SceneTree
const Flex := preload("res://physics/rotorcraft/hx700_flex_bench.gd")
const ElasticSkin := preload("res://render/rotor/hx700_elastic_skin.gd")
const Model := preload("res://aircraft/hx700_articulated_model.gd")
const View := preload("res://render/rotor/hx700_mechanics_view.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted:
		failures += 1
	print(("ok " if accepted else "FAIL ") + label)

func _run() -> void:
	var flex := Flex.new()
	_check("unloaded structure stays exactly at rest", flex.advance(1) and flex.energy_j() == 0 and not flex.needs_advance())
	flex.set_loads(PackedFloat64Array([25.49729, 25.49729, 2]))
	flex.advance(0.04)
	# Independent RK4 reference, using the differential equation rather than
	# copying the analytic state-transition formula.
	var reference := PackedFloat64Array([0, 0])
	var maximum_error := 0.0
	for mode in 3:
		reference = PackedFloat64Array([0, 0])
		for tick in 4000:
			reference = _rk4(reference, mode, flex.force[mode], 0.00001)
		maximum_error = maxf(maximum_error, absf(reference[0] - flex.displacement[mode]))
		maximum_error = maxf(maximum_error, absf(reference[1] - flex.velocity[mode]))
	_check("analytic load response agrees with independent RK4", maximum_error < 1e-10)
	_check("equal rail loads give identical compression", flex.displacement[0] == flex.displacement[1])
	_check("input work equals stored plus dissipated energy", absf(flex.work_j - flex.energy_j() - flex.dissipated_j) < 1e-12)
	flex.advance(3)
	_check("static rail and shell deflection equals force / stiffness", absf(flex.displacement[0] - 25.49729 / 6000) < 1e-12 and absf(flex.displacement[2] - 2.0 / 800) < 1e-12)
	flex.set_loads(PackedFloat64Array([0, 0, 0]))
	var previous_energy := flex.energy_j()
	var passive := true
	var overshoot := false
	for tick in 720:
		flex.advance(1.0 / 240)
		passive = passive and flex.energy_j() <= previous_energy + 1e-12
		overshoot = overshoot or flex.displacement[0] < 0
		previous_energy = flex.energy_j()
	_check("release rebounds then loses energy monotonically", overshoot and passive and flex.energy_j() < 1e-25)
	_check("release preserves the work / dissipation balance", absf(flex.work_j - flex.energy_j() - flex.dissipated_j) < 1e-12)
	var timing_error := 0.0
	var baseline: Dictionary = {}
	for fps in [1, 30, 60, 144]:
		var timed := Flex.new()
		for load in [PackedFloat64Array([51, 0, 2]), PackedFloat64Array([0, 51, -2]), PackedFloat64Array([0, 0, 0])]:
			timed.set_loads(load)
			for tick in fps:
				timed.advance(0.17 / fps)
			if fps == 1:
				baseline[str(load)] = timed.capture_state()
			else:
				for i in 3:
					timing_error = maxf(timing_error, absf(timed.displacement[i] - baseline[str(load)].q[i]))
					timing_error = maxf(timing_error, absf(timed.velocity[i] - baseline[str(load)].v[i]))
				timing_error = maxf(timing_error, absf(timed.dissipated_j - baseline[str(load)].dissipated_j))
	_check("held-load tape agrees at 1/30/60/144 Hz including energy", timing_error < 1e-11)
	var random := RandomNumberGenerator.new()
	random.seed = 260116
	var changing := Flex.new()
	var changing_ok := true
	var maximum_balance := 0.0
	for tick in 10000:
		if tick % 4 == 0:
			changing_ok = changing.set_loads(PackedFloat64Array([random.randf_range(0, 51), random.randf_range(0, 51), random.randf_range(-2, 2)])) and changing_ok
		changing_ok = changing.advance(random.randf_range(.001, .03)) and changing_ok
		maximum_balance = maxf(maximum_balance, absf(changing.work_j - changing.energy_j() - changing.dissipated_j))
	_check("10000 variable load/time steps preserve the energy balance", changing_ok and maximum_balance < 1e-9)
	print("VARIABLE_LOAD maximum_energy_balance_error_j=", maximum_balance)
	flex = Flex.new()
	flex.set_loads(PackedFloat64Array([51, 0, 0]))
	flex.advance(0.03)
	_check("one skid load does not deform the opposite skid or canopy", flex.displacement[0] > 0 and flex.displacement[1] == 0 and flex.displacement[2] == 0)
	var before := flex.capture_state()
	_check("invalid loads and times fail atomically", not flex.set_loads(PackedFloat64Array([0, -1, 0])) and not flex.set_loads(PackedFloat64Array([0, 0, NAN])) and not flex.set_loads(PackedFloat64Array([52, 0, 0])) and not flex.advance(INF) and not flex.advance(-0.1) and not flex.advance(61) and flex.capture_state() == before)
	var overtravel := Flex.new()
	# Disposable initial-velocity fixture: its end state would be nearly zero,
	# but it crosses the shell travel limit between those two sampled frames.
	overtravel.velocity[2] = 2.0
	var before_overtravel := overtravel.capture_state()
	_check("long frames cannot hide intermediate overtravel", not overtravel.advance(1) and overtravel.capture_state() == before_overtravel)
	var preview := Model.load_preview()
	root.add_child(preview.root)
	var original_gear: Mesh = preview.bindings[ElasticSkin.IDS[0]].mesh
	var original_canopy: Mesh = preview.bindings[ElasticSkin.IDS[1]].mesh
	var posts: Mesh = preview.bindings["visual.carenado_postes"].mesh
	var grommets: Mesh = preview.bindings["visual.carenado_gomas"].mesh
	var skin := ElasticSkin.new()
	_check("advanced mesh receives two rail morphs and one shell morph", skin.configure(preview) and skin.gear.mesh.get_blend_shape_count() == 2 and skin.canopy.mesh.get_blend_shape_count() == 1)
	_check("source meshes and rigid mount parts remain untouched", original_gear.get_blend_shape_count() == 0 and original_canopy.get_blend_shape_count() == 0 and preview.bindings["visual.carenado_postes"].mesh == posts and preview.bindings["visual.carenado_gomas"].mesh == grommets)
	var anchors_fixed := true
	var rails_rigid := true
	var upper_count := 0
	var rail_count := 0
	var flexing_vertices := 0
	for s in original_gear.get_surface_count():
		var rest: PackedVector3Array = original_gear.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var shapes: Array = skin.gear.mesh.surface_get_blend_shape_arrays(s)
		for j in rest.size():
			var p := skin.gear.transform * rest[j]
			for mode in 2:
				var delta: Vector3 = shapes[mode][Mesh.ARRAY_VERTEX][j] - rest[j]
				if p.y > 0.074 or (s == 0 and absf(p.z) < 0.044):
					anchors_fixed = anchors_fixed and delta.length() < 1e-7
					upper_count += 1
				if s == 1 or s == 2 or (s >= 3 and p.y < 0.05) or (s == 0 and p.y < 0.020):
					var sign_side := -1.0 if mode == 0 else 1.0
					var expected := Vector3(0, 0.01, sign_side * ElasticSkin.SPLAY * 0.01) if p.z * sign_side > 0 else Vector3.ZERO
					rails_rigid = rails_rigid and delta.distance_to(expected) < 1e-7
					rail_count += 1
				if s == 0 and delta.y > 1e-6 and delta.y < 0.00999:
					flexing_vertices += 1
	_check("actual mesh chassis bases and bolts stay fixed", anchors_fixed and upper_count > 100)
	_check("actual rails, end caps, clamps and low screws translate as rigid sets", rails_rigid and rail_count > 100)
	_check("actual support struts bend between fixed bases and moving clamps", flexing_vertices > 100)
	var canopy_pins := 0
	var canopy_free := 0
	var pins_fixed := true
	for s in original_canopy.get_surface_count():
		var rest: PackedVector3Array = original_canopy.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var shape: Array = skin.canopy.mesh.surface_get_blend_shape_arrays(s)[0]
		for j in rest.size():
			var p := rest[j]
			var delta: Vector3 = shape[Mesh.ARRAY_VERTEX][j] - p
			if minf(Vector2(p.x, p.y).distance_to(Vector2(.15, .145)), Vector2(p.x, p.y).distance_to(Vector2(-.04, .204))) < .008:
				canopy_pins += 1
				pins_fixed = pins_fixed and delta.length() < 1e-7
			if delta.z > .0039:
				canopy_free += 1
	_check("actual shell flexes while four attachment patches stay fixed", pins_fixed and canopy_pins > 20 and canopy_free > 100)
	var preserved := true
	for pair in [[original_gear, skin.gear.mesh], [original_canopy, skin.canopy.mesh]]:
		for s in pair[0].get_surface_count():
			var a: Array = pair[0].surface_get_arrays(s)
			var b: Array = pair[1].surface_get_arrays(s)
			preserved = preserved and pair[0].surface_get_material(s) == pair[1].surface_get_material(s)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
				preserved = preserved and a[channel] == b[channel]
	_check("morph construction preserves base vertices, UVs, indices and materials", preserved)
	skin.apply(PackedFloat64Array([.005, 0, -.002]))
	_check("signed physical metres reach native blend weights", absf(skin.gear.get_blend_shape_value(0) - .5) < 1e-7 and skin.gear.get_blend_shape_value(1) == 0 and absf(skin.canopy.get_blend_shape_value(0) + .5) < 1e-7)
	_check("invalid render deformation retains the accepted morphs", not skin.apply(PackedFloat64Array([.03, 0, 0])) and skin.gear.get_blend_shape_value(0) == .5)
	_check_native_mix(skin)
	preview.root.queue_free()
	var view := View.new()
	root.add_child(view)
	view.set_process(false)
	view._set_elastic_mode(true)
	view._load_preset("Un patín")
	view._process(.03)
	_check("elastic bench advances with stopped controls and rotor", view.flex.displacement[0] > 0 and view.motion.rpm == 0 and view.elastic_skin.gear.get_blend_shape_value(0) > 0)
	view._set_paused(true)
	var frozen := view.flex.displacement.duplicate()
	view._load_preset("Soltar cargas")
	view._process(1)
	_check("pause freezes elastic state while loads are queued", frozen == view.flex.displacement)
	view._step()
	_check("frame step advances released elastic state while paused", view.paused and view.flex.displacement != frozen)
	view._set_paused(false)
	var saved := view.flex.capture_state()
	view.rig._linkages[0].length_m += .1
	view._process(.03)
	_check("mechanism rejection rolls back elastic state too", view.paused and view.flex.capture_state() == saved)
	view.queue_free()
	await process_frame
	print("%d checks, %d failed; RK4 max error %.14f; frame-rate max error %.14f; pinned shell vertices %d" % [checks, failures, maximum_error, timing_error, canopy_pins])
	quit(0 if failures == 0 else 1)

func _check_native_mix(skin: RefCounted) -> void:
	var accepted := true
	var maximum_error := 0.0
	# Exercise the engine's evaluated blend result, including negative weights
	# and weights above one; inspecting only the authored targets misses mode errors.
	for q in [PackedFloat64Array([0, 0, 0]), PackedFloat64Array([.015, .013, -.006]), PackedFloat64Array([-.02, .02, .008])]:
		accepted = skin.apply(q) and accepted
		for node: MeshInstance3D in [skin.gear, skin.canopy]:
			var baked := node.bake_mesh_from_current_blend_shape_mix()
			if baked == null:
				accepted = false
				continue
			for surface in baked.get_surface_count():
				var arrays := baked.surface_get_arrays(surface)
				var base := node.mesh.surface_get_arrays(surface)
				var shapes := node.mesh.surface_get_blend_shape_arrays(surface)
				for vertex in arrays[Mesh.ARRAY_VERTEX].size():
					var expected: Vector3 = base[Mesh.ARRAY_VERTEX][vertex]
					for mode in shapes.size():
						expected += (shapes[mode][Mesh.ARRAY_VERTEX][vertex] - base[Mesh.ARRAY_VERTEX][vertex]) * node.get_blend_shape_value(mode)
					var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][vertex]
					var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][vertex]
					accepted = accepted and point.is_finite() and normal.is_finite() and absf(normal.length() - 1) < 1e-5
					maximum_error = maxf(maximum_error, point.distance_to(expected))
	_check("engine-evaluated morphs preserve signed travel and finite unit normals", accepted and maximum_error < 1e-7)
	print("NATIVE_MORPHS maximum_vertex_error_m=", maximum_error)


func _derivative(state: PackedFloat64Array, mode: int, force: float) -> PackedFloat64Array:
	return PackedFloat64Array([state[1], (force - Flex.STIFFNESS_N_M[mode] * state[0] - Flex.DAMPING_NS_M[mode] * state[1]) / Flex.MASS_KG[mode]])

func _add(a: PackedFloat64Array, b: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0] * dt, a[1] + b[1] * dt])

func _rk4(state: PackedFloat64Array, mode: int, force: float, dt: float) -> PackedFloat64Array:
	var a := _derivative(state, mode, force)
	var b := _derivative(_add(state, a, dt * .5), mode, force)
	var c := _derivative(_add(state, b, dt * .5), mode, force)
	var d := _derivative(_add(state, c, dt), mode, force)
	return PackedFloat64Array([state[0] + dt * (a[0] + 2*b[0] + 2*c[0] + d[0]) / 6, state[1] + dt * (a[1] + 2*b[1] + 2*c[1] + d[1]) / 6])
