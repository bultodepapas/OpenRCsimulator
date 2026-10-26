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
	_test_stock_lighting_drafts()
	_test_refusals()
	print("Presentation rebind and stock-lighting proposals: %d checks, %d failed" % [_checks, _failures])
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


func _test_stock_lighting_drafts() -> void:
	var current_bindings := _bindings_fixture()
	var old_bindings := _without_authored_layout(current_bindings)
	var stale_profile := _custom_profile(old_bindings)
	var stale_original := JSON.stringify(stale_profile)
	var stale_proposal: Dictionary = RebindProposal.propose_stock_lighting(stale_profile, current_bindings)
	_check("compatible stale profile can explicitly inherit current stock lighting", stale_proposal.get("ok", false),
		str(stale_proposal.get("errors", [])))
	if stale_proposal.get("ok", false):
		var stale_output: Dictionary = stale_proposal.get("profile", {})
		var stale_report: Dictionary = stale_proposal.get("report", {})
		var stale_before_nonlighting := _without_binding_lighting(Presentation.validate_stored(stale_profile).profile)
		var stale_after_nonlighting := _without_binding_lighting(stale_output)
		_check("stale stock proposal replaces only lighting and binding",
			stale_output.get("lighting", {}).get("selection", "") == "inherit"
			and stale_output.get("binding", {}).get("slots_sha256", "") == current_bindings.get("slots_sha256", "")
			and stale_after_nonlighting == stale_before_nonlighting,
			JSON.stringify(stale_after_nonlighting) + " != " + JSON.stringify(stale_before_nonlighting))
		_check("stock proposal requires review and a new saved identity",
			stale_proposal.get("requires_review", false) and stale_report.get("save_as_copy_only", false)
			and stale_report.get("stock_lighting_selected", false)
			and stale_report.get("rebound_fields", []) == ["binding", "lighting"])
	_check("stale stock proposal leaves source revision data unchanged", JSON.stringify(stale_profile) == stale_original)

	var unsupported := _custom_profile(current_bindings)
	unsupported["lighting"] = Presentation.LightingProfile.preset("custom")
	for zone: Dictionary in unsupported["lighting"].get("zones", []):
		zone["enabled"] = true
	var normal_review: Dictionary = RebindProposal.propose(unsupported, current_bindings)
	_check("normal review cannot repair same-pin lighting capability gaps", not normal_review.get("ok", true)
		and _errors_contain(normal_review, "already matches"))
	var unsupported_original := JSON.stringify(unsupported)
	var stock_proposal: Dictionary = RebindProposal.propose_stock_lighting(unsupported, current_bindings)
	_check("explicit stock action repairs required custom-lighting capability failure", stock_proposal.get("ok", false),
		str(stock_proposal.get("errors", [])))
	if stock_proposal.get("ok", false):
		var stock_output: Dictionary = stock_proposal.get("profile", {})
		var stock_before_nonlighting := _without_binding_lighting(Presentation.validate(unsupported, current_bindings).profile)
		var stock_after_nonlighting := _without_binding_lighting(stock_output)
		_check("same-pin stock proposal inherits lighting and preserves physical appearance data",
			stock_output.get("lighting", {}).get("selection", "") == "inherit"
			and stock_after_nonlighting == stock_before_nonlighting
			and stock_proposal.get("report", {}).get("rebound_fields", []) == ["lighting"],
			JSON.stringify(stock_after_nonlighting) + " != " + JSON.stringify(stock_before_nonlighting))
		_check("v4 stock copy keeps mechanical audio and outer schema",
			stock_output.get("version", 0) == Presentation.VERSION
			and stock_output.has("mechanical_audio")
			and stock_output.get("mechanical_audio", {}) == unsupported.get("mechanical_audio", {}))
	_check("same-pin stock action leaves source profile unchanged", JSON.stringify(unsupported) == unsupported_original)

	var required_lighting_missing := _custom_profile(current_bindings)
	required_lighting_missing.erase("lighting")
	var missing_original := JSON.stringify(required_lighting_missing)
	var ordinary_missing_review: Dictionary = RebindProposal.propose(required_lighting_missing, current_bindings)
	_check("ordinary review refuses a malformed required-lighting profile", not ordinary_missing_review.get("ok", true)
		and _errors_contain(ordinary_missing_review, "invalid"))
	var repaired_required_lighting: Dictionary = RebindProposal.propose_stock_lighting(required_lighting_missing, current_bindings)
	_check("explicit stock choice repairs only the missing required lighting field",
		repaired_required_lighting.get("ok", false), str(repaired_required_lighting.get("errors", [])))
	if repaired_required_lighting.get("ok", false):
		var repaired_output: Dictionary = repaired_required_lighting.get("profile", {})
		var repaired_after_nonlighting := _without_binding_lighting(repaired_output)
		var expected_repair := required_lighting_missing.duplicate(true)
		expected_repair["lighting"] = Presentation.LightingProfile.defaults()
		var repaired_before_nonlighting := _without_binding_lighting(Presentation.validate(expected_repair).profile)
		_check("required-lighting repair preserves all valid nonlighting selections",
			repaired_output.get("lighting", {}).get("selection", "") == "inherit"
			and repaired_after_nonlighting == repaired_before_nonlighting
			and repaired_required_lighting.get("report", {}).get("repaired_missing_or_invalid_lighting", false),
			JSON.stringify(repaired_after_nonlighting) + " != " + JSON.stringify(repaired_before_nonlighting))
	_check("required-lighting refusal and repair never mutate the stored source", JSON.stringify(required_lighting_missing) == missing_original)
	var roundtrip_missing: Variant = JSON.parse_string(JSON.stringify(required_lighting_missing))
	var roundtrip_repair: Dictionary = RebindProposal.propose_stock_lighting(roundtrip_missing, current_bindings)
	_check("JSON roundtrip still allows explicit repair of missing required lighting",
		roundtrip_repair.get("ok", false) and roundtrip_repair.get("profile", {}).get("lighting", {}).get("selection", "") == "inherit",
		str(roundtrip_repair.get("errors", [])))

	var future_lighting := _custom_profile(current_bindings)
	future_lighting.lighting.version = Presentation.LightingProfile.VERSION + 1
	var future_lighting_original := JSON.stringify(future_lighting)
	var future_lighting_refusal: Dictionary = RebindProposal.propose_stock_lighting(future_lighting, current_bindings)
	_check("stock action refuses a future lighting payload without rewriting it",
		not future_lighting_refusal.get("ok", true) and _errors_contain(future_lighting_refusal, "newer lighting profile"))
	_check("future lighting payload remains unchanged", JSON.stringify(future_lighting) == future_lighting_original)
	var roundtrip_future_lighting: Variant = JSON.parse_string(future_lighting_original)
	var roundtrip_future_refusal: Dictionary = RebindProposal.propose_stock_lighting(roundtrip_future_lighting, current_bindings)
	_check("JSON roundtrip cannot bypass a future lighting payload refusal",
		not roundtrip_future_refusal.get("ok", true) and _errors_contain(roundtrip_future_refusal, "newer lighting profile"))

	var legacy_current := Presentation.defaults(current_bindings, 3)
	legacy_current["lighting"] = Presentation.LightingProfile.preset("festival")
	var legacy_stock: Dictionary = RebindProposal.propose_stock_lighting(legacy_current, current_bindings)
	_check("v3 stock draft keeps its supported outer version and fields", legacy_stock.get("ok", false)
		and legacy_stock.get("profile", {}).get("version", 0) == 3
		and not legacy_stock.get("profile", {}).has("mechanical_audio"))


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
	var stock_smoke_refusal: Dictionary = RebindProposal.propose_stock_lighting(smoke_profile, current_bindings)
	_check("stock draft preserves the existing refusal for smoke on changed pins", not stock_smoke_refusal.get("ok", true)
		and _errors_contain(stock_smoke_refusal, "original companion"))

	var future_profile := old_profile.duplicate(true)
	future_profile["version"] = Presentation.VERSION + 1
	future_profile["future_field"] = "leave unchanged"
	var future_original := JSON.stringify(future_profile)
	var future_refusal: Dictionary = RebindProposal.propose(future_profile, current_bindings)
	_check("proposal refuses unknown future profile schemas", not future_refusal.get("ok", true)
		and _errors_contain(future_refusal, "newer presentation profile"))
	var future_stock_refusal: Dictionary = RebindProposal.propose_stock_lighting(future_profile, current_bindings)
	_check("stock draft refuses future outer versions without downcasting", not future_stock_refusal.get("ok", true)
		and _errors_contain(future_stock_refusal, "newer presentation profile"))
	var roundtrip_future_outer: Variant = JSON.parse_string(JSON.stringify(future_profile))
	var roundtrip_future_outer_refusal: Dictionary = RebindProposal.propose_stock_lighting(roundtrip_future_outer, current_bindings)
	_check("JSON roundtrip preserves future outer-profile refusal", not roundtrip_future_outer_refusal.get("ok", true)
		and _errors_contain(roundtrip_future_outer_refusal, "newer presentation profile"))
	var removed_slot_stock_refusal: Dictionary = RebindProposal.propose_stock_lighting(old_profile, removed_slot)
	_check("stock draft refuses when another saved selection is missing", not removed_slot_stock_refusal.get("ok", true)
		and _errors_contain(removed_slot_stock_refusal, "body"))
	_check("all refused proposals leave their source profile unchanged", JSON.stringify(old_profile) == original)
	_check("future profile remains unchanged after stock refusal", JSON.stringify(future_profile) == future_original)


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


func _without_binding_lighting(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	result.erase("binding")
	result.erase("lighting")
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
