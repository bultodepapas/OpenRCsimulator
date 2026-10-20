extends SceneTree

const Smoke := preload("res://render/smoke/smoke_system.gd")
const Stock := preload("res://render/smoke/stock_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Builder := preload("res://render/airplane.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Trial := preload("res://workshop/trial.gd")
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
	var stock: Node = load("res://main.tscn").instantiate()
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
		stock.session.crash = {"smoke_test": true}
		check("crash gates new show requests", stock._profile_smoke_request() == 0.0)
	stock.queue_free()
	await process_frame


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)
