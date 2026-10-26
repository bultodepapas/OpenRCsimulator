## Actual normal geometry/common-mass stage, synthetic failure strengths/responses.
extends SceneTree
const Response := preload("res://physics/aircraft_ground_damage.gd")
const Stage := preload("res://physics/aircraft_ground_stage.gd")
const Damage := preload("res://physics/gear_damage.gd")
const NormalStage := preload("res://physics/aircraft_ground_dynamics.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Profile := preload("res://physics/aircraft_ground_profile.gd")
const Wheels := preload("res://physics/wheel_profiles.gd")
const Normal := preload("res://physics/normal_compliance.gd")
const Ground := preload("res://physics/ground_support.gd")
const Liquid := preload("res://physics/liquid_fuel.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
var checks := 0
var failed := 0
var profile: Dictionary
var model: Dictionary
var prepared: Dictionary
var provider: Dictionary
var motion: Array
var live: Dictionary
var authored_profile: Dictionary
var authored_damage: Dictionary
var bound: Dictionary

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	_fixture()
	if failed:
		quit(1)
		return
	_bind()
	if failed:
		quit(1)
		return
	_contracts()
	_actual_responses()
	_progressive_and_independent()
	_kernel()
	print("Attached gear response: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "Explicit synthetic stage fixture, not measured aircraft structure"}

func _fixture() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	var derived := Data.validate_and_derive(raw)
	check("installed P51 closed-shaft aircraft derives", derived.ok, str(derived.get("errors", [])))
	if not derived.ok: return
	var applied := Wheels.apply_to_model(derived.model)
	var parameters := {format = Normal.FORMAT}
	var values := {stiffness = 1500.0, compression_damping = 20.0, rebound_damping = 12.0,
		damping_onset = 0.002, stroke = 0.2, stop_stiffness = 0.0,
		stop_scale = 0.01, stop_exponent = 3.0, stop_damping = 0.0}
	for key: String in values: parameters[key] = _q(values[key], Normal.SPECS[key][0])
	var supports: Array = []
	var records: Array = [{rotor_id = derived.model.propulsion.id, transverse_inertia = _q(0.5 * derived.model.propulsion.rotor_inertia, "kg·m2")}]
	var locations := [M.v3(-0.2, -0.35, 0.0), M.v3(-0.2, 0.35, 0.0), M.v3(0.4, 0.0, 0.0)]
	for i in applied.model.landing_gear.contacts.size():
		var contact: Dictionary = applied.model.landing_gear.contacts[i]
		var hub: PackedFloat64Array = locations[i]
		hub[2] = 0.2 - contact.wheel_radius
		var cg: PackedFloat64Array = derived.model.cg_le
		supports.append({contact_id = contact.id, support_type = "wheel", width_model = "zero_width",
			hub_le = _q([cg[0] - hub[0], cg[1] + hub[1], cg[2] - hub[2]], "m"),
			axle_le = _q([0.0, -1.0, 0.0], "1"), normal_profile_id = "synthetic_normal"})
		records.append({rotor_id = contact.id, transverse_inertia = _q(0.5 * contact.wheel_inertia, "kg·m2")})
	var authored := {format = Profile.FORMAT, law = Profile.COUPLED_LAW,
		capabilities = {support = "wheels", shape = "thin_ring", normal = "effective_leg_tire"},
		wheel_profile_ref = {format = Wheels.FORMAT, profile_id = raw.id, profile_sha256 = applied.identity.profile_sha256},
		normal_profiles = [{id = "synthetic_normal", parameters = parameters}], supports = supports,
		rotor_partition = {format = Profile.PARTITION_FORMAT, partition_id = "test_stage_aggregate", reference_pose_id = "test_fixed_hubs",
			kind = "estimated", source = "Explicit test-only aggregate; not a physical ownership/calibration claim", center_model = "fixed_hubs", rotors = records}}
	authored_profile = authored.duplicate(true)
	var resolved := Profile.resolve(authored, derived.model)
	check("closed P51 authoring profile resolves without launch admission", resolved.ok and not resolved.launch_available, str(resolved.get("errors", [])))
	if not resolved.ok: return
	profile = resolved.profile
	model = resolved.model
	prepared = Stage.prepare(profile, model)
	check("normal/rotor stage prepares once", prepared.ok and not prepared.launch_available, str(prepared))
	if not prepared.ok: return
	provider = Ground.prepare_legacy(PackedFloat64Array())
	for support: Dictionary in prepared.normal.supports:
		motion.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(), axle_body = support.axle_body.duplicate(),
			carrier_rate_body = M.v3(0.0, 0.0, 0.0), carrier_accel_body = M.v3(0.0, 0.0, 0.0)})
	var fuel: Dictionary = model.propulsion.liquid_fuel
	live = Liquid.properties(fuel, {str(fuel.tank_id): 0.5 * (float(fuel.capacity_kg) + float(fuel.unusable_kg))})
	check("actual installed finite-fuel resource supplies live mass/inertia", live.ok and M.norm(live.cg_body_m) > 0.0, str(live))

func _bind() -> void:
	var ids: Array = []
	var supports: Array = []
	for row: Dictionary in prepared.normal.supports:
		ids.append(row.contact_id)
		var weak: Dictionary = row.normal.provenance.duplicate(true)
		weak.stiffness.value = 150.0
		supports.append({contact_id = row.contact_id, failed_normal = weak})
	authored_damage = {format = Response.FORMAT, source = "Synthetic response qualification fixture",
		damage = {format = Damage.FORMAT, law = Damage.LAW, source = "Synthetic capacity fixture",
			components = [{component_id = "assembly", support_ids = ids, source = "One synthetic three-support structure",
				normal_failure_force = _q(100.0, "N")}]}, supports = supports,
		component_axes = [{component_id = "assembly", positive_load_axis_body = _q([0.0, 0.0, -1.0], "1")}]}
	bound = Response.prepare(authored_damage, profile, model)
	check("actual stage binds authored weaker response", bound.ok, str(bound.get("errors", [])))

func _clock(tick := 1) -> Dictionary:
	return {tick = tick, time_s = tick * 0.01, dt = 0.01}

func _body(compression := 0.03, speed := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -0.2 + compression), M.v3(0.0, 0.0, speed), M.q_identity(), M.v3(0.0, 0.0, 0.0))

