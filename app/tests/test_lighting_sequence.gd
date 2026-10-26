extends SceneTree

const Sequence := preload("res://workshop/lighting_sequence.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
var failures := 0

func _initialize() -> void:
	var base := Profile.preset("neon_rgb")
	base.orientation_lock = true
	var original := base.duplicate(true)
	var added := Sequence.add_cue(base)
	check("add creates a sequence without mutating input", added.ok and base == original)
	if not added.ok:
		quit(1)
		return
	var profile: Dictionary = added.profile
	var first_id: String = added.selected_id
	check("new cue targets an enabled strip and preserves navigation", str(profile.sequence[0].zone_ids[0]).begins_with("strip_")
		and profile.zones[0] == base.zones[0] and Profile.validate(profile).ok)
	var second := Sequence.duplicate_cue(profile, first_id)
	check("duplicate assigns a unique stable ID", second.ok and second.selected_id != first_id and profile.sequence.size() == 1)
	var moved := Sequence.move_cue(second.profile, second.selected_id, -1)
	check("move changes cue ordering while retaining IDs", moved.ok and moved.profile.sequence[0].id == second.selected_id)
	check("moving past an endpoint is rejected", not Sequence.move_cue(moved.profile, second.selected_id, -1).ok)
	var state := Sequence.editor_state(profile, first_id)
	state.duration_text = "2.5"
	state.period_text = "0.5"
	state.pattern_id = "wave"
	state.color_text = ["#123456", "#ABCDEF"]
	var applied := Sequence.apply_cue(profile, state)
	check("timing uses the established 240 Hz clock", applied.ok and applied.profile.sequence[0].duration_ticks == 600
		and applied.profile.sequence[0].pattern.period_ticks == 120)
	for invalid: String in ["", "nan", "inf", "-1", "0", "1e100", "61", "1.2.3"]:
		var bad := state.duplicate(true)
		bad.duration_text = invalid
		check("invalid duration rejected: " + invalid, not Sequence.apply_cue(profile, bad).ok)
	var pending := state.duplicate(true)
	pending.color_text = ["#12"]
	pending.period_text = "0."
	check("recovery preserves invalid bounded text without accepting a profile", Sequence.validate_editor_state(pending).ok
		and not Sequence.apply_cue(profile, pending).ok)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(pending))
	check("pending editor JSON roundtrip is lossless", Sequence.validate_editor_state(roundtrip).value == pending)
	pending.duration_text = "x".repeat(25)
	check("recovery bounds numeric buffers", not Sequence.validate_editor_state(pending).ok)
	pending = state.duplicate(true)
	pending.zone_ids = ["nav_left"]
	check("locked navigation cannot become a show cue", not Sequence.apply_cue(profile, pending).ok)
	pending.zone_ids = ["strip_left", "strip_left"]
	check("duplicate targets rejected", not Sequence.apply_cue(profile, pending).ok)
	pending.zone_ids = ["strip_left"]
	pending.effect_anchor_ids = ["vfx_tip_left"]
	check("unconfigured effects cannot be targeted", not Sequence.apply_cue(profile, pending).ok)
	var removed := Sequence.remove_cue(profile, first_id)
	check("last cue removal removes orphan sequence patterns", removed.ok and removed.profile.sequence.is_empty()
		and removed.profile.zones.all(func(zone: Dictionary) -> bool: return zone.pattern.id != "sequence"))
	state.duration_text = "60"
	var full := Sequence.apply_cue(profile, state)
	check("sequence duration cap blocks both add and duplicate", full.ok and not Sequence.add_cue(full.profile).ok
		and not Sequence.duplicate_cue(full.profile, first_id).ok)
	state.duration_text = "0.1"
	var many := Sequence.apply_cue(profile, state)
	for index in 31:
		many = Sequence.duplicate_cue(many.profile, first_id)
	check("cue count cap is enforced", many.ok and many.profile.sequence.size() == 32
		and not Sequence.add_cue(many.profile).ok and not Sequence.duplicate_cue(many.profile, first_id).ok)
	check("inherited lighting is not implicitly replaced", not Sequence.add_cue(Profile.defaults()).ok)
	var festival := Profile.preset("festival")
	var festival_state := Sequence.editor_state(festival, "")
	check("existing Festival cues remain editable", Sequence.apply_cue(festival, festival_state).ok)
	print("lighting sequence: %d failures" % failures)
	quit(1 if failures else 0)

func check(label: String, passed: bool) -> void:
	if passed:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
