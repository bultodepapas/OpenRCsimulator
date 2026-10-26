extends SceneTree
const Profile := preload("res://audio/mechanical_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Transfer := preload("res://workshop/profile_transfer.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var bindings := {format = Presentation.BINDINGS_FORMAT, version = 2,
		visual_family = "audio-fixture", model_manifest_sha256 = "a".repeat(64),
		paint_slots = [], marking_slots = [], smoke_slots = [], presentation_sources = [],
		presentation_engine_version = Presentation.PRESENTATION_ENGINE_VERSION, slots_sha256 = ""}
	for path: String in Presentation.PRESENTATION_SOURCE_PATHS:
		bindings.presentation_sources.append({path = path, sha256 = "a".repeat(64)})
	bindings = JSON.parse_string(JSON.stringify(bindings))
	bindings.slots_sha256 = Presentation.bindings_sha256(bindings)
	_check("exactly two servo and two retract choices", Profile.SERVO_TYPES.size() == 2 and Profile.RETRACT_TYPES.size() == 2)
	_check("default valid", Profile.validate(Profile.defaults()).ok)
	for old_version: int in [1, 2, 3]:
		var old := Presentation.defaults(bindings, old_version)
		var checked := Presentation.validate(old, bindings)
		_check("historical v%d remains canonical" % old_version, checked.ok and checked.profile == old and not old.has("mechanical_audio"))
		_check("historical v%d gets sound defaults without mutation" % old_version, Profile.resolve(old) == Profile.defaults() and not old.has("mechanical_audio"))
	var modern := Presentation.defaults(bindings)
	var standard_id := Presentation.identity(modern, bindings)
	_check("v4 default validates", not standard_id.is_empty())
	modern.mechanical_audio = {"servo_type": "high_torque", "servo_level": 0.35, "retract_type": "pneumatic"}
	var checked := Presentation.validate(modern, bindings)
	_check("config participates in presentation identity", checked.ok and checked.identity_sha256 != standard_id)
	var roundtrip := Presentation.validate(JSON.parse_string(JSON.stringify(modern, "", true, true)), bindings)
	_check("JSON roundtrip keeps canonical config", roundtrip.ok and roundtrip.identity_sha256 == checked.identity_sha256, str(roundtrip.get("errors", [])) + " " + str(checked.profile) + " -> " + str(roundtrip.get("profile", {})))
	for invalid: Variant in [null, [], {}, {servo_type = "other", servo_level = 1.0, retract_type = "electric"},
		{servo_type = "standard", servo_level = true, retract_type = "electric"},
		{servo_type = "standard", servo_level = INF, retract_type = "electric"},
		{servo_type = "standard", servo_level = -0.1, retract_type = "electric"},
		{servo_type = "standard", servo_level = 1.01, retract_type = "electric"},
		{servo_type = "standard", servo_level = 1.0, retract_type = "hydraulic"},
		{servo_type = "standard", servo_level = 1.0, retract_type = "electric", path = "anything"}]:
		var bad := modern.duplicate(true)
		bad.mechanical_audio = invalid
		_check("malformed mechanical config rejected", not Presentation.validate(bad, bindings).ok)
	for old_version: int in [2, 3, 4]:
		var destination := Presentation.defaults(bindings, old_version)
		var proposal := Transfer.propose(modern, bindings, destination, bindings)
		_check("copy to v%d preserves full mechanical config" % old_version, proposal.get("ok", false)
			and proposal.get("profile", {}).get("mechanical_audio", {}) == modern.mechanical_audio, str(proposal.get("errors", [])))
	print("Mechanical configuration: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _check(label: String, okay: bool, detail: String = "") -> void:
	checks += 1
	if not okay:
		failures += 1
		printerr("FAIL ", label, " ", detail)