func _transition(state: Dictionary, body: PackedFloat64Array, tick := 1, binding: Dictionary = {}) -> Dictionary:
	return Response.transition_at_boundary(bound if binding.is_empty() else binding, state.modes, state.losses,
		body, provider, PackedFloat64Array([0.0, 0.0, 0.0]), motion, _clock(tick), "response-fixture", false)

func _contracts() -> void:
	var original := var_to_bytes([authored_damage, profile, model, bound])
	for mutation: String in ["extra", "duplicate", "missing", "unknown", "stronger", "unchanged", "stroke", "scale", "exponent", "bad_quantity",
		"axis_missing", "axis_duplicate", "axis_unknown", "axis_nonunit", "axis_bool", "axis_unit", "axis_source", "capacity_missing", "stale_hardware"]:
		var raw := authored_damage.duplicate(true)
		var p := profile.duplicate(true)
		match mutation:
			"extra": raw.extra = true
			"duplicate": raw.supports[1] = raw.supports[0].duplicate(true)
			"missing": raw.supports.pop_back()
			"unknown": raw.supports[0].contact_id = "unknown"
			"stronger": raw.supports[0].failed_normal.stiffness.value = 1501.0
			"unchanged": raw.supports[0].failed_normal.stiffness.value = 1500.0
			"stroke": raw.supports[0].failed_normal.stroke.value = 0.1
			"scale": raw.supports[0].failed_normal.stop_scale.value = 0.02
			"exponent": raw.supports[0].failed_normal.stop_exponent.value = 2.0
			"bad_quantity": raw.supports[0].failed_normal.stiffness.unit = "kg"
			"axis_missing": raw.component_axes.clear()
			"axis_duplicate": raw.component_axes.append(raw.component_axes[0].duplicate(true))
			"axis_unknown": raw.component_axes[0].component_id = "unknown"
			"axis_nonunit": raw.component_axes[0].positive_load_axis_body.value = [0.0, 0.0, -0.5]
			"axis_bool": raw.component_axes[0].positive_load_axis_body.value = [false, 0.0, -1.0]
			"axis_unit": raw.component_axes[0].positive_load_axis_body.unit = "N"
			"axis_source": raw.component_axes[0].positive_load_axis_body.source = ""
			"capacity_missing": raw.damage.components.clear()
			"stale_hardware": p.wheel_profile_identity.profile_sha256 = "0".repeat(64)
		check("invalid response rejects " + mutation, not Response.prepare(raw, p, model).ok)
	check("preparation never mutates authored inputs", original == var_to_bytes([authored_damage, profile, model, bound]))
	var initial := Damage.initial_state(bound.damage_profile)
	check("healthy selection exactly preserves stage", var_to_bytes(Response.select(bound, initial.modes, initial.losses, 0).stage) == var_to_bytes(prepared))
	var changed := bound.duplicate(true)
	changed.failed_normals[0].values.stiffness = 90000.0
	check("prepared mutation rejected", not Response.select(changed, initial.modes, initial.losses, 0).ok)
	var selected := Response.select(bound, initial.modes, initial.losses, 0)
	selected.stage.normal.supports[0].hub_body[0] = 987.0
	check("selected stage detached", original == var_to_bytes([authored_damage, profile, model, bound]))
	var raw := authored_damage.duplicate(true)
	raw.supports.reverse()
	var reordered := Response.prepare(raw, profile, model)
	check("authored support order does not alter physical result", reordered.ok and var_to_bytes(reordered.healthy_stage) == var_to_bytes(bound.healthy_stage)
		and var_to_bytes(reordered.failed_normals) == var_to_bytes(bound.failed_normals) and reordered.damage_profile == bound.damage_profile)
	for primitive: Variant in [null, true, 1, 1.0, [], {}]:
		for selector: String in ["format", "axis_unit", "damage_law", "normal_format"]:
			raw = authored_damage.duplicate(true)
			match selector:
				"format": raw.format = primitive
				"axis_unit": raw.component_axes[0].positive_load_axis_body.unit = primitive
				"damage_law": raw.damage.law = primitive
				"normal_format": raw.supports[0].failed_normal.format = primitive
			check("wrong primitive selector cleanly refuses " + selector, not Response.prepare(raw, profile, model).ok)
		changed = bound.duplicate(true)
		changed.ok = primitive
		check("wrong prepared ok primitive refuses", not Response.select(changed, initial.modes, initial.losses, 0).ok if typeof(primitive) != TYPE_BOOL else true)
	for mutation: String in ["hardening", "axis", "hub", "radius", "rotor", "normal_source", "profile_compilation", "bad_source_axis", "bad_source_shaft"]:
		changed = bound.duplicate(true)
		match mutation:
			"hardening": changed.failed_normals[0].values.stiffness = 90000.0
			"axis": changed.positive_load_axes_body[0][2] = 1.0
			"hub": changed.healthy_stage.normal.supports[0].hub_body[0] += 0.2
			"radius": changed.healthy_stage.radii_m[0] *= 2.0
			"rotor": changed.healthy_stage.rotor_system.axial[0] *= 2.0
			"normal_source": changed.provenance.supports[0].failed_normal.stiffness.value = 99999.0
			"profile_compilation": changed.ground_source.supports[0].normal.values.stiffness = 99999.0
			"bad_source_axis": changed.model_binding.propulsion.axis = 5.0
			"bad_source_shaft": changed.model_binding.propulsion.shaft = 5.0
		changed.erase("identity")
		changed.identity = Damage._digest(changed)
		check("rehashed inconsistent resource refuses " + mutation, not Response.select(changed, initial.modes, initial.losses, 0).ok)
	changed = bound.duplicate(true)
	changed.provenance.loop = changed.provenance
	check("cyclic prepared input refuses before hashing", not Response.select(changed, initial.modes, initial.losses, 0).ok)
	changed.provenance.erase("loop")
	raw = authored_damage.duplicate(true)
	raw.loop = raw
	check("cyclic authored input refuses before preparation", not Response.prepare(raw, profile, model).ok)
	raw.erase("loop")

