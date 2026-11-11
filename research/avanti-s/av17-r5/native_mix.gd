## AV-17-R5: bounded production NativeStage ownership / flap-mix replay comparison.
## Loads the existing temporary research library, never installs an app library.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Profile := preload("res://input/controller_profile.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := "res://data/aircraft/sebart_avanti_s_a200.json"
const INFO := {guid = "native-mix-radio", name = "Native mix fixture", vendor_id = 0x1209, product_id = 0x4f54}
const ENGINE_SHA := "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
const TICKS := 192
const CHECKPOINT_TICK := 96

var checks := 0
var failures := 0
var notes: Array[String] = []
var out := ""
var receipt := {}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty():
		printerr("Expected --out=<directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		var message := label + " " + detail
		notes.append(message)
		printerr("FAIL ", message)


func temp_library() -> bool:
	var root := ProjectSettings.globalize_path("res://../tmp/native-kernel/")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("build-receipt.json")))
	if not parsed is Dictionary:
		check("temporary build receipt parses", false)
		return false
	receipt = parsed
	var row := receipt.duplicate(true)
	row.mirrored_sources = receipt.get("reference_sources_sha256", {})
	var binary := root.path_join("lib/libopenrc_native_kernel.so")
	var descriptor := root.path_join("openrc_native_kernel.gdextension")
	var valid: bool = receipt.get("backend_version") == NativeStage.BACKEND_VERSION \
		and int(receipt.get("abi_version", 0)) == NativeStage.ABI_VERSION and not receipt.get("mutant", true) \
		and FileAccess.get_sha256(binary) == receipt.get("binary_sha256") \
		and FileAccess.get_sha256(OS.get_executable_path()) == ENGINE_SHA \
		and NativeStage._source_error(row).is_empty()
	check("temporary build, engine and mirrored source identity", valid)
	if not valid: return false
	# The normal source-install loader uses a production descriptor. This research-only
	# loader names the checked temporary binary, then uses the real session adapter.
	NativeStage._library_error = NativeStage._initialize_library(descriptor, row)
	NativeStage._library_checked = true
	check("temporary extension loads through native class/ABI check", NativeStage._library_error.is_empty(), NativeStage._library_error)
	return NativeStage._library_error.is_empty()


func fixture(mode: String) -> Node:
	var f := Flight.new()
	f.input_enabled = true
	f.crash_auto_restart = false
	check("select " + mode, f.setup_stage_backend(mode))
	f.setup(AIRCRAFT)
	check("flyable " + mode, f.is_flyable(), str(f.pause_reason))
	if not f.is_flyable(): return f
	f.sim.state[RB.POS + 2] = -500.0
	f.sim.previous = f.sim.state.duplicate()
	f.trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	f.commands = {roll = 0.02, pitch = 0.1, yaw = -0.03, throttle = 0.45}
	f._flap_requested = 1.0
	f.radio.connect_device(42, INFO, Profile.defaults("radio", "radio_custom"))
	return f


func physical(f: Node) -> PackedByteArray:
	return var_to_bytes([f.sim.tick, f.sim.state, f.sim.previous, f.sim.aux, f.sim.continuous,
		f.sim.inputs, f.sim.last_loads, f.sim.modes, f.sim.last_events])


func step_pair(native: Node, reference: Node, inputs: PackedFloat64Array, owner: String, replay: bool) -> bool:
	var helper: RefCounted = native._native_stage
	if helper == null: return false
	var before: Dictionary = helper.stage_stats()
	for f: Node in [native, reference]:
		if replay and not f.restore_input_mix_owner(owner): return false
		f.sim.inputs = inputs.duplicate()
		f.sim.step()
	var after: Dictionary = helper.stage_stats()
	return native._native_stage == helper and helper.owns_stage(native) \
		and native.stage_backend_identity().get("backend") == "native" \
		and int(after.get("stage_calls", 0)) - int(before.get("stage_calls", 0)) >= 4 \
		and int(after.get("context_calls", 0)) - int(before.get("context_calls", 0)) >= 1 \
		and native.sim.tick == reference.sim.tick and native.sim.fault_reason.is_empty() \
		and reference.sim.fault_reason.is_empty() and native.crash.is_empty() and reference.crash.is_empty() \
		and physical(native) == physical(reference) and native.flap_mix_owner() == owner \
		and reference.flap_mix_owner() == owner


