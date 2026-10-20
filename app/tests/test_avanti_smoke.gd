extends SceneTree

const MainScene := preload("res://main.tscn")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const WorkshopCustomization := preload("res://ui/workshop_customization.gd")
const StockSmoke := preload("res://render/smoke/stock_profile.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Trial := preload("res://workshop/trial.gd")
const WorkshopParameters := preload("res://workshop/parameters.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Geometry := preload("res://aircraft/avanti_s_blender_geometry.gd")
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const SLOT_ID := "show_tailpipe"

var _checks := 0
var _failures := 0
var _mains: Array[Node] = []
var _last_ui_profile: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)


func _run() -> void:
	_test_authored_profile_and_outlet()

	var stock: Variant = _make_main(false)
	var disabled: Variant = _make_main(true)
	if stock == null or disabled == null or stock.session == null or disabled.session == null:
		_check("Avanti production mains create flight sessions",
			stock != null and disabled != null and stock.session != null and disabled.session != null,
			"stock=%s off=%s" % [stock.startup_error if stock != null else "missing main",
				disabled.startup_error if disabled != null else "missing main"])
	else:
		_test_stock_route_and_lifecycle(stock, disabled)
		_test_exact_simulation_parity(stock, disabled)

	for main: Node in _mains:
		main.queue_free()
	await process_frame
	_test_workshop_empty_profile_precedence()
	_test_tricolor_preset_excludes_tailpipe()
	for main: Node in _mains:
		if is_instance_valid(main):
			main.queue_free()
	await process_frame
	print("Avanti smoke: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_authored_profile_and_outlet() -> void:
	var described: Dictionary = Customization.describe(AVANTI_ID)
	_check("Avanti customization bindings are accepted", bool(described.get("ok", false)),
		str(described.get("errors", [])))
	if not bool(described.get("ok", false)):
		return

	var bindings: Dictionary = described.bindings
	var profile: Dictionary = StockSmoke.profile(bindings)
	_check("stock factory returns a full Avanti presentation profile",
		not profile.is_empty() and profile.get("smoke", []).size() == 1
		and str(profile.smoke[0].get("slot", "")) == SLOT_ID)
	var other: Dictionary = Customization.describe("jensen-das-ugly-stik-60")
	_check("stock factory refuses unrelated visual families",
		other.get("ok", false) and StockSmoke.profile(other.bindings).is_empty())
	var missing_tailpipe: Dictionary = bindings.duplicate(true)
	var remaining_slots: Array = []
	for slot: Dictionary in missing_tailpipe.get("smoke_slots", []):
		if str(slot.get("id", "")) != SLOT_ID:
			remaining_slots.append(slot)
	missing_tailpipe.smoke_slots = remaining_slots
	_check("stock factory refuses missing tailpipe mount",
		StockSmoke.profile(missing_tailpipe).is_empty())

	var airplane: Dictionary = AirplaneBuilder.build(AVANTI_ID)
	if airplane.is_empty():
		_check("Avanti visual builds for the authored smoke mount check", false)
		return
	airplane.root.transform = Transform3D(Basis(Vector3.UP, 0.31), Vector3(2.0, 1.0, -3.0))
	var outlet: Vector3 = _outlet_position()
	var expected: Vector3 = airplane.root.transform * outlet
	var transforms: Dictionary = Customization.smoke_transforms(airplane)
	var actual: Transform3D = transforms.get(SLOT_ID, Transform3D.IDENTITY)
	_check("show_tailpipe transform follows generated turbine outlet coordinates",
		transforms.has(SLOT_ID) and actual.origin.is_equal_approx(expected),
		"expected=%s actual=%s" % [expected, actual.origin])
	airplane.root.free()


func _test_stock_route_and_lifecycle(stock: Variant, disabled: Variant) -> void:
	_check("normal Avanti route selects the stock smoke profile",
		stock._stock_smoke_profile and stock._profile_smoke != null
		and stock._smoke == null and stock.startup_error.is_empty(), stock.startup_error)
	_check("stock evidence identifies preset and one bounded show pool",
		stock._smoke_evidence().get("mode", "") == "stock"
		and stock._smoke_evidence().get("preset", "") == StockSmoke.PRESET_ID
		and stock._smoke_evidence().get("allocation", {}).get("capacity", 0) == 768
		and stock._smoke_evidence().get("allocation", {}).get("show_emitters", 0) == 1
		and stock._smoke_evidence().get("allocation", {}).get("slot_particles", {}).has(SLOT_ID))
	_check("--smoke=off keeps the stock identity but creates no profile renderer",
		disabled._stock_smoke_profile and disabled._profile_smoke == null
		and disabled._smoke == null and disabled._smoke_evidence().get("mode", "") == "stock"
		and disabled._smoke_evidence().get("disabled", false))

	stock._profile_smoke_tick = stock.session.sim.tick
	stock._update_profile_smoke()
	var smoke_transforms: Dictionary = Customization.smoke_transforms(stock._airplane)
	var expected: Vector3 = stock._airplane.root.global_transform * _outlet_position()
	var resolved: Transform3D = stock._profile_smoke._last_transforms.get(SLOT_ID, Transform3D.IDENTITY)
	_check("stock renderer primes its pool at the authored turbine outlet",
		smoke_transforms.has(SLOT_ID) and resolved.origin.is_equal_approx(expected),
		"expected=%s actual=%s" % [expected, resolved.origin])

	_check("Avanti source is running for the smoke request fixture",
		stock.session.propulsion_source_running(), str(stock.session.sim.modes))
	stock._unhandled_input(_h_key(false))
	_check("H enables stock smoke and the request reaches its configured maximum",
		stock._smoke_key_on and is_equal_approx(stock._profile_smoke_request(), 1.0))
	stock._unhandled_input(_h_key(true))
	_check("key echo does not toggle the held smoke request",
		stock._smoke_key_on and is_equal_approx(stock._profile_smoke_request(), 1.0))
	stock._unhandled_input(_h_key(false))
	_check("a second H press turns stock smoke off",
		not stock._smoke_key_on and is_zero_approx(stock._profile_smoke_request()))
	stock._unhandled_input(_h_key(false))
	_check("H can turn stock smoke back on for lifecycle and parity checks",
		stock._smoke_key_on and is_equal_approx(stock._profile_smoke_request(), 1.0))

	stock.session.engine_running = false
	_check("stock request is gated when accepted propulsion is stopped",
		not stock.session.propulsion_source_running() and is_zero_approx(stock._profile_smoke_request()))
	stock.session.engine_running = true
	var liquid_index: int = stock.session._liquid_index()
	var has_fuel_latch: bool = liquid_index >= 0 and stock.session.sim.continuous.size() > liquid_index + 1
	_check("Avanti fixture has an accepted finite-fuel source latch", has_fuel_latch)
	if has_fuel_latch:
		var fuel_latch: float = stock.session.sim.continuous[liquid_index + 1]
		stock.session.sim.continuous[liquid_index + 1] = 0.0
		_check("accepted fuel exhaustion gates smoke while engine mode stays on",
			stock.session.engine_running and not stock.session.propulsion_source_running()
			and is_zero_approx(stock._profile_smoke_request()))
		stock.session.sim.continuous[liquid_index + 1] = fuel_latch
	stock.session.crash = {"reason": "test gate"}
	_check("stock request is gated after crash",
		not stock.session.crash.is_empty() and is_zero_approx(stock._profile_smoke_request()))
	stock.session.crash = {}
	stock.session.sim.fault_reason = "test gate"
	_check("stock request is gated after simulation fault",
		not stock.session.sim.fault_reason.is_empty() and is_zero_approx(stock._profile_smoke_request()))
	stock.session.sim.fault_reason = ""
	stock.session.reset()
	disabled.session.reset()

	stock._unhandled_input(_h_key(false))
	var lifecycle_emitted: bool = _advance_profile_ticks(stock, 240)
	_check("stock hold request activates its bounded tailpipe emitter", lifecycle_emitted)
	stock.session.sim.set_paused(true)
	var paused_tick: int = stock._profile_smoke._last_tick
	var paused_history_size: int = stock._profile_smoke._history.size()
	stock._update_profile_smoke()
	_check("pause freezes stock smoke clock and history",
		stock._profile_smoke._last_tick == paused_tick
		and stock._profile_smoke._history.size() == paused_history_size
		and stock._profile_smoke_tick == paused_tick)
	stock.session.sim.set_paused(false)
	stock.session.reset()
	_check("reset clears H and puff history, then records the accepted tick-zero source",
		stock.session.sim.tick == 0 and not stock._smoke_key_on
		and stock._profile_request_tape == [{"tick": 0, "level": 0.0}]
		and stock._profile_source_tape == [{"tick": 0, "kind": "turbine", "running": true, "level": 1.0}]
		and stock._profile_smoke._history.is_empty() and stock._profile_smoke._last_tick == -1
		and is_zero_approx(stock._profile_smoke_request()),
		str({tick = stock.session.sim.tick, key = stock._smoke_key_on,
			request_tape = stock._profile_request_tape, source_tape = stock._profile_source_tape,
			history = stock._profile_smoke._history.size(), smoke_tick = stock._profile_smoke._last_tick,
			request = stock._profile_smoke_request()}))


func _test_exact_simulation_parity(stock: Variant, disabled: Variant) -> void:
	stock.session.reset()
	disabled.session.reset()
	stock._unhandled_input(_h_key(false))
	var before_equal: bool = _same_simulation(stock.session.sim, disabled.session.sim)
	var emitted: bool = false
	for tick_index in 240:
		stock.session.sim.step()
		disabled.session.sim.step()
		if (tick_index + 1) % 8 == 0:
			stock._update_profile_smoke()
			emitted = emitted or bool(stock._profile_smoke._emitters[SLOT_ID].emitting)
	_check("stock smoke-on and --smoke=off sessions start from identical states", before_equal)
	_check("parity fixture advances exactly 240 fault-free ticks with accepted inputs",
		stock.session.sim.tick == 240 and disabled.session.sim.tick == 240
		and stock.session.sim.fault_reason.is_empty() and disabled.session.sim.fault_reason.is_empty()
		and not stock.session.sim.inputs.is_empty() and not disabled.session.sim.inputs.is_empty())
	_check("stock hold request emits at least one scheduled tailpipe interval", emitted)
	_check("stock smoke leaves every simulation channel bit-identical after 240 equal ticks",
		_same_simulation(stock.session.sim, disabled.session.sim),
		"stock_tick=%d off_tick=%d" % [stock.session.sim.tick, disabled.session.sim.tick])


func _test_workshop_empty_profile_precedence() -> void:
	var described: Dictionary = Customization.describe(AVANTI_ID)
	if not bool(described.get("ok", false)):
		_check("Workshop empty-profile fixture has Avanti bindings", false, str(described.get("errors", [])))
		return
	var data_path: String = str(Catalog.entry(AVANTI_ID).get("data", ""))
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(data_path)
	var empty_profile: Dictionary = Presentation.defaults(described.bindings)
	var frozen: Dictionary = Trial.freeze({
		"base_id": AVANTI_ID,
		"base_bytes": base_bytes,
		"recipe": WorkshopParameters.defaults(),
		"presentation_profile": empty_profile,
	})
	_check("Workshop can freeze an Avanti trial with an explicit empty smoke choice",
		bool(frozen.get("ok", false))
		and frozen.get("presentation_profile", {}).get("smoke", []).is_empty(),
		str(frozen.get("errors", [])))
	if not bool(frozen.get("ok", false)):
		return
	var main: Variant = _make_main(false, frozen)
	_check("explicit empty Workshop choice suppresses the Avanti stock smoke default",
		main.startup_error.is_empty() and not main._stock_smoke_profile
		and main._profile_smoke == null and main._smoke == null,
		"startup_error=%s evidence=%s" % [main.startup_error, main._smoke_evidence()])


func _test_tricolor_preset_excludes_tailpipe() -> void:
	var described: Dictionary = Customization.describe(AVANTI_ID)
	if not bool(described.get("ok", false)):
		_check("Tricolor fixture has Avanti smoke bindings", false, str(described.get("errors", [])))
		return
	var inspector: Node = WorkshopCustomization.new()
	inspector.page_kind = "smoke"
	inspector.profile_changed.connect(_capture_ui_profile)
	root.add_child(inspector)
	inspector.configure(described.bindings, Presentation.defaults(described.bindings))
	inspector.apply_preset(3)
	var smoke: Array = _last_ui_profile.get("smoke", [])
	var includes_tailpipe := false
	for entry: Dictionary in smoke:
		includes_tailpipe = includes_tailpipe or str(entry.get("slot", "")) == SLOT_ID
	_check("Tricolor exposes all four show mounts but authors only three entries",
		inspector._slot.item_count == 4 and smoke.size() == 3 and not includes_tailpipe,
		"slots=%d smoke=%s" % [inspector._slot.item_count, smoke])
	inspector.free()


func _capture_ui_profile(profile: Dictionary) -> void:
	_last_ui_profile = profile.duplicate(true)


func _advance_profile_ticks(main: Variant, ticks: int) -> bool:
	var emitted := false
	for index in ticks:
		main.session.sim.step()
		if (index + 1) % 8 == 0:
			main._update_profile_smoke()
			emitted = emitted or bool(main._profile_smoke._emitters[SLOT_ID].emitting)
	return emitted


func _same_simulation(a: Variant, b: Variant) -> bool:
	if a.tick != b.tick or not a.fault_reason.is_empty() or not b.fault_reason.is_empty():
		return false
	return a.state == b.state and a.previous == b.previous and a.aux == b.aux \
		and a.inputs == b.inputs and a.modes == b.modes and a.continuous == b.continuous \
		and a.last_loads == b.last_loads and a.fault_reason == b.fault_reason


func _make_main(smoke_off: bool, trial: Dictionary = {}) -> Variant:
	var args := PackedStringArray([
		"--aircraft=" + AVANTI_ID,
		"--start=airborne",
		"--soundscape=off",
		"--crash-effects=off",
		"--accident-report=off",
	])
	if smoke_off:
		args.append("--smoke=off")
	var main: Variant = MainScene.instantiate()
	main.aircraft_id = AVANTI_ID
	main.user_args = args
	main.workshop_trial = trial
	main.external_controller_selection = true
	main.crash_effects_enabled = false
	main.accident_reports_enabled = false
	main.set_process(false)
	main.set_physics_process(false)
	main.set_process_unhandled_input(false)
	root.add_child(main)
	_disable_flight(main)
	_mains.append(main)
	return main


func _disable_flight(main: Variant) -> void:
	main.set_process(false)
	main.set_physics_process(false)
	main.set_process_unhandled_input(false)
	if main.session == null:
		return
	main.session.input_enabled = false
	main.session.set_process(false)
	main.session.set_physics_process(false)
	main.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	main.session.sim.set_process(false)
	main.session.sim.set_physics_process(false)


func _h_key(echo: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_H
	event.keycode = KEY_H
	event.pressed = true
	event.echo = echo
	return event


func _outlet_position() -> Vector3:
	var raw: Array = Geometry.DATA.get("turbine", {}).get("outlet_position", [])
	if raw.size() != 3:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