func _actual_responses() -> void:
	var initial := Damage.initial_state(bound.damage_profile)
	var body := _body()
	var seal := var_to_bytes([bound, initial, body, motion, provider])
	var result := _transition(initial, body)
	check("actual aligned normal loads cause one persistent failure", result.ok and result.events.size() == 1 and result.modes == PackedInt64Array([1, 1]), str(result))
	if not result.ok: return
	check("actual normal sum uses one assembly capacity", absf(result.component_normal_loads_n[0] - 135.0) < 1e-9)
	check("exact spring potential release booked once", absf(result.losses[0] - 1.8225) < 1e-12
		and absf(result.before_normal.potential_j - result.after_normal.potential_j - result.losses[0]) < 1e-12)
	check("failed response lowers actual support load", absf(result.after_normal.loads[2] + 13.5) < 1e-9)
	check("failure changes no input body velocity, geometry, inertia", seal == var_to_bytes([bound, initial, body, motion, provider])
		and result.stage.rotor_system == prepared.rotor_system and result.stage.radii_m == prepared.radii_m)
	for index in 3:
		check("fixed hub retained after constitutive failure", result.stage.normal.supports[index].hub_body == prepared.normal.supports[index].hub_body)
	check("event explicitly declares boundary-only and continued weak response", result.events[0].sampling == "accepted_boundary_only_not_interval_peak"
		and not result.events[0].terminal and result.events[0].response_identity == bound.identity)
	var again := _transition(result, _body(0.04), 2)
	check("new compression retains weaker response without repeated event/loss", again.ok and again.events.is_empty() and again.losses == result.losses
		and absf(again.after_normal.loads[2] + 18.0) < 1e-9)
	check("same failure mask has stable physical stage identity", var_to_bytes(again.stage) == var_to_bytes(result.stage))
	var gentle := _transition(initial, _body(0.02))
	check("sub-capacity support remains healthy", gentle.ok and gentle.events.is_empty() and gentle.modes == initial.modes)
	var closing := _transition(initial, _body(0.02, 0.3))
	check("closing damper load participates in capacity but not fracture energy", closing.ok and closing.events.size() == 1
		and absf(closing.losses[0] - 0.81) < 1e-12)
	var unknown_raw := authored_damage.duplicate(true)
	unknown_raw.damage.components[0].erase("normal_failure_force")
	var unknown := Response.prepare(unknown_raw, profile, model)
	var unfailed := _transition(Damage.initial_state(unknown.damage_profile), _body(0.1), 1, unknown)
	check("unknown strength never manufactures failure", unfailed.ok and unfailed.events.is_empty())
	var tilted := _body()
	var q := M.q_from_euler(0.0, 0.0, 0.001)
	for i in 4: tilted[RB.ATT + i] = q[i]
	var tilted_result := _transition(initial, tilted)
	check("banked load refuses scalar structural shortcut", not tilted_result.ok)
	q = M.q_from_euler(0.7, 0.0, 0.0)
	for i in 4: tilted[RB.ATT + i] = q[i]
	check("yaw does not create structural misalignment", _transition(initial, tilted).ok)
	check("discarded path refuses transition", not Response.transition_at_boundary(bound, initial.modes, initial.losses, body, provider,
		PackedFloat64Array([0.0, 0.0, 0.0]), motion, _clock(), "response-fixture", true).ok)
	check("failed state cannot restore before first failure", not Response.select(bound, result.modes, result.losses, 0).ok)
	check("explicit initial state restores original response", var_to_bytes(Response.select(bound, initial.modes, initial.losses, 0).stage) == var_to_bytes(prepared))

