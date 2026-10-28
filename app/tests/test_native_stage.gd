# NK-3: the optional native joint stage (sim/native_stage.gd). Without an installed library (the CI default) native
# must be absent, every prepare must refuse with a reason and the reference stage must stay installed. With a stale
# install (a mirrored GDScript source changed since the oracles verified it) native must be refused the same way.
# With a fresh install the native stage must reproduce the reference runway take-off roll byte for byte for 960 ticks,
# uninstall cleanly and admit the qualified finite-liquid P-51. Evidence and method: docs/research/native-kernel/NK-3/README.md.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const NativePackage := preload("res://app_state/native_package.gd")

const STIK := "jensen-das-ugly-stik-60"
const P51 := "p51d-mustang-120"
const TICKS := 960

var checks := 0
var failures := 0
var _native_exercised := false
var _finished := false


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


func test_complete_manifest() -> void:
	var digest := "a".repeat(64)
	var engine_version := "fixture-engine"
	var manifest := {
		format = NativePackage.MANIFEST_FORMAT, platform = "linux", architecture = "x86_64",
		engine_version = engine_version, solver_sha256 = digest,
		native_receipt = {
			format = "openrc-native-kernel-receipt", backend = "native", backend_version = NativeStage.BACKEND_VERSION,
			abi_version = NativeStage.ABI_VERSION, platforms = {"linux": {
				platform = "linux", architecture = "x86_64", backend = "native",
				backend_version = NativeStage.BACKEND_VERSION, abi_version = NativeStage.ABI_VERSION, engine_version = engine_version,
				binary_sha256 = digest, source_sha256 = digest, lock_sha256 = digest, engine_sha256 = digest,
				mirrored_sources = {"app/physics/aero.gd": digest},
			}},
		},
		qualification_sources = {
			"session_probe.gd": digest, "test_native_stage.gd": digest,
			"test_native_session.gd": digest, "test_native_replay.gd": digest,
			"test_native_helicopter_session.gd": digest, "test_heli_restore_radio.gd": digest,
		},
	}
	check("complete native package manifest is accepted", NativePackage._complete_manifest(manifest))
	var json_numbers: Dictionary = manifest.duplicate(true)
	json_numbers.native_receipt.abi_version = float(NativeStage.ABI_VERSION)
	json_numbers.native_receipt.platforms.linux.abi_version = float(NativeStage.ABI_VERSION)
	check("JSON numeric ABI is accepted", NativePackage._complete_manifest(json_numbers))

	for field: String in ["format", "backend", "backend_version"]:
		var bad: Dictionary = manifest.duplicate(true)
		bad.native_receipt[field] = "invalid"
		check("invalid receipt envelope " + field + " is rejected", not NativePackage._complete_manifest(bad))
	for abi: Variant in [null, false, true, "2", [], 0, 1, 2.5]:
		var bad_envelope: Dictionary = manifest.duplicate(true)
		bad_envelope.native_receipt.abi_version = abi
		check("invalid receipt ABI is rejected: " + str(abi), not NativePackage._complete_manifest(bad_envelope))
		var bad_row: Dictionary = manifest.duplicate(true)
		bad_row.native_receipt.platforms.linux.abi_version = abi
		check("invalid Linux ABI is rejected: " + str(abi), not NativePackage._complete_manifest(bad_row))
	for platforms: Variant in [null, [], {}, {"linux": null}]:
		var bad: Dictionary = manifest.duplicate(true)
		bad.native_receipt.platforms = platforms
		check("missing or malformed Linux receipt is rejected: " + str(platforms), not NativePackage._complete_manifest(bad))
	for field: String in ["backend", "backend_version", "platform", "architecture", "engine_version"]:
		var bad: Dictionary = manifest.duplicate(true)
		bad.native_receipt.platforms.linux[field] = "invalid"
		check("invalid Linux receipt " + field + " is rejected", not NativePackage._complete_manifest(bad))

	for field: String in ["binary_sha256", "source_sha256", "lock_sha256", "engine_sha256"]:
		for invalid_digest: Variant in [null, 1, "", "a".repeat(63), "g".repeat(64)]:
			var bad: Dictionary = manifest.duplicate(true)
			bad.native_receipt.platforms.linux[field] = invalid_digest
			check("invalid Linux digest " + field + " is rejected: " + str(invalid_digest),
				not NativePackage._complete_manifest(bad))
	for sources: Variant in [null, [], {}, {"other/aero.gd": digest}, {"app/physics/aero.gd": "bad"}, {1: digest}]:
		var bad: Dictionary = manifest.duplicate(true)
		bad.native_receipt.platforms.linux.mirrored_sources = sources
		check("missing or malformed mirrored sources are rejected: " + str(sources), not NativePackage._complete_manifest(bad))
	for name: String in NativePackage.DIAGNOSTICS:
		var missing: Dictionary = manifest.duplicate(true)
		missing.qualification_sources.erase(name)
		check("missing diagnostic is rejected: " + name, not NativePackage._complete_manifest(missing))
	var extra: Dictionary = manifest.duplicate(true)
	extra.qualification_sources["unexpected.gd"] = digest
	check("unexpected diagnostic is rejected", not NativePackage._complete_manifest(extra))
	var bad_diagnostic: Dictionary = manifest.duplicate(true)
	bad_diagnostic.qualification_sources["test_native_stage.gd"] = "g".repeat(64)
	check("malformed diagnostic digest is rejected", not NativePackage._complete_manifest(bad_diagnostic))


func run_all() -> void:
	test_complete_manifest()
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
	check("P-51 preparation shares the qualified library gate", p51_prepared.ok == prepared.ok, str(p51_prepared))
	if prepared.ok:
		check("P-51 installs its finite-liquid native stage", p51_helper.install(p51) == p51_stage)
		var p51_reference := runway(P51)
		var matched := true
		for _tick in 32:
			matched = advance(p51) and advance(p51_reference) and record(p51) == record(p51_reference) and matched
		check("P-51 native finite-liquid ticks match", matched)
		p51_helper.uninstall(p51)
		p51_reference.free()
	else:
		check("unavailable native library leaves P-51 reference intact", not str(p51_prepared.reason).is_empty()
			and not p51_helper.install(p51).is_valid() and p51.sim.model.stage == p51_stage)
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
	_native_exercised = true
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
	_finished = true
	print("Native stage: %d checks, %d failed" % [checks, failures])
	if _native_exercised and checks > 0 and failures == 0:
		print("NK3_NATIVE_STAGE_NATIVE verdict=pass")
	quit(1 if failures > 0 else 0)
