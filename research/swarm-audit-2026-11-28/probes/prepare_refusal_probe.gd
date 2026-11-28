extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const ElectricAdapter := preload("res://sim/native/electric_stage_adapter.gd")
const ID := "stik-electric-6s"

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	run.call_deferred()

func session() -> Node:
	var s: Node = Flight.new()
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_REFERENCE)
	s.setup(Catalog.data_for(ID, Catalog.default_battery_mode(ID)), ID)
	return s

func run() -> void:
	var control := session()
	var s := session()
	var ordinary: Dictionary = NativeConfiguration.prepare(s, ElectricAdapter.config_for)
	if not ordinary.get("ok", false) or s.aircraft.is_read_only():
		printerr("PRECONDITION_FAILED ", ordinary.get("reason"))
		s.free()
		control.free()
		quit(1)
		return
	var meta := {"source": "private numeric fixture"}
	for i in 35:
		meta = {"item": meta}
	s.aircraft.audit_fixture_metadata = meta
	var annotated: Dictionary = NativeConfiguration.prepare(s, ElectricAdapter.config_for)
	var captured: bool = annotated.get("ok", false) and annotated.identity.session_values.aircraft.has("audit_fixture_metadata")
	var same_config: bool = captured and var_to_bytes(ordinary.config) == var_to_bytes(annotated.config)
	print("REFUSAL_PRECONDITIONS captured_metadata=", captured, " identical_native_config=", same_config,
		" writable_before_outer_prepare=", not s.aircraft.is_read_only())
	if not same_config or s.aircraft.is_read_only():
		s.free()
		control.free()
		quit(1)
		return
	var admitted := NativeStage.new()
	var positive: Dictionary = admitted.prepare(control)
	if not positive.get("ok", false):
		print("REFUSAL_NATIVE_UNAVAILABLE ", positive.get("reason"))
		s.free()
		control.free()
		print("REFUSAL_PROBE_COMPLETED")
		quit()
		return
	admitted.install(control)
	if not admitted.is_installed():
		printerr("Positive control did not install its actual native stage")
		s.free()
		control.free()
		quit(1)
		return
	var stage := NativeStage.new()
	var old_stage: Callable = s.sim.model.stage
	var late: Dictionary = stage.prepare(s)
	var refuses: bool = not late.get("ok", true) and not stage.is_installed() and s.sim.model.stage == old_stage
	var writable: bool = not s.aircraft.is_read_only() and not s.aircraft.model.is_read_only() and not s._hull_contact.is_read_only()
	print("REFUSAL_NATIVE_RESULT refused=", refuses, " writable_after_outer_prepare=", writable, " reason=", late.get("reason"))
	s.free()
	control.free()
	print("REFUSAL_PROBE_COMPLETED")
	quit(0 if refuses and writable else 1)