func _progressive_and_independent() -> void:
	var ground_raw := authored_profile.duplicate(true)
	ground_raw.normal_profiles[0].parameters.stop_stiffness.value = 1000.0
	var resolved := Profile.resolve(ground_raw, model)
	check("progressive-stop fixture resolves", resolved.ok)
	if not resolved.ok: return
	var raw := authored_damage.duplicate(true)
	for row: Dictionary in raw.supports: row.failed_normal.stop_stiffness.value = 100.0
	var progressive := Response.prepare(raw, resolved.profile, resolved.model)
	check("weaker progressive stop binds", progressive.ok)
	if not progressive.ok: return
	var result := _transition(Damage.initial_state(progressive.damage_profile), _body(0.22), 1, progressive)
	check("progressive support force reaches declared capacity", result.ok and result.events.size() == 1)
	if result.ok:
		check("progressive stop energy contributes once to failure loss", absf(result.losses[0] - 99.09) < 1e-10
			and absf(result.before_normal.potential_j - result.after_normal.potential_j - result.losses[0]) < 1e-10)
		check("weaker stop changes actual resulting force", absf(result.after_normal.loads[2] + 123.0) < 1e-8)
	raw = authored_damage.duplicate(true)
	var ids: PackedStringArray = bound.damage_profile.installed_support_ids
	raw.damage.components = [{component_id = "left", support_ids = [ids[0]], source = "Independent left fixture leg", normal_failure_force = _q(20.0, "N")},
		{component_id = "other", support_ids = [ids[1], ids[2]], source = "Other fixture supports have unknown strength"}]
	raw.component_axes = [{component_id = "left", positive_load_axis_body = _q([0.0, 0.0, -1.0], "1")},
		{component_id = "other", positive_load_axis_body = _q([0.0, 0.0, -1.0], "1")}]
	var independent := Response.prepare(raw, profile, model)
	check("independent structural components bind", independent.ok)
	if not independent.ok: return
	result = _transition(Damage.initial_state(independent.damage_profile), _body(), 1, independent)
	check("one leg fails without duplicating capacity across other supports", result.ok and result.events.size() == 1
		and result.modes == PackedInt64Array([1, 1, 0, -1]) and absf(result.losses[0] - 0.6075) < 1e-12 and result.losses[1] == 0.0)
	if result.ok:
		check("unfailed supports retain authored full stiffness", result.stage.normal.supports[1].normal == prepared.normal.supports[1].normal
			and result.stage.normal.supports[2].normal == prepared.normal.supports[2].normal)
		check("asymmetric failed response creates real roll moment", absf(result.after_normal.loads[2] + 94.5) < 1e-9
			and absf(result.after_normal.loads[3] + 14.175) < 1e-9)