func run() -> void:
	if not temp_library():
		finish({})
		return
	var reference := fixture("gdscript_reference")
	var native := fixture("native")
	var owned: bool = native._native_stage != null and native._native_stage.owns_stage(native) \
		and native.stage_backend_identity().get("backend") == "native"
	check("native session owns actual stage", owned, str(native.stage_backend_status()))
	check("reference session owns reference stage", reference.stage_backend_identity().get("backend") == "gdscript_reference")
	if not owned or not native.is_flyable() or not reference.is_flyable():
		native.free()
		reference.free()
		finish({})
		return
	check("initial physical bytes match", physical(native) == physical(reference))
	var rows: Array[Dictionary] = []
	var cp_n := {}
	var cp_r := {}
	var cp_physical := PackedByteArray()
	var samples := {}
	var completed := 0
	var counters_before: Dictionary = native._native_stage.stage_stats()
	for i: int in TICKS:
		var owner := "transmitter" if i >= 64 and i < 128 else "simulator"
		if i == 64 or i == 128:
			for f: Node in [native, reference]:
				var profile: Dictionary = f.radio.profile.duplicate(true)
				profile.flap_elevator_mix_owner = owner
				check("activate " + owner, f.radio.use_profile(profile, "native fixture"))
		var n_input: PackedFloat64Array = native._inputs()
		var r_input: PackedFloat64Array = reference._inputs()
		if n_input.to_byte_array() != r_input.to_byte_array() or not step_pair(native, reference, r_input, owner, false):
			check("matched native/reference step %d" % (i + 1), false,
				str(native.stage_backend_status()) + " / " + native.sim.fault_reason + " / " + reference.sim.fault_reason)
			break
		completed += 1
		rows.append({tick = i + 1, owner = owner, inputs = r_input.duplicate(), physical = physical(reference)})
		if i in [59, 95, 159]:
			samples[str(i + 1)] = {owner = owner, pitch = r_input[1], flap_demand = r_input[reference.flap_input_index()],
				flap_actual = reference.sim.aux[reference.flap_aux_index()], diagnostics = Array(reference.flap_mix_diagnostics())}
		if completed == CHECKPOINT_TICK:
			cp_n = native.checkpoint()
			cp_r = reference.checkpoint()
			cp_physical = physical(reference)
	var counters_after: Dictionary = native._native_stage.stage_stats()
	check("all 192 owner-switch ticks execute and match", completed == TICKS, str(completed))
	check("nonzero flap and pitch reach both mix modes", samples.size() == 3 \
		and samples["60"].pitch != 0.0 and samples["60"].flap_actual > 0.0 \
		and samples["60"].diagnostics[0] < 0.0 and samples["96"].flap_actual > 0.0 \
		and samples["96"].diagnostics[0] == 0.0 and samples["160"].diagnostics[0] < 0.0, str(samples))
	check("transmitter checkpoints record owner and matching simulation bytes", not cp_n.is_empty() and not cp_r.is_empty() \
		and cp_n.get("flap_mix_owner") == "transmitter" and cp_r.get("flap_mix_owner") == "transmitter" \
		and cp_n.get("stage_backend", {}).get("backend") == "native" \
		and var_to_bytes(cp_n.get("simulation")) == var_to_bytes(cp_r.get("simulation")))
	var restored := false
	if completed == TICKS and not cp_n.is_empty() and not cp_r.is_empty():
		restored = native.restore_checkpoint(cp_n) and reference.restore_checkpoint(cp_r)
	check("both transmitter checkpoints restore with native owner", restored and not native.input_enabled \
		and not reference.input_enabled and native.flap_mix_owner() == "transmitter" \
		and reference.flap_mix_owner() == "transmitter" and physical(native) == cp_physical \
		and physical(reference) == cp_physical and native._native_stage != null and native._native_stage.owns_stage(native))
	var replayed := 0
	var replay_before := {}
	var replay_after := {}
	if restored:
		replay_before = native._native_stage.stage_stats()
		for i: int in range(CHECKPOINT_TICK, rows.size()):
			var row: Dictionary = rows[i]
			if not step_pair(native, reference, row.inputs, row.owner, true) or physical(reference) != row.physical:
				check("checkpoint replay tick %d" % row.tick, false, str(native.stage_backend_status()))
				break
			replayed += 1
		replay_after = native._native_stage.stage_stats()
	check("all 96 recorded continuation ticks replay exactly", replayed == TICKS - CHECKPOINT_TICK, str(replayed))
	var tape := FileAccess.open(out.path_join("interval-tape.bin"), FileAccess.WRITE)
	if tape != null:
		tape.store_var({rows = rows, native_checkpoint = cp_n, reference_checkpoint = cp_r})
		tape.close()
	check("interval tape retained", tape != null)
	var result := {requested_ticks = TICKS, completed_ticks = completed, checkpoint_tick = CHECKPOINT_TICK,
		replayed_ticks = replayed, native_identity = native.stage_backend_identity(), samples = samples,
		original_counters_before = counters_before, original_counters_after = counters_after,
		replay_counters_before = replay_before, replay_counters_after = replay_after}
	native.free()
	reference.free()
	finish(result)


func finish(result: Dictionary) -> void:
	result["checks"] = checks
	result["failures"] = failures
	result["failure_details"] = notes
	result["build_binary_sha256"] = receipt.get("binary_sha256", "")
	result["build_source_sha256"] = receipt.get("source_sha256", "")
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  ", true, true) + "\n")
		file.close()
	print("AV17_R5_NATIVE_MIX verdict=%s checks=%d failures=%d" % ["pass" if failures == 0 else "fail", checks, failures])
	quit(1 if failures else 0)
