# NK-3: the optional native joint stage (sim/native_stage.gd). Without an installed library (the CI default) native
# must be absent, every prepare must refuse with a reason and the reference stage must stay installed. With a stale
# install (a mirrored GDScript source changed since the oracles verified it) native must be refused the same way.
# With a fresh install the native stage must reproduce the reference runway take-off roll byte for byte for 960 ticks,
# uninstall cleanly and refuse the P-51. Evidence and method: docs/research/native-kernel/NK-3/README.md.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")

const STIK := "jensen-das-ugly-stik-60"
const P51 := "p51d-mustang-120"
const TICKS := 960

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	call_deferred("run_all")


## A detached runway session (default field, near_runway lake, soft hull) with a deterministic take-off-roll tape.
func runway(id: String) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(str(Catalog.entry(id).data), id)
	check(id + " is flyable", session.is_flyable(), str(session.pause_reason))
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	check(id + " field and lake install", field.ok and lake.ok and session.set_field(field.field)
		and session.set_lake_context(lake.lake))
	session.start_choice = Flight.START_RUNWAY
	session.reset()
	check(id + " runway start is healthy", session.sim.fault_reason.is_empty() and session.crash.is_empty())
	session.read_raw = func() -> Dictionary:
		var tick: int = session.sim.tick
		return {roll = 0.0, pitch = 0.06 if tick >= 600 else 0.0, yaw = 0.1 if tick >= 200 and tick < 260 else 0.0,
			throttle = clampf(-1.0 + 2.0 * tick / 240.0, -1.0, 1.0)}
	return session


func advance(session: Node) -> bool:
	var tick: int = session.sim.tick
	session._physics_process(session.sim.dt())
	session.sim._physics_process(session.sim.dt())
	return session.sim.tick == tick + 1


func record(session: Node) -> PackedByteArray:
	var bytes := PackedByteArray()
	for values: Variant in [session.sim.state, session.sim.aux, session.sim.continuous, session.sim.inputs,
			session.sim.last_loads, session.sim.modes]:
		bytes.append_array(values.to_byte_array())
	return bytes


func run_all() -> void:
	var status: Dictionary = NativeStage.library_status()
	check("library status carries a reason when absent", status.ok or not str(status.reason).is_empty(), str(status))
	var stik := runway(STIK)
	var reference_stage: Callable = stik.sim.model.stage
	var reference_pre_tick: Callable = stik.sim.model.pre_tick
	check("the Stik's reference stage is the wheel evaluator", reference_stage.get_method() == &"_wheel_evaluate")
	var stage := NativeStage.new()
	check("reference identity before any install", stage.backend_identity() == NativeStage.reference_identity()
		and stage.identity_text() == NativeStage.BACKEND_REFERENCE)
	check("uninstall without an install changes nothing", not stage.uninstall(stik).is_valid()
		and stik.sim.model.stage == reference_stage)
	var prepared: Dictionary = stage.prepare(stik)
	var p51 := runway(P51)
	var p51_stage: Callable = p51.sim.model.stage
	var p51_helper := NativeStage.new()
	var p51_prepared: Dictionary = p51_helper.prepare(p51)
	check("the P-51 is refused with a reason", not p51_prepared.ok and not str(p51_prepared.reason).is_empty(),
		str(p51_prepared))
	check("a refused install leaves the P-51's stage", not p51_helper.install(p51).is_valid()
		and p51.sim.model.stage == p51_stage)
	p51.free()
	if not prepared.ok:
		# Library absent (CI default), unsupported platform, or a stale install: the reference must stay in charge.
		check("refusal carries a reason", not str(prepared.reason).is_empty(), str(prepared))
		check("refused install changes nothing", not stage.install(stik).is_valid()
			and stik.sim.model.stage == reference_stage and stik.sim.model.pre_tick == reference_pre_tick)
		check("refused helper reports the reference backend", stage.backend_identity() == NativeStage.reference_identity())
		stage.tick_context(stik, stik.sim.aux, stik.sim.inputs) # no-op while not installed
		var flew := true
		for index in 120:
			flew = flew and advance(stik)
		check("the reference stage flies after a refusal", flew and stik.sim.fault_reason.is_empty(), stik.sim.fault_reason)
		if status.ok:
			check("an installed library is refused only for a stale mirrored source",
				str(prepared.reason).begins_with("mirrored source differs"), str(prepared.reason))
		print("Native stage: library %s; refused: %s" % ["installed" if status.ok else "absent", prepared.reason])
		stik.free()
		finish()
		return
	var previous: Callable = stage.install(stik)
	check("install returns the reference stage", previous == reference_stage)
	check("the native stage is installed", stage.is_installed() and stik.sim.model.stage.get_method() == &"stage")
	check("a second install is refused", not stage.install(stik).is_valid())
	var identity: Dictionary = stage.backend_identity()
	check("native identity carries the receipt", identity.get("backend") == NativeStage.BACKEND_NATIVE
		and identity.get("backend_version") == NativeStage.BACKEND_VERSION and str(identity.get("binary_sha256", "")).length() == 64,
		str(identity))
	var reference := runway(STIK)
	var mismatches := 0
	var advanced := 0
	for index in TICKS:
		var native_ok := advance(stik)
		var reference_ok := advance(reference)
		if not native_ok or not reference_ok:
			break
		advanced += 1
		if record(stik) != record(reference):
			mismatches += 1
	check("native and reference both fly %d ticks" % TICKS, advanced == TICKS,
		"%d ticks; %s / %s" % [advanced, stik.sim.fault_reason, reference.sim.fault_reason])
	check("native trajectory is byte-identical to the reference", mismatches == 0, "%d differing ticks" % mismatches)
	check("the take-off roll moved the aircraft", absf(stik.sim.state[3]) > 1.0, str(stik.sim.state[3]))
	var removed: Callable = stage.uninstall(stik)
	check("uninstall returns the native stage", removed.get_method() == &"stage")
	check("uninstall restores the reference stage and pre_tick", stik.sim.model.stage == reference_stage
		and stik.sim.model.pre_tick == reference_pre_tick and not stage.is_installed())
	check("the reference identity is back", stage.backend_identity() == NativeStage.reference_identity())
	check("the reference stage still flies", advance(stik) and stik.sim.fault_reason.is_empty(), stik.sim.fault_reason)
	reference.free()
	stik.free()
	finish()


func finish() -> void:
	print("Native stage: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