func _kernel() -> void:
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var light := _simulate(1.0, 0.8, 48)
	var heavy := _simulate(4.0, 0.8, 48)
	var hard := _simulate(1.0, 2.0, 48)
	check("same structure accepts light landing", light.sim.tick == 48 and light.sim.modes[0] == Damage.HEALTHY and light.events.is_empty())
	check("elastic support produces actual upward rebound without velocity kick", light.minimum_down_speed < -0.01)
	check("same structure fails under heavier dynamic load", heavy.sim.tick == 48 and heavy.sim.modes[0] == Damage.FAILED_ATTACHED and heavy.events.size() == 1, str(heavy.events))
	check("harder landing breaks otherwise identical light structure", hard.sim.tick == 48 and hard.sim.modes[0] == Damage.FAILED_ATTACHED and hard.events.size() == 1)
	check("failure does not freeze body or stop accepted clock", heavy.sim.tick == 48 and absf(heavy.sim.state[RB.POS + 2] - heavy.failure_down[0]) > 0.001
		and heavy.sim.fault_reason.is_empty())
	var checkpoint: Dictionary = heavy.sim.checkpoint()
	for i in 12: heavy.sim.step()
	var continued := var_to_bytes(heavy.sim.checkpoint())
	var event_count: int = heavy.events.size()
	check("continued failed support emits no repeated failure", event_count == 1 and heavy.sim.tick == 60)
	check("failed support checkpoint restores", heavy.sim.restore_checkpoint(checkpoint))
	for i in 12: heavy.sim.step()
	check("failure response and body continuation replay exactly", continued == var_to_bytes(heavy.sim.checkpoint()) and heavy.events.size() == event_count)
	Engine.physics_ticks_per_second = 480
	var refined := _simulate(4.0, 0.8, 96)
	check("refined fixture retains same failure count", refined.events.size() == 1 and refined.sim.tick == 96)
	if heavy.events.size() == 1 and refined.events.size() == 1:
		check("boundary timing converges within one coarse tick in this fixture", absf(heavy.events[0].time_s - refined.events[0].time_s) <= 1.0 / 240.0)
		check("refined potential release remains close in this fixture", absf(heavy.events[0].transition_loss_j - refined.events[0].transition_loss_j) < 0.15)
	Engine.physics_ticks_per_second = 240
	var rollback := _simulate(1.0, 2.0, 0)
	var old_body: PackedFloat64Array = rollback.sim.state.duplicate()
	rollback.sim.model.block_aux = func(_extra, _sampled): return PackedFloat64Array([NAN])
	rollback.sim.step()
	check("later kernel refusal rolls back actual failure response", rollback.sim.tick == 0 and rollback.sim.state == old_body
		and rollback.sim.modes == PackedInt64Array([0, -1]) and rollback.sim.continuous[4] == 0.0
		and rollback.events.is_empty() and not rollback.sim.fault_reason.is_empty())
	for run: Dictionary in [light, heavy, hard, refined, rollback]: run.sim.free()
	Engine.physics_ticks_per_second = saved

