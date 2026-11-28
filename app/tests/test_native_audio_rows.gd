extends SceneTree
## NK-7f: the kernel's airborne contact rows equal GroundAudioModel._unloaded_rows built in GDScript, and its source
## kinematics equal flight_audio.gd snapshot's GDScript evaluation, bit for bit (values, types, key order, signed
## zeros), on random attitudes, velocities, rates, gear arms, propulsion offsets and thrust axes, with unnamed
## contacts, contacts without a position, malformed arms and no exhaust. Skips (passes) without the verified library.

const GroundModel := preload("res://audio/ground_audio_model.gd")
const FlightAudio := preload("res://audio/flight_audio.gd")
const Frames := preload("res://render/frames.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"audio_unloaded_rows"):
		print("NK7F_SKIP no native library with the audio rows")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	var row_mismatch := 0
	var kinematics_mismatch := 0
	var native_rows := 0
	var first := ""
	for i: int in 5000:
		var state := _state(rng)
		var contacts: Array = []
		for w: int in rng.randi_range(0, 4):
			var contact := {position = PackedFloat64Array([rng.randf_range(-1.0, 1.0), rng.randf_range(-0.8, 0.8),
				rng.randf_range(0.0, 0.6)])}
			if rng.randf() < 0.7:
				contact.name = ["main_left", "main_right", "tail", "nose"][w]
			if rng.randf() < 0.05:
				contact.erase("position") # no position: skipped
			if i % 997 == 3 and contact.has("position"):
				contact.position = PackedFloat64Array([1.0, 2.0]) # malformed: GDScript only
			contacts.append(contact)
		var attitude := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
		var base_velocity := M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2])
		var body_rate := state.slice(RB.RATE, RB.RATE + 3)
		var reference_load: float = rng.randf_range(1.0, 400.0)
		GroundModel.native_rows_enabled = true
		var native: Array[Dictionary] = []
		var malformed := false
		for contact: Dictionary in contacts:
			malformed = malformed or (contact.has("position") and (contact.position as PackedFloat64Array).size() != 3)
		if not malformed:
			native = GroundModel._unloaded_rows(contacts, state, attitude, base_velocity, body_rate, reference_load)
			native_rows += native.size()
		GroundModel.native_rows_enabled = false
		var reference: Array[Dictionary] = []
		if not malformed:
			reference = GroundModel._unloaded_rows(contacts, state, attitude, base_velocity, body_rate, reference_load)
		if var_to_bytes(native) != var_to_bytes(reference):
			row_mismatch += 1
			if first.is_empty():
				first = "rows %s vs %s" % [native, reference]
		var offset := PackedFloat64Array([rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)])
		var axis := PackedFloat64Array([1.0, rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)]) if i % 2 == 0 \
			else PackedFloat64Array()
		var k: PackedFloat64Array = FlightAudio._source_kinematics(state, offset, axis)
		var expected := _kinematics(state, offset, axis)
		var got: Array = [Vector3(k[0], k[1], k[2]), Vector3(k[3], k[4], k[5]), Vector3(k[6], k[7], k[8])] \
			if k.size() == 9 else []
		if var_to_bytes(got) != var_to_bytes(expected):
			kinematics_mismatch += 1
			if first.is_empty():
				first = "kinematics %s vs %s" % [got, expected]
	GroundModel.native_rows_enabled = true
	_check("native airborne rows equal the GDScript rows (%d rows)" % native_rows, row_mismatch == 0 and native_rows > 5000,
		"%d differ; %s" % [row_mismatch, first])
	_check("native source kinematics equal snapshot's GDScript evaluation", kinematics_mismatch == 0,
		"%d differ; %s" % [kinematics_mismatch, first])
	_check("a malformed offset answers empty", FlightAudio._source_kinematics(_state(rng), PackedFloat64Array([1.0]),
		PackedFloat64Array()).is_empty())
	print("native audio rows: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _state(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var q := Quaternion(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized(),
		rng.randf_range(-PI, PI))
	var norm: float = sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
	return PackedFloat64Array([rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-300.0, 0.0),
		rng.randf_range(-60.0, 60.0), rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0),
		q.w / norm, q.x / norm, q.y / norm, q.z / norm,
		rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0)])


## flight_audio.gd snapshot's GDScript evaluation of the source kinematics.
func _kinematics(s: PackedFloat64Array, offset: PackedFloat64Array, axis: PackedFloat64Array) -> Array:
	var attitude: PackedFloat64Array = M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var velocity: Vector3 = Frames.ned_to_render(Array(M.q_rotate(attitude, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))))
	var source_arm: PackedFloat64Array = M.v3(-offset[0], offset[1], -offset[2])
	var source_ned: PackedFloat64Array = M.add(s.slice(RB.POS, RB.POS + 3), M.q_rotate(attitude, source_arm))
	var source_velocity: Vector3 = velocity + Frames.ned_to_render(M.q_rotate(attitude,
		M.cross(s.slice(RB.RATE, RB.RATE + 3), source_arm)))
	var exhaust := Vector3.ZERO
	if not axis.is_empty():
		exhaust = Frames.ned_to_render(Array(M.q_rotate(attitude, M.v3(-axis[0], -axis[1], -axis[2]))))
	return [Frames.ned_to_render(source_ned), source_velocity, exhaust]


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
