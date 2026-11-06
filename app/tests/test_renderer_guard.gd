extends SceneTree
## DT-MAC-05b: post-initialization renderer recovery decisions, persistence and confirmation.

const RendererGuard := preload("res://app_state/renderer_guard.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _facts(overrides := {}) -> Dictionary:
	var base := {method = "mobile", standard_method = "mobile", profile = "", headless = false, build = "0.1.10|abc|4.8"}
	base.merge(overrides, true)
	return base


func run() -> void:
	_test_decisions()
	_test_metalfx_decisions()
	await _test_persistence_and_confirmation()
	print("renderer guard: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_decisions() -> void:
	var pending_old := {pending = {method = "mobile", build = "old"}}
	for case: Dictionary in [
			{name = "Compatibility is never guarded", facts = {method = "gl_compatibility", standard_method = "gl_compatibility"}},
			{name = "headless is never guarded", facts = {headless = true}},
			{name = "High restart is not the guarded default", facts = {method = "forward_plus", profile = "high"}},
			{name = "an explicit non-default renderer is not guarded", facts = {method = "forward_plus"}},
			{name = "an unknown build is not guarded", facts = {build = ""}}]:
		var result := RendererGuard.decide(_facts(case.facts), pending_old)
		check(case.name, result.action == "none" and result.state == pending_old)
	var first := RendererGuard.decide(_facts(), {})
	check("first RD launch arms a pending marker", first.action == "guard"
		and first.state.pending == {method = "mobile", build = "0.1.10|abc|4.8"} and not first.state.has("failed"))
	var crashed := RendererGuard.decide(_facts(), first.state)
	check("an unconfirmed launch of the same build falls back", crashed.action == "fallback"
		and crashed.state.failed == {method = "mobile", build = "0.1.10|abc|4.8"} and not crashed.state.has("pending"))
	var again := RendererGuard.decide(_facts(), crashed.state)
	check("the failure persists for that build without a new marker", again.action == "fallback"
		and not again.state.has("pending"))
	var upgraded := RendererGuard.decide(_facts({build = "0.1.11|def|4.8"}), crashed.state)
	check("a new build retries the RD renderer once", upgraded.action == "guard"
		and upgraded.state.pending.build == "0.1.11|def|4.8")
	var stale := RendererGuard.decide(_facts(), {pending = {method = "mobile", build = "other"}})
	check("a pending marker from another build is not a failure", stale.action == "guard"
		and not stale.state.has("failed"))
	var malformed := RendererGuard.decide(_facts(), {pending = "garbage", failed = 7})
	check("malformed records are ignored", malformed.action == "guard" and not malformed.state.has("failed"))
	var gl_after_fallback := RendererGuard.decide(_facts({method = "gl_compatibility"}), crashed.state)
	check("the Compatibility fallback session writes no marker", gl_after_fallback.action == "none"
		and not gl_after_fallback.state.has("pending"))


func _test_metalfx_decisions() -> void:
	var build := "0.1.10|abc|4.8"
	var crashed := RendererGuard.decide_metalfx(build, {metalfx_pending = {build = build}})
	check("an unconfirmed MetalFX session blocks MetalFX for that build", crashed.blocked
		and crashed.state.metalfx_failed == {build = build} and not crashed.state.has("metalfx_pending"))
	check("the MetalFX block persists for that build", RendererGuard.decide_metalfx(build, crashed.state).blocked)
	var newer := RendererGuard.decide_metalfx("0.1.11|def|4.8", crashed.state)
	check("a new build may try MetalFX again", not newer.blocked)
	var stale := RendererGuard.decide_metalfx(build, {metalfx_pending = {build = "old"}})
	check("another build's MetalFX marker is dropped, not a failure", not stale.blocked
		and not stale.state.has("metalfx_pending") and not stale.state.has("metalfx_failed"))
	check("no build never blocks", not RendererGuard.decide_metalfx("", {metalfx_failed = {build = ""}}).blocked)
	var kept := RendererGuard.decide(_facts(), {metalfx_failed = {build = build}})
	check("renderer decisions keep MetalFX records", kept.state.get("metalfx_failed", {}) == {build = build})


func _test_persistence_and_confirmation() -> void:
	var path := "user://test_renderer_guard_%d.cfg" % Time.get_ticks_usec()
	RendererGuard.save_state(path, {pending = {method = "mobile", build = "b"}, failed = {method = "mobile", build = "a"}})
	var loaded := RendererGuard.load_state(path)
	check("state round-trips", loaded.pending == {method = "mobile", build = "b"} and loaded.failed.build == "a")
	RendererGuard.confirm(path)
	loaded = RendererGuard.load_state(path)
	check("confirm clears only the pending marker", not loaded.has("pending") and loaded.failed.build == "a")
	check("a missing file loads as empty", RendererGuard.load_state(path + ".missing").is_empty())
	RendererGuard.save_state(path, {pending = {method = "mobile", build = "b"}, metalfx_pending = {build = "b"}})
	RendererGuard.clear_renderer_pending(path)
	check("RD responsiveness does not confirm MetalFX", not RendererGuard.load_state(path).has("pending")
		and RendererGuard.load_state(path).has("metalfx_pending"))
	RendererGuard.confirm(path)
	check("a clean quit clears both markers", not RendererGuard.load_state(path).has("metalfx_pending"))
	# Exercise the callback directly in headless mode: the old activation must not clear a newer marker.
	var first_activation := RendererGuard._arm_metalfx(path, "b")
	RendererGuard._disarm_metalfx(path)
	var second_activation := RendererGuard._arm_metalfx(path, "b")
	RendererGuard._confirm_metalfx_activation(path, first_activation)
	check("a stale MetalFX confirmer cannot clear the next activation",
		RendererGuard.load_state(path).get("metalfx_pending", {}).get("activation", -1) == second_activation)
	RendererGuard._confirm_metalfx_activation(path, second_activation)
	check("the current MetalFX confirmer clears its own marker", not RendererGuard.load_state(path).has("metalfx_pending"))
	var third_activation := RendererGuard._arm_metalfx(path, "b")
	RendererGuard.save_state(path, {metalfx_pending = {build = "b", activation = third_activation + 1}})
	RendererGuard._confirm_metalfx_activation(path, third_activation)
	check("a confirmer cannot clear a marker it does not own", RendererGuard.load_state(path).has("metalfx_pending"))
	RendererGuard._disarm_metalfx(path)
	var previous_block := RendererGuard.MetalFX.blocked_reason
	var impossible_path := path + "/pending.cfg" # its parent is the existing regular file, so saving must fail
	var refused_activation := RendererGuard._arm_metalfx(impossible_path, "b")
	check("a failed marker write refuses activation and leaves the guard disarmed",
		refused_activation == -1 and not RendererGuard._metalfx_armed
		and RendererGuard.MetalFX.blocked_reason == RendererGuard.METALFX_STORAGE_REASON)
	var blocked_caps := RendererGuard.MetalFX.from_facts({blocked = RendererGuard.MetalFX.blocked_reason,
		headless = false, method = "mobile", driver = "metal", rd_available = true,
		metalfx_spatial_mode = 101, metalfx_spatial_supported = true})
	check("a marker storage failure disables an otherwise supported MetalFX provider",
		not blocked_caps.metalfx_spatial and blocked_caps.metalfx_spatial_reason == RendererGuard.METALFX_STORAGE_REASON)
	RendererGuard._confirm_metalfx_activation(path, third_activation)
	check("a callback from before the failed activation cannot rearm the guard", not RendererGuard._metalfx_armed)
	RendererGuard.MetalFX.blocked_reason = previous_block
	var expected := ConfigFile.new()
	expected.set_value(RendererGuard.SECTION, "metalfx_pending", {build = "b"})
	var partial := ConfigFile.new()
	partial.set_value(RendererGuard.SECTION, "failed", {build = "a"})
	partial.save(path)
	check("a readable partial state cannot stand in for a persisted marker", not RendererGuard._saved_state_matches(path, expected))
	expected.save(path)
	check("the complete marker passes readback verification", RendererGuard._saved_state_matches(path, expected))
	var quality := {provider = "metalfx_spatial", mode = 101, scale = 2.0 / 3.0, output = Vector2i(2560, 1600)}
	var initial_configuration := RendererGuard._prepare_metalfx(path, "b", quality)
	RendererGuard._confirm_metalfx_activation(path, initial_configuration)
	check("identical confirmed reconstruction does not rearm on unrelated settings",
		RendererGuard._prepare_metalfx(path, "b", quality) == 0 and not RendererGuard.load_state(path).has("metalfx_pending"))
	var resized := quality.duplicate(true)
	resized.scale = 0.85
	resized.output = Vector2i(1920, 1200)
	var previous_confirmer := RendererGuard.confirmer_for(path)
	root.add_child(previous_confirmer)
	RendererGuard._metalfx_confirmer = weakref(previous_confirmer)
	var resized_activation := RendererGuard._prepare_metalfx(path, "b", resized)
	check("a descriptor change retires the previous timer instead of accumulating resize timers",
		previous_confirmer.is_queued_for_deletion() and not previous_confirmer.is_processing())
	RendererGuard._confirm_metalfx_activation(path, initial_configuration)
	check("a changed MetalFX descriptor rearms and rejects the previous callback",
		resized_activation > initial_configuration
		and RendererGuard.load_state(path).get("metalfx_pending", {}).get("activation", -1) == resized_activation)
	RendererGuard._confirm_metalfx_activation(path, resized_activation)
	check("the changed descriptor confirms only its own marker", not RendererGuard.load_state(path).has("metalfx_pending"))
	RendererGuard._disarm_metalfx(path)
	RendererGuard.save_state(path, {failed = {method = "mobile", build = "a"}})
	# This SceneTree runs headless: begin() must neither restart nor arm a marker.
	check("headless begin never restarts", not RendererGuard.begin(self, path))
	await process_frame
	check("headless begin arms no confirmer", root.get_node_or_null("RendererGuardConfirm") == null
		and not RendererGuard.load_state(path).has("pending"))
	# The confirmer clears a pending marker after the frame and time thresholds.
	RendererGuard.save_state(path, {pending = {method = "mobile", build = "b"}})
	var confirmer := RendererGuard.confirmer_for(path)
	check("the confirmer runs while the tree is paused", confirmer.process_mode == Node.PROCESS_MODE_ALWAYS)
	paused = true
	root.add_child(confirmer)
	await create_timer(0.2).timeout
	check("the confirmer waits for its thresholds", RendererGuard.load_state(path).has("pending"))
	var deadline := Time.get_ticks_msec() + int(RendererGuard.CONFIRM_SECONDS * 1000.0) + 3000
	while is_instance_valid(confirmer) and Time.get_ticks_msec() < deadline:
		await process_frame
	paused = false
	check("the confirmer clears the marker and frees itself", not is_instance_valid(confirmer)
		and not RendererGuard.load_state(path).has("pending"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
