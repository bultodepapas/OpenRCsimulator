extends SceneTree
## Focused checks for the nonmutating Workshop presentation rebind proposal.

const Presentation := preload("res://workshop/presentation.gd")
const RebindProposal := preload("res://workshop/presentation_rebind.gd")
const PresentationSources := preload("res://render/presentation_sources.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_rebind_preserves_user_state()
	_test_inherited_lighting_and_noop()
	_test_refusals()
	print("Presentation rebind proposal: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_rebind_preserves_user_state() -> void:
	var current_bindings := _bindings_fixture()
	var old_bindings := _without_authored_layout(current_bindings)
	var profile := _custom_profile(old_bindings)
	var original := JSON.stringify(profile)
	var old_stored: Dictionary = Presentation.validate_stored(profile)
	_check("stale pinned profile remains structurally readable", old_stored.get("ok", false)
		and not old_stored.get("available", true), str(old_stored.get("errors", [])))

	var proposal: Dictionary = RebindProposal.propose(profile, current_bindings)
	_check("same-family and same-model proposal succeeds", proposal.get("ok", false), str(proposal.get("errors", [])))
	if not proposal.get("ok", false):
		return
	var report: Dictionary = proposal.get("report", {})
	var output: Dictionary = proposal.get("profile", {})
	var expected_current: Dictionary = Presentation.validate(Presentation.defaults(current_bindings), current_bindings).profile
	_check("proposal requires an explicit review", proposal.get("requires_review", false)
		and report.get("requires_review", false))
	_check("proposal is copy-only and admits unknown descriptor equivalence",
		report.get("save_as_copy_only", false) and report.get("descriptor_equivalence_proven", true) == false)
	_check("proposal rebinds to current companion pins", output.get("binding", {}) == expected_current.get("binding", {}))
	_check("proposal reports authored layout version", report.get("lighting_layout_version", 0) == 1)
	_check("proposal changes only binding pins", _without_binding(output) == _without_binding(old_stored.profile))
	_check("proposal preserves original profile value", JSON.stringify(profile) == original)


func _test_inherited_lighting_and_noop() -> void:
	var current_bindings := _bindings_fixture()
	var old_bindings := _without_authored_layout(current_bindings)
	var inherited := Presentation.defaults(old_bindings)
	var proposal: Dictionary = RebindProposal.propose(inherited, current_bindings)
	_check("empty inherited-lighting profile can be proposed", proposal.get("ok", false), str(proposal.get("errors", [])))
	if proposal.get("ok", false):
		_check("inherited lighting remains inherited", proposal.profile.get("lighting", {}).get("selection", "") == "inherit")
		_check("empty profile's non-binding fields are unchanged", _without_binding(proposal.profile) == _without_binding(inherited))

	var already_current := Presentation.defaults(current_bindings)
	var no_op: Dictionary = RebindProposal.propose(already_current, current_bindings)
	_check("already-current profile does not create a no-op proposal", not no_op.get("ok", true)
		and _errors_contain(no_op, "already matches"))


func _test_refusals() -> void:
	var current_bindings := _bindings_fixture()
	var old_profile := _custom_profile(_without_authored_layout(current_bindings))
	var original := JSON.stringify(old_profile)

	var other_model := current_bindings.duplicate(true)
	other_model["model_manifest_sha256"] = "b".repeat(64)
	_rehash(other_model)
	var physical_refusal: Dictionary = RebindProposal.propose(old_profile, other_model)
	_check("proposal refuses changed physical model identity", not physical_refusal.get("ok", true)
		and _errors_contain(physical_refusal, "physical model manifest"))

	var other_family := current_bindings.duplicate(true)
	other_family["visual_family"] = "other-fixture-aircraft"
	_rehash(other_family)
	var family_refusal: Dictionary = RebindProposal.propose(old_profile, other_family)
	_check("proposal refuses changed visual family", not family_refusal.get("ok", true)
		and _errors_contain(family_refusal, "visual family"))

	var removed_slot := current_bindings.duplicate(true)
	for index: int in range(removed_slot["paint_slots"].size() - 1, -1, -1):
		if str(removed_slot["paint_slots"][index].get("id", "")) == "body":
			removed_slot["paint_slots"].remove_at(index)
	_rehash(removed_slot)
	var missing_refusal: Dictionary = RebindProposal.propose(old_profile, removed_slot)
	_check("proposal rejects selections missing from current companion", not missing_refusal.get("ok", true)
		and _errors_contain(missing_refusal, "body"))

	var smoke_profile := old_profile.duplicate(true)
	smoke_profile["smoke"] = [_smoke_entry("old_smoke")]
	var smoke_refusal: Dictionary = RebindProposal.propose(smoke_profile, current_bindings)
	_check("proposal refuses smoke without original companion", not smoke_refusal.get("ok", true)
		and _errors_contain(smoke_refusal, "original companion"))

	var future_profile := old_profile.duplicate(true)
	future_profile["version"] = Presentation.VERSION + 1
	future_profile["future_field"] = "leave unchanged"
	var future_refusal: Dictionary = RebindProposal.propose(future_profile, current_bindings)
	_check("proposal refuses unknown future profile schemas", not future_refusal.get("ok", true)
		and _errors_contain(future_refusal, "newer presentation profile"))
	_check("all refused proposals leave their source profile unchanged", JSON.stringify(old_profile) == original)


func _custom_profile(bindings: Dictionary) -> Dictionary:
	var profile: Dictionary = Presentation.defaults(bindings)
	profile["paint"] = [{"slot": "body", "color": "#A13BCC", "pattern": "solid", "accent": "none"}]
	profile["markings"] = [{"slot": "registration", "text": "NÑ-24", "color": "#00BEEFFF"}]
	profile["lighting"] = Presentation.LightingProfile.preset("neon_rgb")
	profile["visual_seed"] = 73
	return profile


func _bindings_fixture() -> Dictionary:
	var bindings: Dictionary = {
		"format": Presentation.BINDINGS_FORMAT,
		"version": 4,
		"visual_family": "fixture-aircraft",
		"model_manifest_sha256": "a".repeat(64),
		"paint_slots": [
			{"id": "body", "label": "Body", "targets": [
				{"node_path": "airplane/body", "surface": 0, "kind": "standard_albedo"}]},
			{"id": "wing", "label": "Wing", "targets": [
				{"node_path": "airplane/wing", "surface": 0, "kind": "standard_albedo"}]},
		],
		"marking_slots": [{"id": "registration", "label": "Registration", "max_chars": 12, "targets": [
			{"node_path": "airplane/body", "position_m": [0.0, 0.0, 0.0], "direction": [-1.0, 0.0, 0.0],
				"up": [0.0, 1.0, 0.0], "width_m": 0.5, "height_m": 0.1}]}],
		"smoke_slots": [],
		"presentation_engine_version": Presentation.PRESENTATION_ENGINE_VERSION,
		"presentation_sources": PresentationSources.current_records(3),
		"source_proof_version": 3,
		"lighting_layout": {
			"version": 1,
			"anchors": [{"id": "nav_left", "node_path": ".", "position_m": [-0.5, 0.1, 0.0], "gear_gated": false}],
			"strips": [{"id": "strip_left", "node_path": ".", "points_m": [[-0.5, 0.0, 0.0], [-0.4, 0.0, 0.0]],
				"face": [0.0, 1.0, 0.0], "width_m": 0.015}],
		},
		"slots_sha256": "",
	}
	_rehash(bindings)
	return bindings


func _without_authored_layout(bindings: Dictionary) -> Dictionary:
	var result := bindings.duplicate(true)
	result["version"] = 3
	result.erase("lighting_layout")
	_rehash(result)
	return result


func _rehash(bindings: Dictionary) -> void:
	bindings["slots_sha256"] = Presentation.bindings_sha256(bindings)


func _without_binding(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	result.erase("binding")
	return result


func _smoke_entry(slot: String) -> Dictionary:
	return {
		"slot": slot, "enabled": true, "color": "#FFFFFF", "amount": 0.75,
		"width_m": 0.5, "lifetime_s": 6.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0,
		"palette": [], "step_s": 0.0,
	}


func _errors_contain(result: Dictionary, needle: String) -> bool:
	for message: Variant in result.get("errors", []):
		if str(message).to_lower().contains(needle.to_lower()):
			return true
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