func _simulate(mass_kg: float, speed_mps: float, ticks: int) -> Dictionary:
	# Deliberately symmetric synthetic support geometry and closed fixed mass.
	# The actual existing normal/common-rotor/RK kernel runs; no aircraft calibration.
	var properties := live.duplicate(true)
	properties.mass_kg = mass_kg
	properties.cg_body_m = M.v3(0.0, 0.0, 0.0)
	var initial := Damage.initial_state(bound.damage_profile)
	var sim := Sim.new()
	var vehicle := Model.new()
	vehicle.state_layout_identity = Response.LAW + ":" + bound.identity
	vehicle.aux_size = 0
	vehicle.continuous_size = 4 + bound.damage_profile.components.size()
	vehicle.modes_size = Damage.MODE_STRIDE * bound.damage_profile.components.size()
	vehicle.state_validator = func(frame: Dictionary, context: Dictionary) -> bool:
		return Damage.validate_state(bound.damage_profile, frame.modes, frame.continuous.slice(4), context.tick)
	vehicle.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
		var selected := Response.select(bound, sim.modes, values.slice(4), sim.tick)
		if not selected.ok: return {}
		var stage := Stage.evaluate(selected.stage, body, values.slice(1, 4), values[0], motion, provider, time_s,
			properties, 9.80665, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0), 0.0)
		if not stage.ok: return {}
		var derivative := PackedFloat64Array([stage.shaft_rpm_rate])
		derivative.append_array(stage.wheel_rim_rates)
		derivative.append_array(PackedFloat64Array(initial.losses))
		return {loads = stage.loads, derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, 0.0), body_derivative = stage.body_derivative}
	vehicle.substeps = func(_b, _v, _t): return 4
	vehicle.endpoint_transition = func(_previous, candidate, context):
		var spin: PackedFloat64Array = candidate.continuous.slice(1, 4)
		for i in 3: spin[i] /= prepared.radii_m[i]
		var applied := Response.transition_at_boundary(bound, candidate.modes, candidate.continuous.slice(4), candidate.body,
			provider, spin, motion, {tick = context.tick, time_s = context.time_s, dt = context.dt}, "drop-fixture", context.body_filtered)
		if not applied.ok:
			printerr("transition refusal ", applied)
			return {}
		candidate.modes = applied.modes
		for i in applied.losses.size(): candidate.continuous[4 + i] = applied.losses[i]
		candidate.events = applied.events
		return candidate
	sim.mass = mass_kg
	sim.inertia = properties.inertia.duplicate()
	sim.gravity = 9.80665
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	sim.continuous.append_array(initial.losses)
	sim.modes = initial.modes.duplicate()
	check("damage normal-stage model installs", sim.set_model(vehicle))
	check("drop initializes with healthy actual support", sim.reset(_body(0.0, speed_mps)))
	var events: Array = []
	var failure_down := [0.0]
	var minimum_down_speed := speed_mps
	sim.events_located.connect(func(_tick, batch):
		events.append_array(batch.duplicate(true))
		failure_down[0] = sim.state[RB.POS + 2])
	for i in ticks:
		sim.step()
		minimum_down_speed = minf(minimum_down_speed, sim.state[RB.VEL + 2])
		if sim.tick != i + 1 or not sim.fault_reason.is_empty():
			check("actual damage drop tick accepted", false, str([i, sim.tick, sim.fault_reason]))
			break
	check("all actual damage drop ticks accepted", sim.tick == ticks)
	return {sim = sim, events = events, failure_down = failure_down, minimum_down_speed = minimum_down_speed}
