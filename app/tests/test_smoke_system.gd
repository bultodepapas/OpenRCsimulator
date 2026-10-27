extends SceneTree

const Smoke := preload("res://render/smoke/smoke_system.gd")
const Stock := preload("res://render/smoke/stock_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Builder := preload("res://render/airplane.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Trial := preload("res://workshop/trial.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Cadence := preload("res://render/presentation_cadence.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prop := {"id": "engine_left", "kind": "glow_prop", "idle_rpm": 2000.0, "max_rpm": 12000.0}
	var saved := prop.duplicate(true)
	var idle := Smoke.source_observation(prop, 2000.0, 0.0, true)
	var load := Smoke.source_observation(prop, 9000.0, 0.8, true)
	check("accepted source load responds to RPM", load.level > idle.level and idle.level > 0.0)
	check("source cutoff ignores windmilling RPM", Smoke.source_observation(prop, 9000.0, 0.8, false).level == 0.0)
	check("nonfinite input fails closed", not Smoke.source_observation(prop, NAN, 0.8, true).running)
	check("observation does not mutate physical data", prop == saved)
	check("source aliases share one accepted engine", Smoke.source_map(load)["$propulsion"] == Smoke.source_map(load).engine_left)
	var gasoline := prop.duplicate(true)
	gasoline.liquid_fuel = {"law": "gasoline_bsfc_v1"}
	check("gasoline appearance is separate from solver kind", Smoke.emissions_family(gasoline) == "gasoline_light")
	check("electric and turbine sources default clear", Smoke.emissions_family({"kind": "electric_prop"}) == "electric_clear"
		and Smoke.emissions_family({"kind": "turbine"}) == "turbine_clear")
	for id: String in ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t",
			"gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"]:
		var described := Customization.describe(id)
		check(id + " has verified outlet contract", bool(described.get("ok", false)), str(described.get("errors", [])))
		if not bool(described.get("ok", false)): continue
		var airplane := Builder.build(id)
		root.add_child(airplane.root)
		var transforms := Customization.smoke_transforms(airplane)
		check(id + " resolves every authored outlet", transforms.size() == described.bindings.smoke_slots.size())
		airplane.root.position = Vector3(3.0, 2.0, 1.0)
		var moved := Customization.smoke_transforms(airplane)
		var attached := true
		for slot: String in transforms:
			attached = attached and (moved[slot].origin - transforms[slot].origin).is_equal_approx(Vector3(3, 2, 1))
		check(id + " cached outlets follow rendered model", attached)
		airplane.root.free()
	var heli: Node = load("res://helicopter_main.gd").new()
	var capability: Dictionary = heli.smoke_capabilities()
	check("rotorcraft reports unverified outlet pairing explicitly", not capability.source_available
		and not capability.show_available and not str(capability.reason).is_empty())
	heli.free()
	await _main_checks()
	print("Unified smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _main_checks() -> void:
	var described := Customization.describe("jensen-das-ugly-stik-60")
	if not bool(described.get("ok", false)): return
	var empty := Presentation.defaults(described.bindings)
	var frozen := Trial.freeze({"base_id": "jensen-das-ugly-stik-60",
		"base_bytes": FileAccess.get_file_as_bytes(Catalog.entry("jensen-das-ugly-stik-60").data),
		"recipe": {}, "presentation_profile": empty})
	check("explicit empty profile freezes", bool(frozen.get("ok", false)))
	if not bool(frozen.get("ok", false)): return
	var no_smoke: Node = load("res://main.tscn").instantiate()
	no_smoke.set_user_args(PackedStringArray(["--scenery=off", "--birds=off", "--soundscape=off"]))
	no_smoke.workshop_trial = frozen
	no_smoke.crash_effects_enabled = false
	root.add_child(no_smoke)
	await process_frame
	no_smoke.set_process(false)
	no_smoke.session.set_physics_process(false)
	no_smoke.session.sim.set_physics_process(false)
	check("explicit empty Stik selection suppresses every backend", no_smoke._smoke == null and no_smoke._profile_smoke == null)
	check("empty selection remains visible in evidence", no_smoke._smoke_evidence().mode == "profile")
	no_smoke.queue_free()
	await process_frame
	Cadence.override_every_frames = 1 # VQ-01c-R1 default: accepted ticks wait for the next rendered frame
	var stock: Node = load("res://main.tscn").instantiate()
	Cadence.override_every_frames = -1
	stock.set_user_args(PackedStringArray(["--scenery=off", "--birds=off", "--soundscape=off", "--smoke-pump=on"]))
	stock.crash_effects_enabled = false
	root.add_child(stock)
	await process_frame
	stock.set_process(false)
	stock.session.set_physics_process(false)
	stock.session.sim.set_physics_process(false)
	check("stock Stik uses shared profile renderer", stock._profile_smoke != null and stock._smoke == null, stock.startup_error)
	if stock._profile_smoke != null:
		var budget: Dictionary = stock._profile_smoke.budget_info()
		check("natural and show outlets share bounded allocation", int(budget.get("capacity", 0)) <= 768
			and int(budget.get("source_emitters", 0)) == 1 and int(budget.get("show_emitters", 0)) == 1)
		var physical: PackedFloat64Array = stock.session.sim.state.duplicate()
		var continuous: PackedFloat64Array = stock.session.sim.continuous.duplicate()
		stock._sample_profile_smoke(stock.session.sim.tick, stock.session.sim.time(), physical,
			PackedFloat64Array(), stock.session.sim.inputs, stock.session.sim.aux)
		stock._update_smoke()
		check("presentation leaves accepted simulation state untouched", physical == stock.session.sim.state
			and continuous == stock.session.sim.continuous)
		stock.session.reset()
		stock._update_profile_smoke(0.0)
		stock._smoke_key_on = true
		stock.session.sim.set_paused(false)
		stock.session.sim.step()
		check("a consecutive accepted tick waits for the frame's observer flush", stock._profile_request_tape.is_empty())
		stock._flush_presentation_observers()
		stock._update_profile_smoke(0.002)
		check("future accepted request waits for displayed pose", stock._profile_smoke_tick == 0
			and stock._profile_request_tape.size() == 1 and stock._profile_request_tape[0].tick == 1
			and stock._profile_presented_request == 0.0)
		stock._update_profile_smoke(1.0 / 240.0)
		check("request enters at matching presented tick", stock._profile_smoke_tick == 1
			and stock._profile_request_tape.is_empty() and stock._profile_presented_request == 1.0
			and stock._profile_smoke.budget_info().fault.is_empty())
		_accepted_wash_checks(stock)
		_fractional_source_checks(stock)
		stock.session.crash = {"smoke_test": true}
		check("crash gates new show requests", stock._profile_smoke_request() == 0.0)
	stock.queue_free()
	await process_frame


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _accepted_wash_checks(stock: Node) -> void:
	var state: PackedFloat64Array = stock.session.sim.state.duplicate()
	var continuous: PackedFloat64Array = stock.session.sim.continuous.duplicate()
	var auxiliary: PackedFloat64Array = stock.session.sim.aux.duplicate()
	var modes: PackedInt64Array = stock.session.sim.modes.duplicate()
	var inputs: PackedFloat64Array = stock.session.sim.inputs.duplicate()
	var fixture: Dictionary = AircraftData.load_file(Catalog.entry("p51d-mustang-120").data)
	check("qualified prop-wash fixture loads", bool(fixture.get("ok", false)))
	if not bool(fixture.get("ok", false)): return
	var prop: Dictionary = fixture.model.propulsion
	var accepted_time: float = stock.session.sim.time()
	# A detached numerical RPM fixture exercises the conversion without changing
	# accepted RPM, controls or engine state in the session.
	var reference: Vector3 = stock._profile_smoke_wash(prop, state, 7500.0, accepted_time, true)
	check("accepted wash numerical fixture has finite nonzero velocity", reference.is_finite() and reference.length() > 0.01)
	var original_transform: Transform3D = stock._airplane.root.transform
	for scale_factor: float in [0.1, 1.0, 5.0]:
		stock._airplane.root.basis = Basis(Vector3.UP, 1.2).scaled(Vector3.ONE * scale_factor)
		var wash: Vector3 = stock._profile_smoke_wash(prop, state, 7500.0, accepted_time, true)
		check("accepted wash ignores rendered %.1fx scale and stale orientation" % scale_factor,
			wash.is_equal_approx(reference), str(wash) + " vs " + str(reference))
	stock._airplane.root.transform = original_transform
	check("accepted cutoff removes wash despite numerical windmilling RPM",
		stock._profile_smoke_wash(prop, state, 7500.0, accepted_time, false) == Vector3.ZERO)
	var original_version: int = int(stock._profile_smoke._profile.version)
	stock._profile_smoke._profile.version = 1
	check("historical v1 profiles keep zero added wash",
		stock._profile_smoke_wash(prop, state, 7500.0, accepted_time, true) == Vector3.ZERO)
	stock._profile_smoke._profile.version = original_version
	check("accepted wash observation leaves all physical arrays unchanged", state == stock.session.sim.state
		and continuous == stock.session.sim.continuous and auxiliary == stock.session.sim.aux
		and modes == stock.session.sim.modes and inputs == stock.session.sim.inputs)


func _fractional_source_checks(stock: Node) -> void:
	# Advance real accepted ticks before presenting the detached source tape below.
	# The synthetic cut verifies presentation ordering; it is not a fuel experiment.
	stock.session.sim.step()
	stock.session.sim.step()
	var state: PackedFloat64Array = stock.session.sim.state.duplicate()
	var continuous: PackedFloat64Array = stock.session.sim.continuous.duplicate()
	var auxiliary: PackedFloat64Array = stock.session.sim.aux.duplicate()
	var modes: PackedInt64Array = stock.session.sim.modes.duplicate()
	var inputs: PackedFloat64Array = stock.session.sim.inputs.duplicate()
	var source_kind: String = Propulsion.source_kind(stock.session.aircraft.model.propulsion)
	var expected_wash := Vector3(0, 0, 3)
	stock._profile_presented_running = true
	stock._profile_presented_level = 0.5
	stock._profile_presented_wash = expected_wash
	stock._profile_request_tape.clear()
	stock._profile_source_tape = [{"tick": 2, "kind": source_kind, "running": false, "level": 0.0, "wash_mps": Vector3.ZERO}]
	stock._update_profile_smoke(1.5 / 240.0)
	var source_emitter: GPUParticles3D = stock._profile_smoke._emitters.source_exhaust
	var material: ShaderMaterial = source_emitter.process_material
	var wash_values: PackedVector3Array = material.get_shader_parameter("birth_event_wash")
	check("future cutoff cannot remove prior presented wash", stock._profile_source_tape.size() == 1
		and stock._profile_presented_wash == expected_wash and wash_values[0] == expected_wash)
	stock._update_profile_smoke(2.25 / 240.0)
	wash_values = material.get_shader_parameter("birth_event_wash")
	var times: PackedFloat32Array = material.get_shader_parameter("birth_event_times")
	var levels: PackedFloat32Array = material.get_shader_parameter("birth_event_levels")
	check("accepted cutoff and wash share the exact fractional birth boundary",
		int(material.get_shader_parameter("birth_event_count")) == 2
		and wash_values[0] == expected_wash and wash_values[1] == Vector3.ZERO
		and absf(times[1] - 0.5 / 240.0) < 0.000001 and levels[0] == 0.5 and levels[1] == 0.0)
	check("presented cutoff becomes the next wash baseline", stock._profile_presented_wash == Vector3.ZERO
		and not stock._profile_presented_running and stock._profile_source_tape.is_empty())
	var emitter_id := source_emitter.get_instance_id()
	var presented_before: float = stock._profile_presented_s
	var history_before: Array = stock._profile_smoke._history.duplicate(true)
	stock._profile_source_tape = [{"tick": 3, "kind": source_kind, "running": true, "level": 0.5, "wash_mps": expected_wash}]
	var queued_before: Array = stock._profile_source_tape.duplicate(true)
	stock.session.sim.set_paused(true)
	stock._update_profile_smoke(2.1 / 240.0)
	stock.session.sim.set_paused(false)
	stock._update_profile_smoke(2.1 / 240.0)
	check("pause fraction rollback retains puffs and queued accepted events",
		stock._profile_smoke._emitters.source_exhaust.get_instance_id() == emitter_id
		and stock._profile_presented_s == presented_before and stock._profile_source_tape == queued_before
		and stock._profile_smoke._history == history_before)
	stock._update_profile_smoke(2.8 / 240.0)
	check("fractional presentation resumes when the clock catches up", stock._profile_presented_s > presented_before
		and stock._profile_smoke._emitters.source_exhaust.get_instance_id() == emitter_id
		and stock._profile_smoke.budget_info().fault.is_empty())
	# Model an observer that previously saw a later accepted tick. Only detached
	# presentation bookkeeping changes; the physical tick/state stay untouched.
	stock._profile_last_accepted_tick = stock.session.sim.tick + 1
	stock._update_profile_smoke(2.8 / 240.0)
	check("accepted-tick rewind clears and reprimes instead of retaining old puffs",
		stock._profile_smoke._emitters.source_exhaust.get_instance_id() != emitter_id
		and stock._profile_source_tape.is_empty() and stock._profile_smoke._last_tick == 2)
	check("fractional source and rewind presentation leave physical arrays unchanged", state == stock.session.sim.state
		and continuous == stock.session.sim.continuous and auxiliary == stock.session.sim.aux
		and modes == stock.session.sim.modes and inputs == stock.session.sim.inputs)
